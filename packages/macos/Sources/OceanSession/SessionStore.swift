import Foundation
import Observation
import OceanKit

private let localPrefix = "local:"

private func isLocalID(_ id: String) -> Bool {
  id.hasPrefix(localPrefix)
}

@Observable
@MainActor
public final class SessionStore {
  public private(set) var sessionID: String
  public private(set) var directory: String?

  public private(set) var messages: [SessionMessage] = []
  public private(set) var loading = false
  public private(set) var error: String?
  public private(set) var sending = false
  public private(set) var busy = false
  public private(set) var statusNote: String?
  public private(set) var activeAssistantID: String?

  public private(set) var permissions: [PermissionRequest] = []
  public private(set) var questions: [QuestionRequest] = []
  public private(set) var forms: [FormRequest] = []
  public private(set) var queued: [InboxItem] = []
  public var deliveryMode: InboxDelivery = .queue

  public private(set) var title: String?
  public private(set) var agent: String?
  public private(set) var model: ModelRef?

  public private(set) var agents: [AgentInfo] = []
  public private(set) var models: [ModelInfo] = []
  public private(set) var commands: [CommandInfo] = []

  public private(set) var mcpServers: [McpServer]?
  public private(set) var mcpLoading = false
  public private(set) var mcpError: String?
  public private(set) var mcpActionError: String?
  public private(set) var mcpPending: Set<String> = []

  public private(set) var todos: [TodoItem] = []
  public private(set) var totalTokens: Int = 0
  public private(set) var updateTick: UInt64 = 0

  @ObservationIgnored private let connection: ConnectionStore
  @ObservationIgnored private var eventSubscription: EventSubscription?
  @ObservationIgnored private var localCounter = 0
  @ObservationIgnored private var loadToken = 0
  @ObservationIgnored private var syncing = false
  @ObservationIgnored private var compactionNoteID: String?

  @ObservationIgnored private var messageIndexMap: [String: Int] = [:]
  @ObservationIgnored private var partIndexMap: [String: (msgIdx: Int, partIdx: Int)] = [:]
  @ObservationIgnored private var toolCallIndexMap: [String: (msgIdx: Int, partIdx: Int)] = [:]
  @ObservationIgnored private var pendingEvents: [ServerEvent] = []
  @ObservationIgnored private var tickTask: Task<Void, Never>?

  public init(sessionID: String, directory: String? = nil, connection: ConnectionStore? = nil) {
    let conn = connection ?? ConnectionStore.shared
    self.sessionID = sessionID
    self.directory = directory
    self.connection = conn

    self.eventSubscription = conn.onServerEvent { [weak self] event in
      self?.handleEvent(event)
    }

    load()
  }

  public var isStreaming: Bool { sending || busy }

  public var blockingPermission: PermissionRequest? { permissions.first }
  public var blockingQuestion: QuestionRequest? { questions.first }
  public var blockingForm: FormRequest? { forms.first }

  private func rebuildIndexMaps() {
    var msgMap: [String: Int] = [:]
    var partMap: [String: (msgIdx: Int, partIdx: Int)] = [:]
    var toolMap: [String: (msgIdx: Int, partIdx: Int)] = [:]

    for (mIdx, message) in messages.enumerated() {
      msgMap[message.info.id] = mIdx
      for (pIdx, part) in message.parts.enumerated() {
        partMap[part.id] = (mIdx, pIdx)
        if let callID = part.callID {
          toolMap[callID] = (mIdx, pIdx)
        }
      }
    }
    self.messageIndexMap = msgMap
    self.partIndexMap = partMap
    self.toolCallIndexMap = toolMap
  }

  private func rebuildIndex() {
    rebuildIndexMaps()
    updateTodos()
    updateTotalTokens()
  }

  public static func extractTodos(from input: [String: JSONValue]) -> [TodoItem] {
    extractTodos(from: JSONValue.object(input))
  }

  public static func extractTodos(from input: JSONValue) -> [TodoItem] {
    let rawTodos = input["todos"].array
    guard !rawTodos.isEmpty else { return [] }
    var items: [TodoItem] = []
    for (idx, entry) in rawTodos.enumerated() {
      guard let content = entry["content"].string else { continue }
      let itemID = entry["id"].string ?? "todo-\(idx)"
      let rawStatus = entry["status"].string ?? "pending"
      let status = TodoStatus(rawValue: rawStatus) ?? .pending
      items.append(TodoItem(id: itemID, content: content, status: status))
    }
    return items
  }

  private func updateTodos() {
    for message in messages.reversed() {
      for part in message.parts.reversed() {
        guard part.type == .tool, part.tool == "todowrite" else { continue }
        if let state = part.state, let input = state.input {
          let items = Self.extractTodos(from: input)
          if !items.isEmpty {
            if self.todos != items { self.todos = items }
            return
          }
        }
      }
    }
    if !self.todos.isEmpty { self.todos = [] }
  }

  private func updateTotalTokens() {
    var count = 0
    for msg in messages {
      if let t = msg.info.tokens {
        count += (t.input ?? 0) + (t.output ?? 0) + (t.reasoning ?? 0)
      }
    }
    if self.totalTokens != count {
      self.totalTokens = count
    }
  }

  // MARK: - Load & Sync

  public func load() {
    let currentID = sessionID
    let currentDir = directory
    loadToken += 1
    let token = loadToken

    loading = true
    error = nil

    Task {
      do {
        let client = try connection.requireClient()
        // Explicit child tasks, not `async let`: on this Swift 6.2 runtime the
        // async-let storage traps if the parent task is torn down mid-flight.
        let historyTask = Task { (try? await client.listMessages(currentID)) ?? [] }
        let detailTask = Task { try? await client.getSession(currentID) }
        let statusesTask = Task { try? await client.getSessionStatuses() }
        let pendingTask = Task { (try? await client.listPermissions(currentID)) ?? [] }
        let inboxTask = Task { (try? await client.listInbox(currentID)) ?? [] }
        let questionsTask = Task { (try? await client.listQuestions(currentID)) ?? [] }
        let formsTask = Task { (try? await client.listForms(currentID)) ?? [] }
        let agentsTask = Task { (try? await client.listAgents(currentDir)) ?? [] }
        let modelsTask = Task { (try? await client.listModels(currentDir)) ?? [] }
        let commandsTask = Task { (try? await client.listCommands(currentDir)) ?? [] }

        let history = await historyTask.value
        let detail = await detailTask.value
        let statuses = await statusesTask.value
        let pending = await pendingTask.value
        let inbox = await inboxTask.value
        let asked = await questionsTask.value
        let opened = await formsTask.value
        let agentList = await agentsTask.value
        let modelList = await modelsTask.value
        let commandList = await commandsTask.value

        guard token == self.loadToken && self.sessionID == currentID else { return }

        self.mergeHistory(history)
        self.permissions = pending
        self.questions = asked.filter { $0.sessionID == currentID }
        self.forms = opened.filter { $0.sessionID == currentID }
        self.queued = inbox
        self.agents = agentList
        self.models = modelList
        self.commands = commandList

        if let title = detail?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
          self.title = title
        }

        self.agent = detail?.agent
        if let m = detail?.model, let modelRef = m.ref {
          self.model = modelRef
        }

        if self.agent == nil || self.model == nil {
          if let defaults = try? await client.getDefaults(currentDir) {
            if self.agent == nil { self.agent = defaults.agent }
            if self.model == nil { self.model = defaults.model }
          }
        }

        if let status = statuses?[currentID] {
          self.busy = status == "busy" || status == "retry"
        }
      } catch {
        if token == self.loadToken {
          self.error = toUserMessage(error)
        }
      }
      if token == self.loadToken {
        self.loading = false
      }
    }
  }

  public func sync() {
    guard !syncing else { return }
    syncing = true
    let currentID = sessionID

    Task {
      defer { self.syncing = false }
      guard let client = try? self.connection.requireClient() else { return }
      guard let history = try? await client.listMessages(currentID) else { return }
      guard self.sessionID == currentID else { return }
      self.mergeHistory(history)
    }
  }

  public func reload() {
    load()
  }

  // MARK: - Transcript updates

  private func adopt(_ message: MessageWithParts) -> SessionMessage {
    SessionMessage(
      info: message.info,
      parts: message.parts,
      delivery: .sent,
      failure: nil,
      draft: nil,
      draftAttachments: []
    )
  }

  private func findMessageIndex(_ id: String) -> Int? {
    messageIndexMap[id]
  }

  private func messageText(_ message: SessionMessage) -> String {
    message.parts
      .filter { $0.type == .text }
      .compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .joined(separator: "\n\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func isOptimisticMatch(
    draftText: String,
    draftAttachmentsCount: Int,
    timeCreated: Int,
    serverText: String,
    serverFilesCount: Int,
    serverTimeCreated: Int
  ) -> Bool {
    let timeDiff = serverTimeCreated >= (timeCreated - 5000)
    return serverText == draftText && serverFilesCount == draftAttachmentsCount && timeDiff
  }

  private func reconcileOptimistic() {
    let localUsers = messages.filter { isLocalID($0.info.id) && $0.info.role == .user && $0.delivery != .failed }
    guard !localUsers.isEmpty else { return }

    let serverUsers = messages.filter { !isLocalID($0.info.id) && $0.info.role == .user }
    guard !serverUsers.isEmpty else { return }

    var serverTexts: [String: (text: String, filesCount: Int, timeCreated: Int)] = [:]
    for s in serverUsers {
      serverTexts[s.info.id] = (messageText(s), s.parts.filter { $0.type == .file }.count, s.info.timeCreated)
    }

    var removeIDs = Set<String>()
    for local in localUsers {
      let draft = local.draft?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if draft.isEmpty && local.draftAttachments.isEmpty { continue }

      let match = serverUsers.first { candidate in
        guard let cached = serverTexts[candidate.info.id] else { return false }
        return Self.isOptimisticMatch(
          draftText: draft,
          draftAttachmentsCount: local.draftAttachments.count,
          timeCreated: local.info.timeCreated,
          serverText: cached.text,
          serverFilesCount: cached.filesCount,
          serverTimeCreated: cached.timeCreated
        )
      }

      if match != nil {
        removeIDs.insert(local.info.id)
      }
    }

    if !removeIDs.isEmpty {
      messages.removeAll { removeIDs.contains($0.info.id) }
    }
  }

  private func mergeHistory(_ history: [MessageWithParts]) {
    var outOfOrder = false
    var lastTime = -1
    for message in history {
      if message.info.id == activeAssistantID { continue }
      upsertInfo(message.info)
      for part in message.parts {
        upsertPart(part)
      }
      if message.info.timeCreated < lastTime {
        outOfOrder = true
      }
      lastTime = max(lastTime, message.info.timeCreated)
    }
    reconcileOptimistic()
    if outOfOrder {
      messages.sort { $0.info.timeCreated < $1.info.timeCreated }
      rebuildIndexMaps()
    }
    updateTodos()
    updateTotalTokens()
  }

  private func insertMessage(_ message: SessionMessage) {
    let created = message.info.timeCreated
    if let index = messages.firstIndex(where: { $0.info.timeCreated > created }) {
      messages.insert(message, at: index)
      rebuildIndexMaps()
    } else {
      let mIdx = messages.count
      messages.append(message)
      messageIndexMap[message.info.id] = mIdx
      for (pIdx, part) in message.parts.enumerated() {
        partIndexMap[part.id] = (mIdx, pIdx)
        if let callID = part.callID {
          toolCallIndexMap[callID] = (mIdx, pIdx)
        }
      }
    }
  }

  private func upsertInfo(_ info: MessageInfo) {
    if let idx = findMessageIndex(info.id) {
      var existing = messages[idx]
      existing.info = mergeMessageInfo(existing.info, info)
      messages[idx] = existing
      return
    }

    if info.role == .user {
      if let optIdx = messages.firstIndex(where: { isLocalID($0.info.id) && $0.info.role == .user && $0.delivery != .failed }) {
        let oldID = messages[optIdx].info.id
        messageIndexMap.removeValue(forKey: oldID)
        messages[optIdx].info = info
        messages[optIdx].delivery = .sent
        messageIndexMap[info.id] = optIdx
        return
      }
    }

    insertMessage(adopt(MessageWithParts(info: info, parts: [])))
  }

  private func mergeMessageInfo(_ previous: MessageInfo, _ next: MessageInfo) -> MessageInfo {
    var result = previous
    if let kind = next.kind { result.kind = kind }
    if next.timeCompleted != nil { result.timeCompleted = next.timeCompleted }
    if let agent = next.agent { result.agent = agent }
    if let modelID = next.modelID { result.modelID = modelID }
    if let providerID = next.providerID { result.providerID = providerID }
    if let variant = next.variant { result.variant = variant }
    if let tokens = next.tokens { result.tokens = tokens }
    if let cost = next.cost { result.cost = cost }
    if let finish = next.finish { result.finish = finish }
    if let error = next.error { result.error = error }
    return result
  }

  private func upsertPart(_ part: Part) {
    guard let msgIdx = findMessageIndex(part.messageID) else { return }
    var message = messages[msgIdx]

    if !isLocalID(part.id) && message.parts.contains(where: { isLocalID($0.id) }) {
      for p in message.parts where isLocalID(p.id) {
        partIndexMap.removeValue(forKey: p.id)
        if let callID = p.callID {
          toolCallIndexMap.removeValue(forKey: callID)
        }
      }
      message.parts.removeAll { isLocalID($0.id) }
      for (pIdx, p) in message.parts.enumerated() {
        partIndexMap[p.id] = (msgIdx, pIdx)
        if let callID = p.callID {
          toolCallIndexMap[callID] = (msgIdx, pIdx)
        }
      }
    }

    if let partIdx = message.parts.firstIndex(where: { $0.id == part.id }) {
      var existing = message.parts[partIdx]
      existing.text = part.text ?? existing.text
      existing.tool = part.tool ?? existing.tool
      existing.callID = part.callID ?? existing.callID
      if let state = part.state { existing.state = state }
      existing.filename = part.filename ?? existing.filename
      existing.mime = part.mime ?? existing.mime
      existing.url = part.url ?? existing.url
      existing.ordinal = part.ordinal ?? existing.ordinal
      existing.synthetic = part.synthetic ?? existing.synthetic
      message.parts[partIdx] = existing
      if let callID = existing.callID {
        toolCallIndexMap[callID] = (msgIdx, partIdx)
      }
    } else {
      let partIdx = message.parts.count
      message.parts.append(part)
      partIndexMap[part.id] = (msgIdx, partIdx)
      if let callID = part.callID {
        toolCallIndexMap[callID] = (msgIdx, partIdx)
      }
    }

    messages[msgIdx] = message
  }

  @discardableResult
  private func ensureAssistant(_ id: String, patch: PartialMessageInfo? = nil) -> SessionMessage {
    if let idx = findMessageIndex(id) {
      if let patch {
        messages[idx].info = patch.apply(to: messages[idx].info)
      }
      return messages[idx]
    }

    var info = MessageInfo(
      id: id,
      sessionID: sessionID,
      role: .assistant,
      kind: "assistant",
      timeCreated: Int(Date().timeIntervalSince1970 * 1000)
    )
    if let patch {
      info = patch.apply(to: info)
    }

    let message = SessionMessage(info: info, parts: [], delivery: .sent)
    let idx = messages.count
    messages.append(message)
    messageIndexMap[id] = idx
    return message
  }

  private func textPart(messageID: String, ordinal: Int, type: PartType) -> Part? {
    let _ = ensureAssistant(messageID)
    let partID = "\(messageID):\(ordinal)"
    if let (msgIdx, partIdx) = partIndexMap[partID],
       msgIdx < messages.count, partIdx < messages[msgIdx].parts.count,
       messages[msgIdx].parts[partIdx].id == partID {
      return messages[msgIdx].parts[partIdx]
    }

    guard let msgIdx = findMessageIndex(messageID) else { return nil }
    let part = Part(
      id: partID,
      messageID: messageID,
      sessionID: sessionID,
      type: type,
      text: "",
      ordinal: ordinal,
      synthetic: true
    )
    let pIdx = messages[msgIdx].parts.count
    messages[msgIdx].parts.append(part)
    partIndexMap[partID] = (msgIdx, pIdx)
    return part
  }

  private func toolPart(callID: String, messageID: String?, toolName: String?) -> Part? {
    if let (msgIdx, partIdx) = toolCallIndexMap[callID],
       msgIdx < messages.count, partIdx < messages[msgIdx].parts.count,
       messages[msgIdx].parts[partIdx].callID == callID {
      if let toolName, messages[msgIdx].parts[partIdx].tool == nil {
        messages[msgIdx].parts[partIdx].tool = toolName
      }
      return messages[msgIdx].parts[partIdx]
    }

    let resolvedMessageID: String
    if let messageID {
      resolvedMessageID = messageID
    } else {
      if let found = messages.first(where: { $0.parts.contains(where: { $0.type == .tool && $0.callID == callID }) }) {
        resolvedMessageID = found.info.id
      } else {
        return nil
      }
    }

    let _ = ensureAssistant(resolvedMessageID)
    guard let msgIdx = findMessageIndex(resolvedMessageID) else { return nil }

    let partID = "\(resolvedMessageID):tool:\(callID)"
    if let partIdx = messages[msgIdx].parts.firstIndex(where: { $0.id == partID }) {
      if let toolName, messages[msgIdx].parts[partIdx].tool == nil {
        messages[msgIdx].parts[partIdx].tool = toolName
      }
      toolCallIndexMap[callID] = (msgIdx, partIdx)
      partIndexMap[partID] = (msgIdx, partIdx)
      return messages[msgIdx].parts[partIdx]
    }

    let pIdx = messages[msgIdx].parts.count
    let part = Part(
      id: partID,
      messageID: resolvedMessageID,
      sessionID: sessionID,
      type: .tool,
      tool: toolName,
      callID: callID,
      state: .pending,
      ordinal: pIdx
    )
    messages[msgIdx].parts.append(part)
    partIndexMap[partID] = (msgIdx, pIdx)
    toolCallIndexMap[callID] = (msgIdx, pIdx)
    return part
  }

  private func pushNote(kind: String, text: String) -> String {
    let noteID = "\(localPrefix)\(kind):\(localCounter)"
    localCounter += 1
    let msg = adopt(
      MessageWithParts(
        info: MessageInfo(
          id: noteID,
          sessionID: sessionID,
          role: .system,
          kind: kind,
          timeCreated: Int(Date().timeIntervalSince1970 * 1000)
        ),
        parts: [
          Part(id: "\(noteID):text", messageID: noteID, sessionID: sessionID, type: .text, text: text)
        ]
      )
    )
    insertMessage(msg)
    return noteID
  }

  private func updateCompactionNote(text: String, final: Bool) {
    if let id = compactionNoteID, let idx = findMessageIndex(id) {
      if !messages[idx].parts.isEmpty {
        messages[idx].parts[0].text = text
      }
      if final { compactionNoteID = nil }
      return
    }
    let noteID = pushNote(kind: "compaction", text: text)
    compactionNoteID = final ? nil : noteID
  }

  private func failActive(_ message: String) {
    if let activeID = activeAssistantID, let idx = findMessageIndex(activeID) {
      messages[idx].info.error = MessageInfo.Failure(name: "Session error", message: message)
      return
    }
    _ = pushNote(kind: "error", text: message)
  }

  private func settle() {
    busy = false
    statusNote = nil
    activeAssistantID = nil
    if messages.contains(where: { isLocalID($0.info.id) && $0.info.role == .user && $0.delivery == .sent }) {
      sync()
    }
  }

  // MARK: - SSE Event Dispatch

  private func handleEvent(_ event: ServerEvent) {
    if event.type == "stream.reconnected" {
      load()
      return
    }

    guard let eventSessionID = event.sessionID, eventSessionID == sessionID else { return }
    pendingEvents.append(event)
    startTickLoopIfNeeded()
  }

  private func startTickLoopIfNeeded() {
    guard tickTask == nil else { return }
    tickTask = Task { @MainActor [weak self] in
      while let self, !self.pendingEvents.isEmpty {
        try? await Task.sleep(nanoseconds: 16_000_000)
        self.drainPendingEvents()
      }
      self?.tickTask = nil
    }
  }

  public func drainPendingEvents() {
    guard !pendingEvents.isEmpty else { return }
    let events = pendingEvents
    pendingEvents.removeAll()
    for event in events {
      processSingleEvent(event)
    }
    updateTick &+= 1
  }

  private func processSingleEvent(_ event: ServerEvent) {
    let data = event.data

    switch event.type {
    case "session.step.started":
      guard let assistantID = data["assistantMessageID"]?.string else { return }
      let modelData = data["model"] ?? .null
      let patch = PartialMessageInfo(
        agent: data["agent"]?.string,
        modelID: modelData["modelID"].string ?? modelData["id"].string,
        providerID: modelData["providerID"].string,
        variant: modelData["variant"].string
      )
      ensureAssistant(assistantID, patch: patch)
      activeAssistantID = assistantID
      busy = true

    case "session.step.ended":
      guard let assistantID = data["assistantMessageID"]?.string else { return }
      let msg = ensureAssistant(assistantID)
      var info = msg.info
      info.timeCompleted = Int(Date().timeIntervalSince1970 * 1000)
      if let cost = data["cost"]?.double { info.cost = cost }
      if let finish = data["finish"]?.string { info.finish = finish }
      if let tokens = TokenUsage(json: data["tokens"] ?? .null) { info.tokens = tokens }
      if let idx = findMessageIndex(assistantID) { messages[idx].info = info }
      updateTotalTokens()
      if activeAssistantID == assistantID { activeAssistantID = nil }

    case "session.step.failed":
      guard let assistantID = data["assistantMessageID"]?.string else { return }
      let msg = ensureAssistant(assistantID)
      var info = msg.info
      info.timeCompleted = Int(Date().timeIntervalSince1970 * 1000)
      let errObj = data["error"] ?? .null
      info.error = MessageInfo.Failure(
        name: errObj["name"].string ?? "Turn failed",
        message: errObj["message"].string ?? "The model turn failed."
      )
      if let idx = findMessageIndex(assistantID) { messages[idx].info = info }
      if activeAssistantID == assistantID { activeAssistantID = nil }

    case "session.text.started", "session.reasoning.started":
      guard let assistantID = data["assistantMessageID"]?.string,
        let ordinal = data["ordinal"]?.int
      else { return }
      let type: PartType = event.type == "session.text.started" ? .text : .reasoning
      _ = textPart(messageID: assistantID, ordinal: ordinal, type: type)

    case "session.text.delta", "session.reasoning.delta":
      guard let assistantID = data["assistantMessageID"]?.string,
        let ordinal = data["ordinal"]?.int,
        let delta = data["delta"]?.string
      else { return }
      let type: PartType = event.type == "session.text.delta" ? .text : .reasoning
      let partID = "\(assistantID):\(ordinal)"
      let targetIndex: (msgIdx: Int, partIdx: Int)?
      if let loc = partIndexMap[partID] {
        targetIndex = loc
      } else if let part = textPart(messageID: assistantID, ordinal: ordinal, type: type) {
        targetIndex = partIndexMap[part.id]
      } else {
        targetIndex = nil
      }
      if let (msgIdx, partIdx) = targetIndex,
         msgIdx < messages.count, partIdx < messages[msgIdx].parts.count {
        if messages[msgIdx].parts[partIdx].text == nil {
          messages[msgIdx].parts[partIdx].text = delta
        } else {
          messages[msgIdx].parts[partIdx].text?.append(delta)
        }
      }

    case "session.text.ended", "session.reasoning.ended":
      guard let assistantID = data["assistantMessageID"]?.string,
        let ordinal = data["ordinal"]?.int
      else { return }
      let type: PartType = event.type == "session.text.ended" ? .text : .reasoning
      if let part = textPart(messageID: assistantID, ordinal: ordinal, type: type),
        let (msgIdx, partIdx) = partIndexMap[part.id],
        msgIdx < messages.count, partIdx < messages[msgIdx].parts.count
      {
        if let finalText = data["text"]?.string {
          messages[msgIdx].parts[partIdx].text = finalText
        }
        messages[msgIdx].parts[partIdx].synthetic = false
      }

    case "session.tool.input.started":
      guard let callID = data["id"]?.string else { return }
      let assistantID = data["assistantMessageID"]?.string
      let toolName = data["name"]?.string
      if let part = toolPart(callID: callID, messageID: assistantID, toolName: toolName),
        let (msgIdx, partIdx) = partIndexMap[part.id],
        msgIdx < messages.count, partIdx < messages[msgIdx].parts.count
      {
        messages[msgIdx].parts[partIdx].state = .streaming(.init(title: nil, inputText: "", time: nil))
      }

    case "session.tool.input.delta":
      guard let callID = data["id"]?.string, let delta = data["delta"]?.string else { return }
      let assistantID = data["assistantMessageID"]?.string
      if let part = toolPart(callID: callID, messageID: assistantID, toolName: nil),
        let (msgIdx, partIdx) = partIndexMap[part.id],
        msgIdx < messages.count, partIdx < messages[msgIdx].parts.count
      {
        if case .streaming(var s) = messages[msgIdx].parts[partIdx].state {
          if s.inputText == nil {
            s.inputText = delta
          } else {
            s.inputText?.append(delta)
          }
          messages[msgIdx].parts[partIdx].state = .streaming(s)
        } else {
          messages[msgIdx].parts[partIdx].state = .streaming(.init(title: nil, inputText: delta, time: nil))
        }
      }

    case "session.tool.input.ended":
      guard let callID = data["id"]?.string else { return }
      let assistantID = data["assistantMessageID"]?.string
      if let part = toolPart(callID: callID, messageID: assistantID, toolName: nil),
        let (msgIdx, partIdx) = partIndexMap[part.id],
        msgIdx < messages.count, partIdx < messages[msgIdx].parts.count
      {
        let text = data["text"]?.string ?? ""
        messages[msgIdx].parts[partIdx].state = .streaming(.init(title: nil, inputText: text, time: nil))
      }

    case "session.tool.called":
      guard let callID = data["id"]?.string else { return }
      let assistantID = data["assistantMessageID"]?.string
      let toolName = data["name"]?.string
      let inputObj = data["input"]?.object
      if let part = toolPart(callID: callID, messageID: assistantID, toolName: toolName),
        let (msgIdx, partIdx) = partIndexMap[part.id],
        msgIdx < messages.count, partIdx < messages[msgIdx].parts.count
      {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        messages[msgIdx].parts[partIdx].state = .running(
          .init(title: part.state?.title, input: inputObj, time: ToolTime(start: now))
        )
      }

    case "session.tool.progress":
      guard let callID = data["id"]?.string else { return }
      let assistantID = data["assistantMessageID"]?.string
      let metaObj = data["metadata"]?.object
      let titleStr = metaObj?["title"]?.string
      if let part = toolPart(callID: callID, messageID: assistantID, toolName: nil),
        let (msgIdx, partIdx) = partIndexMap[part.id],
        msgIdx < messages.count, partIdx < messages[msgIdx].parts.count
      {
        let currentTitle = titleStr ?? part.state?.title
        let startTime = part.state?.time?.start ?? Int(Date().timeIntervalSince1970 * 1000)
        messages[msgIdx].parts[partIdx].state = .running(
          .init(title: currentTitle, input: part.state?.input, time: ToolTime(start: startTime))
        )
      }

    case "session.tool.success":
      guard let callID = data["id"]?.string else { return }
      let assistantID = data["assistantMessageID"]?.string
      let metaObj = data["metadata"]?.object
      let titleStr = metaObj?["title"]?.string
      let outputStr = toolOutput(data["content"] ?? .null)
      if let part = toolPart(callID: callID, messageID: assistantID, toolName: nil),
        let (msgIdx, partIdx) = partIndexMap[part.id],
        msgIdx < messages.count, partIdx < messages[msgIdx].parts.count
      {
        let currentTitle = titleStr ?? part.state?.title
        let startTime = part.state?.time?.start ?? Int(Date().timeIntervalSince1970 * 1000)
        let now = Int(Date().timeIntervalSince1970 * 1000)
        messages[msgIdx].parts[partIdx].state = .completed(
          .init(
            title: currentTitle,
            input: part.state?.input,
            output: outputStr,
            metadata: metaObj,
            time: ToolTime(start: startTime, end: now)
          )
        )
        if part.tool == "todowrite" { updateTodos() }
      }

    case "session.tool.failed":
      guard let callID = data["id"]?.string else { return }
      let assistantID = data["assistantMessageID"]?.string
      let metaObj = data["metadata"]?.object
      let errObj = data["error"] ?? .null
      let errStr = errObj["message"].string ?? "The tool failed"
      let titleStr = metaObj?["title"]?.string
      if let part = toolPart(callID: callID, messageID: assistantID, toolName: nil),
        let (msgIdx, partIdx) = partIndexMap[part.id],
        msgIdx < messages.count, partIdx < messages[msgIdx].parts.count
      {
        let currentTitle = titleStr ?? part.state?.title
        let startTime = part.state?.time?.start ?? Int(Date().timeIntervalSince1970 * 1000)
        let now = Int(Date().timeIntervalSince1970 * 1000)
        messages[msgIdx].parts[partIdx].state = .error(
          .init(
            error: errStr,
            title: currentTitle,
            input: part.state?.input,
            metadata: metaObj,
            time: ToolTime(start: startTime, end: now)
          )
        )
      }

    case "session.execution.started":
      busy = true
      statusNote = nil
      sync()

    case "session.execution.succeeded", "session.execution.interrupted", "session.idle":
      settle()

    case "session.execution.failed":
      let errObj = data["error"] ?? .null
      let errMessage = errObj["message"].string ?? "The turn failed."
      failActive(errMessage)
      settle()

    case "session.status":
      let statusObj = data["status"] ?? .null
      let typeStr = statusObj["type"].string
      if typeStr == "busy" {
        busy = true
        statusNote = nil
      } else if typeStr == "retry" {
        busy = true
        let attempt = statusObj["attempt"].int
        let msg = statusObj["message"].string ?? "retrying"
        statusNote = attempt != nil ? "\(msg) (attempt \(attempt!))" : msg
      } else if typeStr == "idle" {
        settle()
      }

    case "session.retry.scheduled":
      busy = true
      let attempt = data["attempt"]?.int
      let errObj = data["error"] ?? .null
      let reason = errObj["message"].string ?? "the turn failed"
      statusNote = attempt != nil ? "retrying (attempt \(attempt!)) — \(reason)" : "retrying — \(reason)"

    case "session.renamed":
      title = data["title"]?.string

    case "session.agent.selected":
      agent = data["agent"]?.string

    case "session.model.selected":
      let modelData = data["model"] ?? .null
      if let modelID = modelData["modelID"].string ?? modelData["id"].string,
        let providerID = modelData["providerID"].string
      {
        model = ModelRef(providerID: providerID, modelID: modelID, variant: modelData["variant"].string)
      }

    case "session.compaction.started":
      updateCompactionNote(text: "Compacting the conversation…", final: false)

    case "session.compaction.ended":
      updateCompactionNote(text: "Conversation compacted.", final: true)

    case "session.compaction.failed":
      let errObj = data["error"] ?? .null
      let errStr = errObj["message"].string ?? "unknown error"
      updateCompactionNote(text: "Compaction failed — \(errStr)", final: true)

    case "permission.asked":
      if let request = PermissionRequest(json: .object(data)) {
        if !permissions.contains(where: { $0.id == request.id }) {
          permissions.append(request)
        }
      }

    case "permission.replied":
      if let requestID = data["requestID"]?.string {
        permissions.removeAll { $0.id == requestID }
      }

    case "question.asked":
      if let request = QuestionRequest(json: .object(data)) {
        if !questions.contains(where: { $0.id == request.id }) {
          questions.append(request)
        }
      }

    case "question.replied", "question.rejected":
      if let requestID = data["requestID"]?.string {
        questions.removeAll { $0.id == requestID }
      }

    case "form.created":
      if let formVal = data["form"], let request = toFormRequest(formVal) {
        if !forms.contains(where: { $0.id == request.id }) {
          forms.append(request)
        }
      }

    case "form.replied", "form.cancelled":
      if let formID = data["id"]?.string {
        forms.removeAll { $0.id == formID }
      }

    case "session.inbox.enqueued":
      if let itemObj = data["item"], let item = toInboxItem(itemObj) {
        if !queued.contains(where: { $0.id == item.id }) {
          queued.append(item)
        }
      }

    case "session.inbox.delivered", "session.inbox.cancelled":
      if let inboxID = data["inboxID"]?.string {
        queued.removeAll { $0.id == inboxID }
        if event.type == "session.inbox.delivered" { sync() }
      }

    case "session.inbox.delivery.changed":
      if let inboxID = data["inboxID"]?.string {
        let deliveryStr = data["delivery"]?.string == "steer" ? InboxDelivery.steer : InboxDelivery.queue
        if let idx = queued.firstIndex(where: { $0.id == inboxID }) {
          queued[idx].delivery = deliveryStr
        }
      }

    default:
      break
    }
  }

  // MARK: - Actions

  public func send(text: String, attachments: [PromptAttachment] = []) {
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (!body.isEmpty || !attachments.isEmpty) && !loading && !sending else { return }

    localCounter += 1
    let localID = "\(localPrefix)\(Int(Date().timeIntervalSince1970 * 1000)):\(localCounter)"

    var parts: [Part] = attachments.enumerated().map { idx, att in
      Part(
        id: "\(localID):file:\(idx)",
        messageID: localID,
        sessionID: sessionID,
        type: .file,
        filename: att.filename,
        mime: att.mime,
        url: att.url
      )
    }

    if !body.isEmpty {
      parts.append(
        Part(id: "\(localID):text", messageID: localID, sessionID: sessionID, type: .text, text: body)
      )
    }

    let optimistic = SessionMessage(
      info: MessageInfo(
        id: localID,
        sessionID: sessionID,
        role: .user,
        kind: "user",
        timeCreated: Int(Date().timeIntervalSince1970 * 1000)
      ),
      parts: parts,
      delivery: .sending,
      failure: nil,
      draft: body,
      draftAttachments: attachments
    )

    insertMessage(optimistic)
    deliverPrompt(optimistic)
  }

  private func deliverPrompt(_ message: SessionMessage) {
    guard let idx = findMessageIndex(message.id) else { return }
    messages[idx].delivery = .sending
    messages[idx].failure = nil
    sending = true

    let queueing = busy
    if !queueing { busy = true }

    Task {
      do {
        let client = try connection.requireClient()
        try await client.sendPrompt(
          sessionID,
          text: message.draft ?? "",
          model: model,
          agent: agent,
          attachments: message.draftAttachments,
          delivery: queueing ? deliveryMode : nil
        )

        if let currentIdx = self.findMessageIndex(message.id) {
          self.messages[currentIdx].delivery = .sent
          if queueing {
            self.messages.remove(at: currentIdx)
          }
        }
      } catch {
        if let currentIdx = self.findMessageIndex(message.id) {
          self.messages[currentIdx].delivery = .failed
          self.messages[currentIdx].failure = toUserMessage(error)
        }
        if !queueing { self.busy = false }
      }
      self.sending = false
    }
  }

  public func retry(messageID: String) {
    guard let idx = findMessageIndex(messageID) else { return }
    let msg = messages[idx]
    guard msg.delivery == .failed && !loading && !sending && !busy else { return }
    deliverPrompt(msg)
  }

  public func abort() {
    let currentID = sessionID
    Task {
      if let client = try? connection.requireClient() {
        try? await client.abortSession(currentID)
      }
      self.sending = false
      self.busy = false
      self.statusNote = nil
      self.activeAssistantID = nil
    }
  }

  public func respondPermission(_ requestID: String, reply: PermissionReply) {
    guard permissions.contains(where: { $0.id == requestID }) else { return }
    let currentID = sessionID
    Task {
      do {
        let client = try connection.requireClient()
        try await client.replyPermission(currentID, requestID, reply)
        self.permissions.removeAll { $0.id == requestID }
      } catch {
        // error handling
      }
    }
  }

  public func respondQuestion(_ requestID: String, answers: [[String]]) {
    guard questions.contains(where: { $0.id == requestID }) else { return }
    let currentID = sessionID
    Task {
      do {
        let client = try connection.requireClient()
        try await client.replyQuestion(currentID, requestID, answers: answers)
        self.questions.removeAll { $0.id == requestID }
      } catch {
        // error handling
      }
    }
  }

  public func rejectQuestion(_ requestID: String) {
    guard questions.contains(where: { $0.id == requestID }) else { return }
    let currentID = sessionID
    Task {
      do {
        let client = try connection.requireClient()
        try await client.rejectQuestion(currentID, requestID)
        self.questions.removeAll { $0.id == requestID }
      } catch {
        // error handling
      }
    }
  }

  public func respondForm(_ formID: String, answer: FormAnswer) {
    guard forms.contains(where: { $0.id == formID }) else { return }
    let currentID = sessionID
    Task {
      do {
        let client = try connection.requireClient()
        try await client.replyForm(currentID, formID, answer: answer)
        self.forms.removeAll { $0.id == formID }
      } catch {
        // error handling
      }
    }
  }

  public func cancelForm(_ formID: String) {
    guard forms.contains(where: { $0.id == formID }) else { return }
    let currentID = sessionID
    Task {
      do {
        let client = try connection.requireClient()
        try await client.cancelForm(currentID, formID)
        self.forms.removeAll { $0.id == formID }
      } catch {
        // error handling
      }
    }
  }

  public func runCommand(name: String, args: String = "") {
    guard !loading && !sending else { return }
    let currentID = sessionID
    let queueing = busy
    sending = true
    if !queueing { busy = true }

    Task {
      do {
        let client = try connection.requireClient()
        try await client.runCommand(currentID, command: name, arguments: args, delivery: queueing ? deliveryMode : nil)
      } catch {
        if !queueing { self.busy = false }
        self.error = toUserMessage(error)
      }
      self.sending = false
    }
  }

  public func cancelQueued(_ inboxID: String) {
    let previous = queued
    queued.removeAll { $0.id == inboxID }
    let currentID = sessionID

    Task {
      do {
        let client = try connection.requireClient()
        try await client.cancelInbox(currentID, inboxID)
      } catch {
        self.queued = previous
      }
    }
  }

  public func setQueuedDelivery(_ inboxID: String, delivery: InboxDelivery) {
    if let idx = queued.firstIndex(where: { $0.id == inboxID }) {
      queued[idx].delivery = delivery
    }
    let currentID = sessionID

    Task {
      do {
        let client = try connection.requireClient()
        try await client.setInboxDelivery(currentID, inboxID, delivery)
      } catch {
        // Revert on error
      }
    }
  }

  public func setAgent(_ nextAgent: String) {
    guard agent != nextAgent else { return }
    let previous = agent
    agent = nextAgent
    let currentID = sessionID

    Task {
      do {
        let client = try connection.requireClient()
        try await client.switchAgent(currentID, nextAgent)
      } catch {
        self.agent = previous
      }
    }
  }

  public func setModel(_ nextModel: ModelRef) {
    guard model != nextModel else { return }
    let previous = model
    model = nextModel
    let currentID = sessionID

    Task {
      do {
        let client = try connection.requireClient()
        try await client.switchModel(currentID, nextModel)
      } catch {
        self.model = previous
      }
    }
  }

  // MARK: - MCP

  public func loadMcp() {
    mcpLoading = true
    mcpError = nil
    let dir = directory

    Task {
      do {
        let client = try connection.requireClient()
        let result = try await client.listMcp(dir)
        self.mcpServers = result
      } catch {
        self.mcpError = toUserMessage(error)
      }
      self.mcpLoading = false
    }
  }

  public func toggleMcp(server: McpServer, enabled: Bool) {
    guard !mcpPending.contains(server.name) else { return }
    mcpPending.insert(server.name)
    mcpActionError = nil

    if let idx = mcpServers?.firstIndex(where: { $0.name == server.name }) {
      mcpServers?[idx].status = enabled ? .connected : .disabled
    }
    let dir = directory

    Task {
      do {
        let client = try connection.requireClient()
        try await client.setMcpEnabled(server.name, enabled, directory: dir)
        self.loadMcp()
      } catch {
        self.mcpActionError = "\(server.name): \(toUserMessage(error))"
        if let idx = self.mcpServers?.firstIndex(where: { $0.name == server.name }) {
          self.mcpServers?[idx].status = server.status
        }
      }
      self.mcpPending.remove(server.name)
    }
  }
}

private struct PartialMessageInfo {
  var agent: String?
  var modelID: String?
  var providerID: String?
  var variant: String?

  func apply(to info: MessageInfo) -> MessageInfo {
    var result = info
    if let agent { result.agent = agent }
    if let modelID { result.modelID = modelID }
    if let providerID { result.providerID = providerID }
    if let variant { result.variant = variant }
    return result
  }
}
