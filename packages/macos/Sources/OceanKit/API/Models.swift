import Foundation

/**
 Shapes returned by the opencode v2 server's HTTP API (`/api/…`).

 These are hand-written rather than generated: the wire shapes are wider than
 what the screens need, so the client narrows them here once and every screen
 reads the same normalised types.

 Everything off the wire is read through `JSONValue` rather than synthesised
 `Codable`. The server's JSON is loose — a field can be missing, null, or the
 wrong primitive — and one surprise in one message must not fail a whole list.
 The `Codable` conformances exist for persistence and tests, not for parsing.
 */

// MARK: - Loose JSON

/// A parsed JSON document, in the shape the server actually sends rather than
/// the shape we hoped for. The reading accessors below are the Swift spelling
/// of the Vue client's `record()` / `str()` / `num()` helpers.
public enum JSONValue: Codable, Hashable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised JSON")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  public static func parse(_ data: Data) throws -> JSONValue {
    let raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    return fromAny(raw)
  }

  public static func fromAny(_ object: Any) -> JSONValue {
    if object is NSNull { return .null }
    if let num = object as? NSNumber {
      if CFBooleanGetTypeID() == CFGetTypeID(num) {
        return .bool(num.boolValue)
      }
      return .number(num.doubleValue)
    }
    if let str = object as? String {
      return .string(str)
    }
    if let arr = object as? [Any] {
      return .array(arr.map { fromAny($0) })
    }
    if let dict = object as? [String: Any] {
      var obj: [String: JSONValue] = [:]
      obj.reserveCapacity(dict.count)
      for (k, v) in dict {
        obj[k] = fromAny(v)
      }
      return .object(obj)
    }
    return .null
  }

  public func encoded() throws -> Data {
    try JSONEncoder().encode(self)
  }

  /// Missing keys read as `.null`, so `root["data"]["form"]["sessionID"]` is safe.
  public subscript(key: String) -> JSONValue {
    if case .object(let members) = self { return members[key] ?? .null }
    return .null
  }

  public subscript(index: Int) -> JSONValue {
    if case .array(let items) = self, items.indices.contains(index) { return items[index] }
    return .null
  }

  public var isNull: Bool { self == .null }

  public var object: [String: JSONValue]? {
    if case .object(let members) = self { return members }
    return nil
  }

  public var array: [JSONValue] {
    if case .array(let items) = self { return items }
    return []
  }

  /// Non-empty strings only, matching the Vue client's `str()`.
  public var string: String? {
    if case .string(let value) = self, !value.isEmpty { return value }
    return nil
  }

  /// Finite numbers only — the schema also admits `Infinity`/`NaN`.
  public var double: Double? {
    if case .number(let value) = self, value.isFinite { return value }
    return nil
  }

  public var int: Int? {
    guard let value = double, value >= Double(Int.min), value <= Double(Int.max) else { return nil }
    return Int(value)
  }

  public var bool: Bool? {
    if case .bool(let value) = self { return value }
    return nil
  }

  /// `true` only when the server said so, mirroring `raw.x === true`.
  public var isTrue: Bool { bool == true }

  public var stringArray: [String] { array.compactMap(\.string) }
}

// MARK: - Connection

/**
 Where the server is rooted, what it is running, and whether it is a repository.

 Assembled by the client from `GET /api/health`, `GET /api/location`,
 `GET /api/project` and `GET /api/config` — no single endpoint carries all of it.
 */
public struct AppInfo: Codable, Hashable, Sendable {
  public struct Paths: Codable, Hashable, Sendable {
    /// Repository / worktree root. Absent on non-repo directories.
    public var root: String?
    /// Directory the server was started in.
    public var cwd: String?
    public var config: String?
    public var data: String?
    public var state: String?

    public init(
      root: String? = nil, cwd: String? = nil, config: String? = nil,
      data: String? = nil, state: String? = nil
    ) {
      self.root = root
      self.cwd = cwd
      self.config = config
      self.data = data
      self.state = state
    }
  }

  public var hostname: String?
  /// True when the server's directory is a git worktree (`vcs == "git"`).
  public var git: Bool?
  /// The server user's home directory, for collapsing paths to `~`.
  public var home: String?
  public var path: Paths?
  public var version: String?

  public init(
    hostname: String? = nil, git: Bool? = nil, home: String? = nil,
    path: Paths? = nil, version: String? = nil
  ) {
    self.hostname = hostname
    self.git = git
    self.home = home
    self.path = path
    self.version = version
  }
}

/// `GET /api/health`.
public struct ServerHealth: Codable, Hashable, Sendable {
  public var healthy: Bool
  public var version: String?

  public init(healthy: Bool, version: String? = nil) {
    self.healthy = healthy
    self.version = version
  }

  init(json: JSONValue) {
    healthy = json["healthy"].bool ?? false
    version = json["version"].string
  }
}

/// `GET /api/location` — where the server is rooted right now.
public struct LocationInfo: Codable, Hashable, Sendable {
  public var directory: String?
  public var projectRoot: String?

  public init(directory: String? = nil, projectRoot: String? = nil) {
    self.directory = directory
    self.projectRoot = projectRoot
  }

  init(json: JSONValue) {
    directory = json["directory"].string
    projectRoot = json["project"]["canonical"].string ?? json["project"]["directory"].string
  }
}

/// `GET /api/config` — one of the config sources the server loaded.
public struct ConfigEntry: Codable, Hashable, Sendable {
  public var type: String
  public var path: String?

  public init(type: String, path: String? = nil) {
    self.type = type
    self.path = path
  }

  public init?(json: JSONValue) {
    guard let type = json["type"].string else { return nil }
    self.type = type
    path = json["path"].string
  }
}

/// A saved connection target. Passwords are held only for the active session.
public struct ServerCredentials: Codable, Hashable, Sendable {
  public var url: String
  public var useBasicAuth: Bool
  public var username: String
  public var password: String
  /**
   Keep this server — password included — in the keychain so the app attaches
   again without the form. Opt-in per server, because it outlives the launch.
   */
  public var remember: Bool

  public init(
    url: String, useBasicAuth: Bool = true, username: String = "opencode",
    password: String = "", remember: Bool = false
  ) {
    self.url = url
    self.useBasicAuth = useBasicAuth
    self.username = username
    self.password = password
    self.remember = remember
  }
}

public struct RecentServer: Codable, Hashable, Sendable {
  public var url: String
  public var username: String?
  public var useBasicAuth: Bool
  public var lastConnected: Int
  /// Working directory reported by the server the last time we reached it.
  public var lastDirectory: String?

  public init(
    url: String, username: String? = nil, useBasicAuth: Bool = true,
    lastConnected: Int, lastDirectory: String? = nil
  ) {
    self.url = url
    self.username = username
    self.useBasicAuth = useBasicAuth
    self.lastConnected = lastConnected
    self.lastDirectory = lastDirectory
  }
}

// MARK: - Projects

/// `GET /api/project` — a directory the server knows about.
public struct Project: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  /// Absolute path to the project directory (v2 calls it `canonical`).
  public var worktree: String
  /// `"git"` when the directory is a git repository.
  public var vcs: String?
  public var timeCreated: Int?
  public var timeInitialized: Int?
  /// Extra worktrees / sandboxes v2 associates with the project.
  public var directories: [String]

  public var isGit: Bool { vcs == "git" }

  public init(
    id: String, worktree: String, vcs: String? = nil, timeCreated: Int? = nil,
    timeInitialized: Int? = nil, directories: [String] = []
  ) {
    self.id = id
    self.worktree = worktree
    self.vcs = vcs
    self.timeCreated = timeCreated
    self.timeInitialized = timeInitialized
    self.directories = directories
  }

  public init?(json: JSONValue) {
    guard let id = json["id"].string else { return nil }
    let worktree = json["canonical"].string ?? json["directory"].string ?? ""
    self.id = id
    self.worktree = worktree
    vcs = json["vcs"].string == "git" ? "git" : nil
    timeCreated = json["time"]["created"].int
    timeInitialized = json["time"]["initialized"].int
    let sandboxes = json["sandboxes"].stringArray
    directories = sandboxes.isEmpty ? (worktree.isEmpty ? [] : [worktree]) : sandboxes
  }
}

// MARK: - Sessions

public struct TokenUsage: Codable, Hashable, Sendable {
  public struct Cache: Codable, Hashable, Sendable {
    public var read: Int?
    public var write: Int?

    public init(read: Int? = nil, write: Int? = nil) {
      self.read = read
      self.write = write
    }
  }

  public var input: Int?
  public var output: Int?
  public var reasoning: Int?
  public var cache: Cache?

  public init(input: Int? = nil, output: Int? = nil, reasoning: Int? = nil, cache: Cache? = nil) {
    self.input = input
    self.output = output
    self.reasoning = reasoning
    self.cache = cache
  }

  public init?(json: JSONValue) {
    guard json.object != nil else { return nil }
    input = json["input"].int
    output = json["output"].int
    reasoning = json["reasoning"].int
    let cacheJSON = json["cache"]
    cache = cacheJSON.object == nil
      ? nil : Cache(read: cacheJSON["read"].int, write: cacheJSON["write"].int)
  }
}

/// What a session is running under, mirroring the server's `Model.Ref`.
public struct ModelRef: Codable, Hashable, Sendable {
  public var providerID: String
  public var modelID: String
  public var variant: String?

  public init(providerID: String, modelID: String, variant: String? = nil) {
    self.providerID = providerID
    self.modelID = modelID
    self.variant = variant
  }
}

/// `GET /api/session` — an agent conversation rooted at a directory.
public struct Session: Codable, Hashable, Sendable, Identifiable {
  public struct ModelSelection: Codable, Hashable, Sendable {
    public var id: String?
    public var modelID: String?
    public var providerID: String?
    public var variant: String?

    public init(
      id: String? = nil, modelID: String? = nil, providerID: String? = nil, variant: String? = nil
    ) {
      self.id = id
      self.modelID = modelID
      self.providerID = providerID
      self.variant = variant
    }

    public var ref: ModelRef? {
      guard let providerID, let modelID = modelID ?? id else { return nil }
      return ModelRef(providerID: providerID, modelID: modelID, variant: variant)
    }
  }

  public var id: String
  public var projectID: String?
  public var directory: String?
  public var parentID: String?
  public var title: String?
  public var version: String?
  public var timeCreated: Int
  public var timeUpdated: Int
  /// The agent this session runs under.
  public var agent: String?
  /// The model this session runs under.
  public var model: ModelSelection?
  public var cost: Double?
  public var tokens: TokenUsage?
  /// Present when a revert is staged on the session.
  public var revert: JSONValue?

  public init(
    id: String, projectID: String? = nil, directory: String? = nil, parentID: String? = nil,
    title: String? = nil, version: String? = nil, timeCreated: Int = 0, timeUpdated: Int = 0,
    agent: String? = nil, model: ModelSelection? = nil, cost: Double? = nil,
    tokens: TokenUsage? = nil, revert: JSONValue? = nil
  ) {
    self.id = id
    self.projectID = projectID
    self.directory = directory
    self.parentID = parentID
    self.title = title
    self.version = version
    self.timeCreated = timeCreated
    self.timeUpdated = timeUpdated
    self.agent = agent
    self.model = model
    self.cost = cost
    self.tokens = tokens
    self.revert = revert
  }

  public init?(json: JSONValue) {
    guard let id = json["id"].string else { return nil }
    self.id = id
    projectID = json["projectID"].string
    directory = json["location"]["directory"].string
    parentID = json["parentID"].string
    title = json["title"].string
    version = json["version"].string
    timeCreated = json["time"]["created"].int ?? 0
    timeUpdated = json["time"]["updated"].int ?? timeCreated
    agent = json["agent"].string
    let modelJSON = json["model"]
    model = modelJSON.object == nil
      ? nil
      : ModelSelection(
        id: modelJSON["id"].string,
        modelID: modelJSON["modelID"].string ?? modelJSON["id"].string,
        providerID: modelJSON["providerID"].string,
        variant: modelJSON["variant"].string
      )
    cost = json["cost"].double
    tokens = TokenUsage(json: json["tokens"])
    let revertJSON = json["revert"]
    revert = revertJSON.isNull ? nil : revertJSON
  }
}

/**
 True for anything the session list has no business showing: the children a
 `task` tool spawns for a subagent belong to their parent's transcript, not
 beside it.
 */
public func isHiddenSession(_ session: Session) -> Bool {
  session.parentID != nil
}

// MARK: - Messages

/**
 `system` covers every v2 message type that is neither a user prompt nor an
 assistant turn — synthetic notes, skill activations, compactions and the
 agent / model / location switches the server records inline.
 */
public enum MessageRole: String, Codable, Hashable, Sendable {
  case user
  case assistant
  case system
}

public struct MessageInfo: Codable, Hashable, Sendable, Identifiable {
  public struct Failure: Codable, Hashable, Sendable {
    public var name: String?
    public var message: String?

    public init(name: String? = nil, message: String? = nil) {
      self.name = name
      self.message = message
    }
  }

  public var id: String
  public var sessionID: String
  public var role: MessageRole
  /// The raw v2 message type, for screens that label system notes.
  public var kind: String?
  public var timeCreated: Int
  public var timeCompleted: Int?
  /// Assistant turns carry the agent, model and token accounting.
  public var agent: String?
  public var modelID: String?
  public var providerID: String?
  public var variant: String?
  public var tokens: TokenUsage?
  public var cost: Double?
  public var finish: String?
  public var error: Failure?

  public init(
    id: String, sessionID: String, role: MessageRole, kind: String? = nil,
    timeCreated: Int = 0, timeCompleted: Int? = nil, agent: String? = nil,
    modelID: String? = nil, providerID: String? = nil, variant: String? = nil,
    tokens: TokenUsage? = nil, cost: Double? = nil, finish: String? = nil,
    error: Failure? = nil
  ) {
    self.id = id
    self.sessionID = sessionID
    self.role = role
    self.kind = kind
    self.timeCreated = timeCreated
    self.timeCompleted = timeCompleted
    self.agent = agent
    self.modelID = modelID
    self.providerID = providerID
    self.variant = variant
    self.tokens = tokens
    self.cost = cost
    self.finish = finish
    self.error = error
  }
}

public enum PartType: String, Codable, Hashable, Sendable {
  case text
  case reasoning
  case tool
  case file
}

public enum ToolStatus: String, Codable, Hashable, Sendable {
  case pending
  case streaming
  case running
  case completed
  case error
}

public struct ToolTime: Codable, Hashable, Sendable {
  public var start: Int
  public var end: Int?

  public init(start: Int, end: Int? = nil) {
    self.start = start
    self.end = end
  }
}

public enum ToolState: Codable, Hashable, Sendable {
  public struct Streaming: Codable, Hashable, Sendable {
    public var title: String?
    /// Partial JSON the model is still emitting.
    public var inputText: String?
    public var time: ToolTime?

    public init(title: String? = nil, inputText: String? = nil, time: ToolTime? = nil) {
      self.title = title
      self.inputText = inputText
      self.time = time
    }
  }

  public struct Running: Codable, Hashable, Sendable {
    public var title: String?
    public var input: [String: JSONValue]?
    public var time: ToolTime?

    public init(title: String? = nil, input: [String: JSONValue]? = nil, time: ToolTime? = nil) {
      self.title = title
      self.input = input
      self.time = time
    }
  }

  public struct Completed: Codable, Hashable, Sendable {
    public var title: String?
    public var input: [String: JSONValue]?
    public var output: String?
    public var metadata: [String: JSONValue]?
    public var time: ToolTime?

    public init(
      title: String? = nil, input: [String: JSONValue]? = nil, output: String? = nil,
      metadata: [String: JSONValue]? = nil, time: ToolTime? = nil
    ) {
      self.title = title
      self.input = input
      self.output = output
      self.metadata = metadata
      self.time = time
    }
  }

  public struct Failed: Codable, Hashable, Sendable {
    public var error: String
    public var title: String?
    public var input: [String: JSONValue]?
    public var metadata: [String: JSONValue]?
    public var time: ToolTime?

    public init(
      error: String, title: String? = nil, input: [String: JSONValue]? = nil,
      metadata: [String: JSONValue]? = nil, time: ToolTime? = nil
    ) {
      self.error = error
      self.title = title
      self.input = input
      self.metadata = metadata
      self.time = time
    }
  }

  case pending
  case streaming(Streaming)
  case running(Running)
  case completed(Completed)
  case error(Failed)

  public var status: ToolStatus {
    switch self {
    case .pending: return .pending
    case .streaming: return .streaming
    case .running: return .running
    case .completed: return .completed
    case .error: return .error
    }
  }

  public var title: String? {
    switch self {
    case .pending: return nil
    case .streaming(let state): return state.title
    case .running(let state): return state.title
    case .completed(let state): return state.title
    case .error(let state): return state.title
    }
  }

  public var input: [String: JSONValue]? {
    switch self {
    case .pending, .streaming: return nil
    case .running(let state): return state.input
    case .completed(let state): return state.input
    case .error(let state): return state.input
    }
  }

  public var time: ToolTime? {
    switch self {
    case .pending: return nil
    case .streaming(let state): return state.time
    case .running(let state): return state.time
    case .completed(let state): return state.time
    case .error(let state): return state.time
    }
  }

  private enum CodingKeys: String, CodingKey { case status }

  public init(from decoder: Decoder) throws {
    let tag = try decoder.container(keyedBy: CodingKeys.self)
    switch try tag.decode(ToolStatus.self, forKey: .status) {
    case .pending: self = .pending
    case .streaming: self = .streaming(try Streaming(from: decoder))
    case .running: self = .running(try Running(from: decoder))
    case .completed: self = .completed(try Completed(from: decoder))
    case .error: self = .error(try Failed(from: decoder))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var tag = encoder.container(keyedBy: CodingKeys.self)
    try tag.encode(status, forKey: .status)
    switch self {
    case .pending: break
    case .streaming(let state): try state.encode(to: encoder)
    case .running(let state): try state.encode(to: encoder)
    case .completed(let state): try state.encode(to: encoder)
    case .error(let state): try state.encode(to: encoder)
    }
  }
}

public struct Part: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var messageID: String
  public var sessionID: String
  public var type: PartType
  /// `text` and `reasoning` parts.
  public var text: String?
  /// `tool` parts.
  public var tool: String?
  public var callID: String?
  public var state: ToolState?
  /// `file` parts.
  public var filename: String?
  public var mime: String?
  public var url: String?
  /// Position of the part inside its message, which is how v2 keys deltas.
  public var ordinal: Int?
  /// Set on parts the server is still streaming.
  public var synthetic: Bool?

  public init(
    id: String, messageID: String, sessionID: String, type: PartType, text: String? = nil,
    tool: String? = nil, callID: String? = nil, state: ToolState? = nil,
    filename: String? = nil, mime: String? = nil, url: String? = nil,
    ordinal: Int? = nil, synthetic: Bool? = nil
  ) {
    self.id = id
    self.messageID = messageID
    self.sessionID = sessionID
    self.type = type
    self.text = text
    self.tool = tool
    self.callID = callID
    self.state = state
    self.filename = filename
    self.mime = mime
    self.url = url
    self.ordinal = ordinal
    self.synthetic = synthetic
  }
}

/// A message and its parts, which is how every screen wants to consume it.
public struct MessageWithParts: Codable, Hashable, Sendable, Identifiable {
  public var info: MessageInfo
  public var parts: [Part]

  public var id: String { info.id }

  public init(info: MessageInfo, parts: [Part]) {
    self.info = info
    self.parts = parts
  }
}

/**
 An image the user attached to a prompt, held as a `data:` URL.

 The server takes the bytes inline on the prompt body rather than through a
 separate upload, so there is nothing to clean up if the send fails.
 */
public struct PromptAttachment: Codable, Hashable, Sendable, Identifiable {
  /// Client-side only, for keying the thumbnail list and removal.
  public var id: String
  public var mime: String
  public var filename: String
  public var url: String

  public init(id: String = UUID().uuidString, mime: String, filename: String, url: String) {
    self.id = id
    self.mime = mime
    self.filename = filename
    self.url = url
  }
}

/// v2 message types that are neither a prompt nor a turn, rendered as notes.
private let systemMessageTypes: Set<String> = [
  "synthetic", "system", "skill", "shell", "compaction",
  "agent-switched", "model-switched", "location-switched",
]

/**
 A v2 message and its `content` array, flattened into the `{info, parts}` shape
 every screen reads. Parts have no ids of their own, so they are keyed by their
 position in the message — which is also how the event stream addresses them
 (`ordinal` for text and reasoning, the call id for tools).
 */
public func toMessage(_ json: JSONValue, sessionID: String) -> MessageWithParts? {
  guard let id = json["id"].string else { return nil }
  let kind = json["type"].string ?? "system"
  let role: MessageRole =
    kind == "user" ? .user : kind == "assistant" ? .assistant : .system

  let errorJSON = json["error"]
  let info = MessageInfo(
    id: id,
    sessionID: sessionID,
    role: role,
    kind: kind,
    timeCreated: json["time"]["created"].int ?? 0,
    timeCompleted: json["time"]["completed"].int,
    agent: json["agent"].string,
    modelID: json["model"]["id"].string,
    providerID: json["model"]["providerID"].string,
    variant: json["model"]["variant"].string,
    tokens: TokenUsage(json: json["tokens"]),
    cost: json["cost"].double,
    finish: json["finish"].string,
    error: errorJSON.object == nil
      ? nil
      : MessageInfo.Failure(name: errorJSON["type"].string, message: errorJSON["message"].string)
  )

  var parts: [Part] = []
  for (index, item) in json["content"].array.enumerated() {
    let type = item["type"].string
    if type == "text" || type == "reasoning" {
      parts.append(
        Part(
          id: "\(id):\(index)",
          messageID: id,
          sessionID: sessionID,
          type: type == "text" ? .text : .reasoning,
          text: item["text"].string ?? "",
          ordinal: index
        ))
      continue
    }
    if type == "tool" {
      let callID = item["id"].string
      parts.append(
        Part(
          id: "\(id):tool:\(callID ?? String(index))",
          messageID: id,
          sessionID: sessionID,
          type: .tool,
          tool: item["name"].string,
          callID: callID,
          state: toToolState(item),
          ordinal: index
        ))
    }
  }

  // The prompt itself, plus anything the user attached to it.
  if kind == "user" {
    for (index, file) in json["files"].array.enumerated() {
      parts.append(
        Part(
          id: "\(id):file:\(index)",
          messageID: id,
          sessionID: sessionID,
          type: .file,
          filename: file["name"].string,
          mime: file["mime"].string,
          url: fileURL(file)
        ))
    }
  }
  if let plain = json["text"].string ?? json["summary"].string ?? json["description"].string {
    parts.append(
      Part(id: "\(id):text", messageID: id, sessionID: sessionID, type: .text, text: plain))
  }

  return MessageWithParts(info: info, parts: parts)
}

private func fileURL(_ file: JSONValue) -> String? {
  if file["source"]["type"].string == "uri", let uri = file["source"]["uri"].string { return uri }
  if let data = file["data"].string {
    return "data:\(file["mime"].string ?? "application/octet-stream");base64,\(data)"
  }
  return nil
}

public func toToolState(_ item: JSONValue) -> ToolState {
  let state = item["state"]
  guard let status = state["status"].string else { return .pending }
  let start = item["time"]["ran"].int ?? item["time"]["created"].int ?? 0
  let end = item["time"]["completed"].int ?? 0
  let time: ToolTime? = start > 0 ? ToolTime(start: start, end: end) : nil
  let metadata = state["metadata"].object
  let title = metadata?["title"]?.string

  switch status {
  case "streaming":
    return .streaming(
      .init(title: title, inputText: state["input"].string, time: time.map { ToolTime(start: $0.start) }))
  case "running":
    return .running(
      .init(title: title, input: state["input"].object, time: time.map { ToolTime(start: $0.start) }))
  case "completed":
    return .completed(
      .init(
        title: title,
        input: state["input"].object,
        output: toolOutput(state["content"]),
        metadata: metadata,
        time: time
      ))
  case "error":
    return .error(
      .init(
        error: state["error"]["message"].string ?? "The tool failed",
        title: title,
        input: state["input"].object,
        metadata: metadata,
        time: time
      ))
  default:
    return .pending
  }
}

/// Tool output is a list of content blocks in v2; screens want one string.
public func toolOutput(_ content: JSONValue) -> String {
  content.array
    .map { block -> String in
      switch block["type"].string {
      case "text": return block["text"].string ?? ""
      case "file": return block["name"].string ?? block["uri"].string ?? ""
      default: return ""
      }
    }
    .filter { !$0.isEmpty }
    .joined(separator: "\n")
}

// MARK: - Files

/**
 What `GET /api/vcs/status` can say about a file. There is no untracked marker:
 a file git has never seen is reported as `added`, same as a staged new file,
 and no endpoint distinguishes the index from the worktree.
 */
public enum FileChangeStatus: String, Codable, Hashable, Sendable {
  case added
  case modified
  case deleted
}

/// One entry of a directory listing, with an absolute `path`.
public struct FileNode: Codable, Hashable, Sendable, Identifiable {
  public enum Kind: String, Codable, Hashable, Sendable {
    case file
    case directory
  }

  public var name: String
  public var path: String
  public var type: Kind
  /// Git working-tree state, when the server reports it.
  public var status: FileChangeStatus?
  public var size: Int?

  public var id: String { path }

  public init(
    name: String, path: String, type: Kind, status: FileChangeStatus? = nil, size: Int? = nil
  ) {
    self.name = name
    self.path = path
    self.type = type
    self.status = status
    self.size = size
  }
}

/// `GET /api/fs/read/*` — the body of one file.
public struct FileContent: Codable, Hashable, Sendable {
  public var content: String

  public init(content: String) {
    self.content = content
  }
}

/// The working tree, as `GET /api/vcs/status` sees it. Paths are repo-relative.
public struct FileStatus: Codable, Hashable, Sendable, Identifiable {
  public var path: String
  public var status: FileChangeStatus
  public var added: Int?
  public var removed: Int?

  public var id: String { path }

  public init(path: String, status: FileChangeStatus, added: Int? = nil, removed: Int? = nil) {
    self.path = path
    self.status = status
    self.added = added
    self.removed = removed
  }
}

// MARK: - Git

public struct GitCommit: Codable, Hashable, Sendable, Identifiable {
  public var hash: String
  public var shortHash: String
  public var subject: String
  public var author: String
  public var date: Int
  public var refs: [String]

  public var id: String { hash }

  public init(
    hash: String, shortHash: String, subject: String, author: String, date: Int, refs: [String]
  ) {
    self.hash = hash
    self.shortHash = shortHash
    self.subject = subject
    self.author = author
    self.date = date
    self.refs = refs
  }
}

/// One file touched by a commit, as `git show --name-status --numstat` reports it.
public struct GitCommitFile: Codable, Hashable, Sendable, Identifiable {
  public var path: String
  public var status: FileChangeStatus
  public var added: Int
  public var removed: Int

  public var id: String { path }

  public init(path: String, status: FileChangeStatus, added: Int, removed: Int) {
    self.path = path
    self.status = status
    self.added = added
    self.removed = removed
  }
}

public struct GitCommitDetail: Codable, Hashable, Sendable, Identifiable {
  public var commit: GitCommit
  public var files: [GitCommitFile]

  public var id: String { commit.hash }

  public init(commit: GitCommit, files: [GitCommitFile]) {
    self.commit = commit
    self.files = files
  }
}

/// One `@@` block of a unified diff.
public struct DiffHunk: Codable, Hashable, Sendable {
  public var header: String
  public var lines: [DiffLine]

  public init(header: String, lines: [DiffLine]) {
    self.header = header
    self.lines = lines
  }
}

public struct DiffLine: Codable, Hashable, Sendable {
  public enum Kind: String, Codable, Hashable, Sendable {
    case context
    case add
    case del
  }

  public var kind: Kind
  public var text: String
  public var oldNumber: Int?
  public var newNumber: Int?

  public init(kind: Kind, text: String, oldNumber: Int? = nil, newNumber: Int? = nil) {
    self.kind = kind
    self.text = text
    self.oldNumber = oldNumber
    self.newNumber = newNumber
  }
}

public struct FileDiff: Codable, Hashable, Sendable, Identifiable {
  public var path: String
  public var hunks: [DiffHunk]
  public var added: Int
  public var removed: Int

  public var id: String { path }

  public init(path: String, hunks: [DiffHunk], added: Int, removed: Int) {
    self.path = path
    self.hunks = hunks
    self.added = added
    self.removed = removed
  }
}

// MARK: - VCS

/**
 `GET /api/vcs` gives the branch; ahead/behind come from `git rev-list` through
 the shell endpoint, since v2 has no upstream-tracking route.
 */
public struct VcsInfo: Codable, Hashable, Sendable {
  public var branch: String?
  public var defaultBranch: String?
  public var ahead: Int
  public var behind: Int

  public init(branch: String? = nil, defaultBranch: String? = nil, ahead: Int = 0, behind: Int = 0) {
    self.branch = branch
    self.defaultBranch = defaultBranch
    self.ahead = ahead
    self.behind = behind
  }
}

/// `GET /api/vcs/status` — one changed file, as the VCS service reports it.
public struct VcsFileStatus: Codable, Hashable, Sendable, Identifiable {
  public var file: String
  public var additions: Int
  public var deletions: Int
  public var status: FileChangeStatus

  public var id: String { file }

  public init(file: String, additions: Int, deletions: Int, status: FileChangeStatus) {
    self.file = file
    self.additions = additions
    self.deletions = deletions
    self.status = status
  }

  public init?(json: JSONValue) {
    guard let file = json["file"].string else { return nil }
    self.file = file
    additions = json["additions"].int ?? 0
    deletions = json["deletions"].int ?? 0
    status = FileChangeStatus(rawValue: json["status"].string ?? "") ?? .modified
  }
}

/// `GET /api/vcs/diff` — one changed file and its unified-diff patch.
public struct VcsDiffFile: Codable, Hashable, Sendable, Identifiable {
  public var file: String
  public var patch: String
  public var additions: Int
  public var deletions: Int
  public var status: FileChangeStatus

  public var id: String { file }

  public init(
    file: String, patch: String, additions: Int, deletions: Int, status: FileChangeStatus
  ) {
    self.file = file
    self.patch = patch
    self.additions = additions
    self.deletions = deletions
    self.status = status
  }

  public init?(json: JSONValue) {
    guard let file = json["file"].string else { return nil }
    self.file = file
    patch = json["patch"].string ?? ""
    additions = json["additions"].int ?? 0
    deletions = json["deletions"].int ?? 0
    status = FileChangeStatus(rawValue: json["status"].string ?? "") ?? .modified
  }
}

/// What the working tree is diffed against.
public enum VcsDiffMode: String, Codable, Hashable, Sendable {
  case working
  case branch
}

/// The result of `git commit`, run through `POST /api/shell`.
public struct VcsCommitResult: Codable, Hashable, Sendable {
  public var committed: Bool
  public var hash: String?
  public var message: String?

  public init(committed: Bool, hash: String? = nil, message: String? = nil) {
    self.committed = committed
    self.hash = hash
    self.message = message
  }
}

/// The result of `git push`, run through `POST /api/shell`.
public struct VcsPushResult: Codable, Hashable, Sendable {
  public var pushed: Bool
  public var message: String?

  public init(pushed: Bool, message: String? = nil) {
    self.pushed = pushed
    self.message = message
  }
}

// MARK: - Shell

public enum ShellStatus: String, Codable, Hashable, Sendable {
  case running
  case exited
  case timeout
  case killed
}

/// `POST /api/shell` — one command the server ran on our behalf.
public struct ShellResult: Codable, Hashable, Sendable {
  public var output: String
  public var exit: Int?
  public var status: ShellStatus

  public init(output: String, exit: Int? = nil, status: ShellStatus) {
    self.output = output
    self.exit = exit
    self.status = status
  }
}

/// `GET /api/shell/{id}` — where a started command has got to.
public struct ShellCommand: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var status: ShellStatus
  public var exit: Int?

  public init(id: String, status: ShellStatus, exit: Int? = nil) {
    self.id = id
    self.status = status
    self.exit = exit
  }
}

/// `GET /api/shell/{id}/output` — one page of the captured combined output.
public struct ShellChunk: Codable, Hashable, Sendable {
  public var output: String
  /// Absolute byte offset to resume from on the next read.
  public var cursor: Int
  /// Bytes were dropped before this page because the capture wrapped.
  public var truncated: Bool

  public init(output: String, cursor: Int, truncated: Bool) {
    self.output = output
    self.cursor = cursor
    self.truncated = truncated
  }
}

// MARK: - Events

/// `GET /api/event` — one frame of the server's SSE stream.
public struct ServerEvent: Codable, Hashable, Sendable {
  public var type: String
  public var id: String?
  /// From the event's `location`, so screens can ignore other directories.
  public var directory: String?
  public var sessionID: String?
  public var data: [String: JSONValue]

  public init(
    type: String, id: String? = nil, directory: String? = nil, sessionID: String? = nil,
    data: [String: JSONValue] = [:]
  ) {
    self.type = type
    self.id = id
    self.directory = directory
    self.sessionID = sessionID
    self.data = data
  }

  /// Missing keys read as `.null`, the same as `JSONValue`.
  public subscript(key: String) -> JSONValue { data[key] ?? .null }
}

/**
 The v2 frame is `{id, type, data, location}`. Sessions are identified inside
 `data`, and the directory comes from the event's own location — the stream is
 global, so that is the only way to tell whose event this is.
 */
public func normaliseServerEvent(_ json: JSONValue) -> ServerEvent? {
  guard json.object != nil, let type = json["type"].string else { return nil }
  let data = json["data"]
  return ServerEvent(
    type: type,
    id: json["id"].string,
    directory: json["location"]["directory"].string,
    // `form.created` is the one event that carries the session inside its
    // payload object rather than beside it; without this it looks sessionless
    // and every screen drops it.
    sessionID: data["sessionID"].string ?? data["form"]["sessionID"].string,
    data: data.object ?? [:]
  )
}

// MARK: - Commands

/// `GET /api/command` — a saved prompt template the session can run.
public struct CommandInfo: Codable, Hashable, Sendable, Identifiable {
  public var name: String
  public var description: String?
  /// The prompt it expands to; `$ARGUMENTS` is where the rest of the line goes.
  public var template: String
  public var agent: String?
  public var subtask: Bool?

  public var id: String { name }

  public init(
    name: String, description: String? = nil, template: String = "", agent: String? = nil,
    subtask: Bool? = nil
  ) {
    self.name = name
    self.description = description
    self.template = template
    self.agent = agent
    self.subtask = subtask
  }

  public init?(json: JSONValue) {
    guard let name = json["name"].string else { return nil }
    self.name = name
    description = json["description"].string
    template = json["template"].string ?? ""
    agent = json["agent"].string
    subtask = json["subtask"].bool
  }
}

// MARK: - Inbox

/// `queue` runs after the current turn; `steer` cuts into it.
public enum InboxDelivery: String, Codable, Hashable, Sendable {
  case steer
  case queue
}

/// `GET /api/session/{id}/inbox` — a prompt admitted but not yet delivered.
public struct InboxItem: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var sessionID: String
  public var timeCreated: Int
  public var type: String
  public var text: String
  public var delivery: InboxDelivery
  public var attachments: Int

  public init(
    id: String, sessionID: String, timeCreated: Int, type: String, text: String,
    delivery: InboxDelivery, attachments: Int
  ) {
    self.id = id
    self.sessionID = sessionID
    self.timeCreated = timeCreated
    self.type = type
    self.text = text
    self.delivery = delivery
    self.attachments = attachments
  }
}

public func toInboxItem(_ json: JSONValue) -> InboxItem? {
  guard let id = json["id"].string else { return nil }
  return InboxItem(
    id: id,
    sessionID: json["sessionID"].string ?? "",
    timeCreated: json["timeCreated"].int ?? Int(Date().timeIntervalSince1970 * 1000),
    type: json["type"].string ?? "user",
    text: json["payload"]["text"].string ?? "",
    delivery: json["delivery"].string == "steer" ? .steer : .queue,
    attachments: json["payload"]["files"].array.count
  )
}

// MARK: - Permissions

/**
 `permission.asked` / `GET /api/session/{id}/permission` — the agent is blocked
 until this is answered.
 */
public struct PermissionRequest: Codable, Hashable, Sendable, Identifiable {
  public struct Source: Codable, Hashable, Sendable {
    public var type: String
    public var messageID: String
    public var id: String

    public init(type: String, messageID: String, id: String) {
      self.type = type
      self.messageID = messageID
      self.id = id
    }
  }

  public var id: String
  public var sessionID: String
  /// What it wants to do: `edit`, `bash`, `webfetch`, `external_directory`…
  public var action: String
  /// What it wants to do it to — a path, a command, a URL.
  public var resources: [String]
  /// The patterns an `always` answer would save.
  public var save: [String]?
  public var metadata: [String: JSONValue]?
  /// The tool call that raised it, for pointing at the right turn.
  public var source: Source?

  public init(
    id: String, sessionID: String, action: String, resources: [String] = [],
    save: [String]? = nil, metadata: [String: JSONValue]? = nil, source: Source? = nil
  ) {
    self.id = id
    self.sessionID = sessionID
    self.action = action
    self.resources = resources
    self.save = save
    self.metadata = metadata
    self.source = source
  }

  public init?(json: JSONValue) {
    guard let id = json["id"].string else { return nil }
    self.id = id
    sessionID = json["sessionID"].string ?? ""
    action = json["action"].string ?? ""
    resources = json["resources"].stringArray
    let saved = json["save"].stringArray
    save = saved.isEmpty ? nil : saved
    metadata = json["metadata"].object
    let sourceJSON = json["source"]
    source = sourceJSON.object.flatMap { _ -> Source? in
      guard let sourceID = sourceJSON["id"].string else { return nil }
      return Source(
        type: sourceJSON["type"].string ?? "tool",
        messageID: sourceJSON["messageID"].string ?? "",
        id: sourceID
      )
    }
  }
}

public enum PermissionReply: String, Codable, Hashable, Sendable {
  case once
  case always
  case reject
}

// MARK: - Questions

public struct QuestionOption: Codable, Hashable, Sendable {
  public var label: String
  public var description: String?

  public init(label: String, description: String? = nil) {
    self.label = label
    self.description = description
  }
}

public struct QuestionInfo: Codable, Hashable, Sendable {
  public var question: String
  public var header: String?
  public var options: [QuestionOption]
  public var multiple: Bool
  public var custom: Bool

  public init(
    question: String, header: String? = nil, options: [QuestionOption] = [],
    multiple: Bool = false, custom: Bool = false
  ) {
    self.question = question
    self.header = header
    self.options = options
    self.multiple = multiple
    self.custom = custom
  }
}

public struct QuestionRequest: Codable, Hashable, Sendable, Identifiable {
  public struct ToolRef: Codable, Hashable, Sendable {
    public var messageID: String
    public var callID: String

    public init(messageID: String, callID: String) {
      self.messageID = messageID
      self.callID = callID
    }
  }

  public var id: String
  public var sessionID: String
  public var questions: [QuestionInfo]
  public var tool: ToolRef?

  public init(
    id: String, sessionID: String, questions: [QuestionInfo] = [], tool: ToolRef? = nil
  ) {
    self.id = id
    self.sessionID = sessionID
    self.questions = questions
    self.tool = tool
  }

  public init?(json: JSONValue) {
    guard let id = json["id"].string else { return nil }
    self.id = id
    sessionID = json["sessionID"].string ?? ""
    questions = json["questions"].array.compactMap { entry in
      guard let question = entry["question"].string else { return nil }
      return QuestionInfo(
        question: question,
        header: entry["header"].string,
        options: entry["options"].array.compactMap { option in
          guard let label = option["label"].string else { return nil }
          return QuestionOption(label: label, description: option["description"].string)
        },
        multiple: entry["multiple"].isTrue,
        custom: entry["custom"].isTrue
      )
    }
    let toolJSON = json["tool"]
    tool = toolJSON["callID"].string.map {
      ToolRef(messageID: toolJSON["messageID"].string ?? "", callID: $0)
    }
  }
}

// MARK: - Forms

/// One answered field. Numbers go out as numbers — the server rejects `"2"`.
public enum FormValue: Codable, Hashable, Sendable {
  case string(String)
  case number(Double)
  case boolean(Bool)
  case list([String])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Bool.self) {
      self = .boolean(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else {
      self = .list(try container.decode([String].self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .boolean(let value): try container.encode(value)
    case .list(let value): try container.encode(value)
    }
  }

  init?(scalar json: JSONValue) {
    switch json {
    case .string(let value): self = .string(value)
    case .number(let value) where value.isFinite: self = .number(value)
    case .bool(let value): self = .boolean(value)
    default: return nil
    }
  }

  var jsonValue: JSONValue {
    switch self {
    case .string(let value): return .string(value)
    case .number(let value): return .number(value)
    case .boolean(let value): return .bool(value)
    case .list(let value): return .array(value.map { .string($0) })
    }
  }
}

/// The whole reply, keyed by field. Only *active* fields may appear.
public typealias FormAnswer = [String: FormValue]

public struct FormOption: Codable, Hashable, Sendable, Identifiable {
  public var value: String
  public var label: String
  public var description: String?

  public var id: String { value }

  public init(value: String, label: String, description: String? = nil) {
    self.value = value
    self.label = label
    self.description = description
  }
}

/**
 A field is only asked when every one of its conditions holds against the
 answers so far. Sending a field whose conditions fail is a 400, so this decides
 what is rendered *and* what is submitted.
 */
public struct FormCondition: Codable, Hashable, Sendable {
  public enum Op: String, Codable, Hashable, Sendable {
    case eq
    case neq
  }

  public var key: String
  public var op: Op
  public var value: FormValue

  public init(key: String, op: Op, value: FormValue) {
    self.key = key
    self.op = op
    self.value = value
  }

  /// Whether the field this guards should be asked, given the answers so far.
  public func holds(in answers: FormAnswer) -> Bool {
    let matches = answers[key] == value
    return op == .eq ? matches : !matches
  }
}

public struct FormFieldBase: Codable, Hashable, Sendable {
  public var key: String
  public var title: String?
  public var description: String?
  public var required: Bool
  public var when: [FormCondition]?

  public init(
    key: String, title: String? = nil, description: String? = nil, required: Bool = false,
    when: [FormCondition]? = nil
  ) {
    self.key = key
    self.title = title
    self.description = description
    self.required = required
    self.when = when
  }
}

public enum FormField: Codable, Hashable, Sendable, Identifiable {
  /// Free text, or a single-choice list when `options` is present.
  public struct StringField: Codable, Hashable, Sendable {
    public enum Format: String, Codable, Hashable, Sendable {
      case email
      case uri
      case date
      case dateTime = "date-time"
    }

    public var base: FormFieldBase
    public var format: Format?
    public var minLength: Int?
    public var maxLength: Int?
    public var pattern: String?
    public var placeholder: String?
    public var `default`: String?
    public var options: [FormOption]?
    /// With `options`, also accept a value the user types.
    public var custom: Bool

    public init(
      base: FormFieldBase, format: Format? = nil, minLength: Int? = nil, maxLength: Int? = nil,
      pattern: String? = nil, placeholder: String? = nil, default: String? = nil,
      options: [FormOption]? = nil, custom: Bool = false
    ) {
      self.base = base
      self.format = format
      self.minLength = minLength
      self.maxLength = maxLength
      self.pattern = pattern
      self.placeholder = placeholder
      self.default = `default`
      self.options = options
      self.custom = custom
    }
  }

  public struct NumberField: Codable, Hashable, Sendable {
    public var base: FormFieldBase
    /// `true` when the server asked for an integer rather than any number.
    public var integer: Bool
    public var minimum: Double?
    public var maximum: Double?
    public var `default`: Double?

    public init(
      base: FormFieldBase, integer: Bool = false, minimum: Double? = nil,
      maximum: Double? = nil, default: Double? = nil
    ) {
      self.base = base
      self.integer = integer
      self.minimum = minimum
      self.maximum = maximum
      self.default = `default`
    }
  }

  public struct BooleanField: Codable, Hashable, Sendable {
    public var base: FormFieldBase
    public var `default`: Bool?

    public init(base: FormFieldBase, default: Bool? = nil) {
      self.base = base
      self.default = `default`
    }
  }

  public struct MultiselectField: Codable, Hashable, Sendable {
    public var base: FormFieldBase
    public var options: [FormOption]
    public var minItems: Int?
    public var maxItems: Int?
    public var custom: Bool
    public var `default`: [String]?

    public init(
      base: FormFieldBase, options: [FormOption], minItems: Int? = nil, maxItems: Int? = nil,
      custom: Bool = false, default: [String]? = nil
    ) {
      self.base = base
      self.options = options
      self.minItems = minItems
      self.maxItems = maxItems
      self.custom = custom
      self.default = `default`
    }
  }

  /**
   A link the user has to go and deal with elsewhere. Every one of these must be
   acknowledged — answered with `true` — before the form will submit, whether or
   not it is marked required.
   */
  public struct ExternalField: Codable, Hashable, Sendable {
    public var base: FormFieldBase
    public var url: String

    public init(base: FormFieldBase, url: String) {
      self.base = base
      self.url = url
    }
  }

  case string(StringField)
  case number(NumberField)
  case boolean(BooleanField)
  case multiselect(MultiselectField)
  case external(ExternalField)

  public var base: FormFieldBase {
    switch self {
    case .string(let field): return field.base
    case .number(let field): return field.base
    case .boolean(let field): return field.base
    case .multiselect(let field): return field.base
    case .external(let field): return field.base
    }
  }

  public var key: String { base.key }
  public var id: String { base.key }

  /// The wire discriminator, so screens can label a field without a switch.
  public var type: String {
    switch self {
    case .string: return "string"
    case .number(let field): return field.integer ? "integer" : "number"
    case .boolean: return "boolean"
    case .multiselect: return "multiselect"
    case .external: return "external"
    }
  }

  /// True when every condition holds, which is both "render it" and "send it".
  public func isActive(in answers: FormAnswer) -> Bool {
    (base.when ?? []).allSatisfy { $0.holds(in: answers) }
  }

  private enum CodingKeys: String, CodingKey { case type }

  public init(from decoder: Decoder) throws {
    let tag = try decoder.container(keyedBy: CodingKeys.self)
    switch try tag.decode(String.self, forKey: .type) {
    case "number", "integer": self = .number(try NumberField(from: decoder))
    case "boolean": self = .boolean(try BooleanField(from: decoder))
    case "multiselect": self = .multiselect(try MultiselectField(from: decoder))
    case "external": self = .external(try ExternalField(from: decoder))
    default: self = .string(try StringField(from: decoder))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var tag = encoder.container(keyedBy: CodingKeys.self)
    try tag.encode(type, forKey: .type)
    switch self {
    case .string(let field): try field.encode(to: encoder)
    case .number(let field): try field.encode(to: encoder)
    case .boolean(let field): try field.encode(to: encoder)
    case .multiselect(let field): try field.encode(to: encoder)
    case .external(let field): try field.encode(to: encoder)
    }
  }
}

/**
 `form.created` / `GET /api/session/{id}/form` — a structured request the agent
 is blocked on, the same way it blocks on a permission or a question.
 */
public struct FormRequest: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var sessionID: String
  public var title: String
  public var fields: [FormField]
  public var metadata: [String: JSONValue]?

  public init(
    id: String, sessionID: String, title: String, fields: [FormField],
    metadata: [String: JSONValue]? = nil
  ) {
    self.id = id
    self.sessionID = sessionID
    self.title = title
    self.fields = fields
    self.metadata = metadata
  }
}

/**
 Read a `Form.Info` — from the REST list or off the stream — into something the
 UI can render without trusting the server's build.

 A field whose `type` this build has never heard of becomes a text field rather
 than a hole in the form: the user can still answer it, and a form that cannot
 be answered is a session that never continues.
 */
public func toFormRequest(_ json: JSONValue) -> FormRequest? {
  guard let id = json["id"].string, let sessionID = json["sessionID"].string,
    case .array(let rawFields) = json["fields"]
  else { return nil }

  let fields = rawFields.compactMap { entry -> FormField? in
    guard let key = entry["key"].string else { return nil }
    return toFormField(entry, key: key)
  }
  if fields.isEmpty { return nil }

  return FormRequest(
    id: id,
    sessionID: sessionID,
    title: json["title"].string ?? "The agent needs some details",
    fields: fields,
    metadata: json["metadata"].object
  )
}

private func toFormField(_ json: JSONValue, key: String) -> FormField {
  let base = FormFieldBase(
    key: key,
    title: json["title"].string,
    description: json["description"].string,
    required: json["required"].isTrue,
    when: toFormConditions(json["when"])
  )

  switch json["type"].string {
  case "number", "integer":
    return .number(
      .init(
        base: base,
        integer: json["type"].string == "integer",
        minimum: json["minimum"].double,
        maximum: json["maximum"].double,
        default: json["default"].double
      ))

  case "boolean":
    return .boolean(.init(base: base, default: json["default"].bool))

  case "multiselect":
    // A list with nothing to pick could never be answered; let it be typed.
    let choices = toFormOptions(json["options"])
    if !choices.isEmpty {
      return .multiselect(
        .init(
          base: base,
          options: choices,
          minItems: json["minItems"].int,
          maxItems: json["maxItems"].int,
          custom: json["custom"].isTrue,
          default: json["default"].stringArray.isEmpty ? nil : json["default"].stringArray
        ))
    }

  case "external":
    if let url = json["url"].string {
      return .external(.init(base: base, url: url))
    }

  default:
    break
  }

  let options = toFormOptions(json["options"])
  return .string(
    .init(
      base: base,
      format: json["format"].string.flatMap(FormField.StringField.Format.init(rawValue:)),
      minLength: json["minLength"].int,
      maxLength: json["maxLength"].int,
      pattern: json["pattern"].string,
      placeholder: json["placeholder"].string,
      default: json["default"].string,
      options: options.isEmpty ? nil : options,
      custom: json["custom"].isTrue
    ))
}

private func toFormOptions(_ json: JSONValue) -> [FormOption] {
  json.array.compactMap { entry in
    guard let value = entry["value"].string else { return nil }
    return FormOption(
      value: value,
      label: entry["label"].string ?? value,
      description: entry["description"].string
    )
  }
}

private func toFormConditions(_ json: JSONValue) -> [FormCondition]? {
  guard case .array(let entries) = json else { return nil }
  let conditions = entries.compactMap { entry -> FormCondition? in
    guard let key = entry["key"].string,
      let op = FormCondition.Op(rawValue: entry["op"].string ?? ""),
      let value = FormValue(scalar: entry["value"])
    else { return nil }
    return FormCondition(key: key, op: op, value: value)
  }
  return conditions.isEmpty ? nil : conditions
}

// MARK: - Agents, models, MCP

/// `GET /api/agent` — one agent the session can run under.
public struct AgentInfo: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var name: String?
  public var description: String?
  /// `primary` agents can be run directly; `subagent` cannot.
  public var mode: String?
  public var hidden: Bool

  public init(
    id: String, name: String? = nil, description: String? = nil, mode: String? = nil,
    hidden: Bool = false
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.mode = mode
    self.hidden = hidden
  }

  public init?(json: JSONValue) {
    guard let id = json["id"].string else { return nil }
    self.id = id
    name = json["name"].string ?? id
    description = json["description"].string
    mode = json["mode"].string
    hidden = json["hidden"].isTrue
  }
}

/// What a model will accept and produce, which is what gates the attach button.
public struct ModelCapabilities: Codable, Hashable, Sendable {
  public var tools: Bool
  /// Modalities the model accepts: `text`, `image`, `pdf`, `audio`, `video`.
  public var input: [String]
  public var output: [String]

  public init(tools: Bool = false, input: [String] = [], output: [String] = []) {
    self.tools = tools
    self.input = input
    self.output = output
  }

  public var acceptsImages: Bool { input.contains("image") }
  public var acceptsPDFs: Bool { input.contains("pdf") }
}

/// `GET /api/model` — one model the session can run.
public struct ModelInfo: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var providerID: String
  public var name: String?
  public var family: String?
  /// The model's named variants, e.g. a "thinking" mode.
  public var variants: [String]
  public var capabilities: ModelCapabilities
  public var enabled: Bool?
  public var status: String?

  public init(
    id: String, providerID: String, name: String? = nil, family: String? = nil,
    variants: [String] = [], capabilities: ModelCapabilities = .init(),
    enabled: Bool? = nil, status: String? = nil
  ) {
    self.id = id
    self.providerID = providerID
    self.name = name
    self.family = family
    self.variants = variants
    self.capabilities = capabilities
    self.enabled = enabled
    self.status = status
  }

  public init?(json: JSONValue) {
    guard let providerID = json["providerID"].string,
      let id = json["modelID"].string ?? json["id"].string
    else { return nil }
    self.id = id
    self.providerID = providerID
    name = json["name"].string ?? id
    family = json["family"].string
    // v2 lists a variant as `{id, settings}`; older builds sent bare strings.
    variants = json["variants"].array.compactMap { $0.string ?? $0["id"].string }
    let caps = json["capabilities"]
    capabilities = ModelCapabilities(
      tools: caps["tools"].isTrue,
      input: caps["input"].stringArray,
      output: caps["output"].stringArray
    )
    enabled = json["enabled"].bool
    status = json["status"].string
  }

  public var ref: ModelRef { ModelRef(providerID: providerID, modelID: id) }
}

/**
 One MCP server the opencode process knows about.

 `GET /api/mcp` returns `{name, status: {status}}` entries; this narrows them,
 because every screen wants a flat list. `failed` carries the reason — it is a
 server the user meant to run, so the error is the whole story.
 */
public struct McpServer: Codable, Hashable, Sendable, Identifiable {
  public enum Status: String, Codable, Hashable, Sendable {
    case connected
    case disabled
    case failed
  }

  public var name: String
  public var status: Status
  public var error: String?

  public var id: String { name }

  public init(name: String, status: Status, error: String? = nil) {
    self.name = name
    self.status = status
    self.error = error
  }

  public init?(json: JSONValue) {
    guard let name = json["name"].string else { return nil }
    self.name = name
    let reported = json["status"]["status"].string ?? ""
    status = Status(rawValue: reported) ?? .disabled
    error = json["status"]["error"].string
  }
}
