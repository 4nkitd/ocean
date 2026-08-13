import { computed, onUnmounted, ref, toValue, watch, type MaybeRefOrGetter } from "vue"
import { toolOutput } from "@/api/client"
import { isApiError, toUserMessage } from "@/api/errors"
import type {
  InboxDelivery,
  InboxItem,
  MessageInfo,
  MessageWithParts,
  ModelRef,
  Part,
  PermissionReply,
  PermissionRequest,
  QuestionInfo,
  QuestionOption,
  QuestionRequest,
  PromptAttachment,
  ServerEvent,
  TokenUsage,
} from "@/api/types"
import { onServerEvent, requireClient } from "@/stores/connection"

/**
 * One chat session: its history, the live stream that grows it, and sending.
 *
 * v2 admits a prompt and answers nothing — every token, tool call and error
 * arrives on the SSE stream as a granular event. So the transcript is built
 * twice over: `listMessages` gives the canonical history, and the stream grows
 * the turn in flight. The two meet on ids, which is why parts are keyed exactly
 * the way `toMessage` keys them — `<messageID>:<ordinal>` for text and
 * reasoning, `<messageID>:tool:<callID>` for tools. A part the stream created
 * and a part the history returned are then the same part.
 *
 * The one thing the stream never announces is the user's own message: v2
 * persists it and moves on. So the optimistic bubble stays local until a
 * refetch (on `session.execution.started`) hands back the server's copy.
 */

/** Where an optimistic user turn is in its journey to the server. */
export type DeliveryStatus = "sent" | "sending" | "failed"

export interface SessionMessage extends MessageWithParts {
  delivery: DeliveryStatus
  /** Set when `delivery === "failed"` — rendered beside the retry control. */
  failure: string | null
  /** The prompt text, kept so a failed turn can be resent without retyping. */
  draft: string | null
  /** The images that went with `draft`, kept for the same reason. */
  draftAttachments: PromptAttachment[]
}

/** Ids we mint ourselves — the optimistic turn and the local system notes. */
const LOCAL_PREFIX = "local:"

function isLocalId(id: string): boolean {
  return id.startsWith(LOCAL_PREFIX)
}

/**
 * What the user last ran in this directory.
 *
 * A new v2 session starts with no agent or model of its own, so without this
 * every new session would open on the server's default and the choice would
 * have to be made again. Kept per directory: a different repo is usually a
 * different kind of work.
 */
const PREFERENCE_KEY = "opencode.mobile.lastRun"

interface RunPreference {
  agent?: string
  model?: ModelRef
}

function loadPreference(directory: string | undefined): RunPreference {
  if (!directory) return {}
  try {
    const raw = localStorage.getItem(`${PREFERENCE_KEY}:${directory}`)
    return raw ? (JSON.parse(raw) as RunPreference) : {}
  } catch {
    return {}
  }
}

function savePreference(directory: string | undefined, preference: RunPreference): void {
  if (!directory) return
  try {
    localStorage.setItem(`${PREFERENCE_KEY}:${directory}`, JSON.stringify(preference))
  } catch {
    // Private browsing refuses writes; the choice still holds for this session.
  }
}

export function useSession(
  sessionId: MaybeRefOrGetter<string>,
  directory: MaybeRefOrGetter<string | undefined>,
) {
  const messages = ref<SessionMessage[]>([])
  const loading = ref(false)
  const error = ref<string | null>(null)
  /** A prompt POST is in flight. */
  const sending = ref(false)
  /** The server is producing a turn — driven entirely by the stream. */
  const busy = ref(false)
  /** What the server is doing when that is more than "busy" — a retry, say. */
  const statusNote = ref<string | null>(null)
  const activeAssistantId = ref<string | null>(null)
  /**
   * Requests the agent is blocked on. Oldest first: the agent asks one at a
   * time, and answering the oldest is what unblocks it.
   */
  const permissions = ref<PermissionRequest[]>([])
  const questions = ref<QuestionRequest[]>([])
  /**
   * Prompts admitted while the agent was mid-turn. v2 holds them in a session
   * inbox and delivers them when the turn ends, which is what makes it possible
   * to line up the next instruction instead of waiting at the screen.
   */
  const queued = ref<InboxItem[]>([])
  /** How the next prompt goes out while the agent is busy. */
  const deliveryMode = ref<InboxDelivery>("queue")

  /** The agent this session runs under, for the composer's selector. */
  const agent = ref<string | null>(null)
  const title = ref<string | null>(null)
  /** The model (and variant) this session runs under, for the composer. */
  const model = ref<ModelRef | null>(null)

  let controller = new AbortController()
  let promptController: AbortController | null = null
  let localCounter = 0
  let loadToken = 0
  let syncing = false
  let compactionNoteId: string | null = null

  const isStreaming = computed(() => sending.value || busy.value)

  // ── transcript ───────────────────────────────────────────────────────────

  function adopt(message: MessageWithParts): SessionMessage {
    return {
      info: message.info,
      parts: [...(message.parts ?? [])],
      delivery: "sent",
      failure: null,
      draft: null,
      draftAttachments: [],
    }
  }

  function indexOfMessage(id: string): number {
    return messages.value.findIndex((message) => message.info.id === id)
  }

  function findMessage(id: string): SessionMessage | undefined {
    const at = indexOfMessage(id)
    return at === -1 ? undefined : messages.value[at]!
  }

  function mergeInfo(previous: MessageInfo, next: MessageInfo): MessageInfo {
    const tokens =
      previous.tokens || next.tokens
        ? {
            ...previous.tokens,
            ...next.tokens,
            cache:
              previous.tokens?.cache || next.tokens?.cache
                ? { ...previous.tokens?.cache, ...next.tokens?.cache }
                : undefined,
          }
        : undefined
    return {
      ...previous,
      ...next,
      time: { ...previous.time, ...next.time },
      ...(tokens ? { tokens } : {}),
    }
  }

  function mergePart(previous: Part, next: Part): Part {
    const merged: Part = { ...previous, ...next }
    if (previous.state && next.state)
      merged.state = { ...previous.state, ...next.state } as Part["state"]
    return merged
  }

  function messageText(message: MessageWithParts): string {
    return message.parts
      .filter((part) => part.type === "text" && typeof part.text === "string")
      .map((part) => part.text!.trim())
      .join("\n\n")
      .trim()
  }

  function reconcileOptimistic(): void {
    const serverUsers = messages.value.filter(
      (message) => !isLocalId(message.info.id) && message.info.role === "user",
    )
    for (const local of messages.value.filter(
      (message) =>
        isLocalId(message.info.id) &&
        message.info.role === "user" &&
        message.delivery !== "failed",
    )) {
      const draft = local.draft?.trim() ?? ""
      // An images-only turn has no text to match on, so the attachment count
      // stands in for it — otherwise the local bubble would never be reconciled
      // and would sit beside the server's copy of the same turn.
      if (!draft && local.draftAttachments.length === 0) continue
      const match = serverUsers.find(
        (candidate) =>
          messageText(candidate) === draft &&
          candidate.parts.filter((part) => part.type === "file").length ===
            local.draftAttachments.length &&
          candidate.info.time.created >= local.info.time.created - 5_000,
      )
      if (match) removeMessage(local.info.id)
    }
  }

  function mergeHistory(history: MessageWithParts[]): void {
    for (const message of history) {
      // The turn streaming right now is more current than the copy the server
      // just handed back — its parts are still growing here.
      if (message.info.id === activeAssistantId.value) continue
      upsertInfo(message.info)
      for (const part of message.parts ?? []) upsertPart(part)
    }
    reconcileOptimistic()
    messages.value.sort((left, right) => left.info.time.created - right.info.time.created)
  }

  /** Insert by creation time so a message that arrives late still lands in order. */
  function insertMessage(message: SessionMessage): void {
    const created = message.info.time.created
    const at = messages.value.findIndex((existing) => existing.info.time.created > created)
    if (at === -1) messages.value.push(message)
    else messages.value.splice(at, 0, message)
  }

  function upsertInfo(info: MessageInfo): void {
    const existing = findMessage(info.id)
    if (existing) {
      existing.info = mergeInfo(existing.info, info)
      return
    }

    // The server's copy of a user message we are still holding optimistically
    // *is* that message — adopt the real id rather than showing both.
    if (info.role === "user") {
      const optimistic = messages.value.find(
        (message) =>
          isLocalId(message.info.id) &&
          message.info.role === "user" &&
          message.delivery !== "failed",
      )
      if (optimistic) {
        optimistic.info = info
        optimistic.delivery = "sent"
        return
      }
    }

    insertMessage(adopt({ info, parts: [] }))
  }

  function upsertPart(part: Part): void {
    const message = findMessage(part.messageID)
    if (!message) return

    if (!isLocalId(part.id) && message.parts.some((existing) => isLocalId(existing.id))) {
      message.parts = message.parts.filter((existing) => !isLocalId(existing.id))
    }

    const at = message.parts.findIndex((existing) => existing.id === part.id)
    if (at === -1) message.parts.push(part)
    else message.parts[at] = mergePart(message.parts[at]!, part)
  }

  function removeMessage(id: string): void {
    const at = indexOfMessage(id)
    if (at !== -1) messages.value.splice(at, 1)
  }

  // ── stream targets ───────────────────────────────────────────────────────

  /**
   * The assistant message a step is producing. `session.step.started` is the
   * only announcement of it, so this both creates and patches.
   */
  function ensureAssistant(id: string, patch?: Partial<MessageInfo>): SessionMessage {
    const existing = findMessage(id)
    if (existing) {
      if (patch) existing.info = { ...existing.info, ...patch }
      return existing
    }
    const message = adopt({
      info: {
        id,
        sessionID: toValue(sessionId),
        role: "assistant",
        kind: "assistant",
        time: { created: Date.now() },
        ...patch,
      },
      parts: [],
    })
    messages.value.push(message)
    return message
  }

  /** Text and reasoning are addressed by their ordinal inside the message. */
  function textPart(
    data: Record<string, unknown>,
    type: "text" | "reasoning",
  ): Part | undefined {
    const messageID = str(data.assistantMessageID)
    const ordinal = num(data.ordinal)
    if (!messageID || ordinal === null) return undefined

    const message = ensureAssistant(messageID)
    const id = `${messageID}:${ordinal}`
    const existing = message.parts.find((part) => part.id === id)
    if (existing) return existing

    const part: Part = {
      id,
      messageID,
      sessionID: message.info.sessionID,
      type,
      ordinal,
      text: "",
      synthetic: true,
    }
    message.parts.push(part)
    return message.parts[message.parts.length - 1]
  }

  /** Tool calls are addressed by their call id, which is stable across events. */
  function toolPart(data: Record<string, unknown>): Part | undefined {
    const callID = str(data.id)
    if (!callID) return undefined
    const messageID = str(data.assistantMessageID)
    if (!messageID) {
      for (const message of messages.value) {
        const found = message.parts.find(
          (part) => part.type === "tool" && part.callID === callID,
        )
        if (found) return found
      }
      return undefined
    }

    const message = ensureAssistant(messageID)
    const id = `${messageID}:tool:${callID}`
    const existing = message.parts.find((part) => part.id === id)
    if (existing) {
      const name = str(data.name)
      if (name && !existing.tool) existing.tool = name
      return existing
    }

    const part: Part = {
      id,
      messageID,
      sessionID: message.info.sessionID,
      type: "tool",
      tool: str(data.name) ?? undefined,
      callID,
      ordinal: message.parts.length,
      state: { status: "pending" },
    }
    message.parts.push(part)
    return message.parts[message.parts.length - 1]
  }

  /** The input the call was made with, carried forward as the state advances. */
  function toolInput(part: Part): Record<string, unknown> | undefined {
    const state = part.state
    if (!state || state.status === "pending" || state.status === "streaming") return undefined
    return state.input
  }

  function toolTitle(part: Part): string | undefined {
    const state = part.state
    if (!state || state.status === "pending") return undefined
    return state.title
  }

  function toolStart(part: Part): number {
    const state = part.state
    if (!state || state.status === "pending") return Date.now()
    return state.time?.start ?? Date.now()
  }

  /** A note in the transcript for something the server did outside a turn. */
  function pushNote(kind: string, text: string): string {
    const id = `${LOCAL_PREFIX}${kind}:${localCounter++}`
    const sid = toValue(sessionId)
    insertMessage(
      adopt({
        info: { id, sessionID: sid, role: "system", kind, time: { created: Date.now() } },
        parts: [{ id: `${id}:text`, messageID: id, sessionID: sid, type: "text", text }],
      }),
    )
    return id
  }

  function compactionNote(text: string, final: boolean): void {
    const existing = compactionNoteId ? findMessage(compactionNoteId) : undefined
    if (existing) {
      const part = existing.parts[0]
      if (part) part.text = text
      if (final) compactionNoteId = null
      return
    }
    const id = pushNote("compaction", text)
    compactionNoteId = final ? null : id
  }

  function failActive(message: string): void {
    const active = activeAssistantId.value ? findMessage(activeAssistantId.value) : undefined
    if (active) {
      active.info = { ...active.info, error: { name: "Session error", data: { message } } }
      return
    }
    pushNote("error", message)
  }

  function settle(): void {
    busy.value = false
    statusNote.value = null
    activeAssistantId.value = null
    // A prompt whose server copy never arrived leaves the local echo behind.
    if (
      messages.value.some(
        (message) =>
          isLocalId(message.info.id) &&
          message.info.role === "user" &&
          message.delivery === "sent",
      )
    )
      void sync()
  }

  // ── server events ────────────────────────────────────────────────────────

  function handleEvent(event: ServerEvent): void {
    if (event.type === "stream.reconnected") {
      void load()
      return
    }

    const sid = toValue(sessionId)
    if (!sid || event.sessionID !== sid) return
    const data = event.data ?? {}

    switch (event.type) {
      case "session.step.started": {
        const id = str(data.assistantMessageID)
        if (!id) return
        const ref = record(data.model)
        ensureAssistant(id, {
          agent: str(data.agent) ?? undefined,
          modelID: str(ref?.id) ?? str(ref?.modelID) ?? undefined,
          providerID: str(ref?.providerID) ?? undefined,
          variant: str(ref?.variant) ?? undefined,
        })
        activeAssistantId.value = id
        busy.value = true
        return
      }

      case "session.step.ended": {
        const id = str(data.assistantMessageID)
        if (!id) return
        const message = ensureAssistant(id)
        message.info = {
          ...message.info,
          time: { ...message.info.time, completed: Date.now() },
          cost: num(data.cost) ?? message.info.cost,
          tokens: tokensOf(data.tokens) ?? message.info.tokens,
          finish: str(data.finish) ?? message.info.finish,
        }
        if (activeAssistantId.value === id) activeAssistantId.value = null
        return
      }

      case "session.step.failed": {
        const id = str(data.assistantMessageID)
        if (!id) return
        const failure = record(data.error)
        const message = ensureAssistant(id)
        message.info = {
          ...message.info,
          time: { ...message.info.time, completed: Date.now() },
          cost: num(data.cost) ?? message.info.cost,
          tokens: tokensOf(data.tokens) ?? message.info.tokens,
          error: {
            name: str(failure?.name) ?? "Turn failed",
            data: { message: str(failure?.message) ?? "The model turn failed." },
          },
        }
        if (activeAssistantId.value === id) activeAssistantId.value = null
        return
      }

      case "session.text.started":
      case "session.reasoning.started": {
        const part = textPart(data, event.type === "session.text.started" ? "text" : "reasoning")
        if (!part) return
        part.text = ""
        part.synthetic = true
        return
      }

      case "session.text.delta":
      case "session.reasoning.delta": {
        const delta = str(data.delta)
        if (!delta) return
        const part = textPart(data, event.type === "session.text.delta" ? "text" : "reasoning")
        if (!part) return
        part.text = `${part.text ?? ""}${delta}`
        return
      }

      case "session.text.ended":
      case "session.reasoning.ended": {
        const part = textPart(data, event.type === "session.text.ended" ? "text" : "reasoning")
        if (!part) return
        if (typeof data.text === "string") part.text = data.text
        part.synthetic = false
        return
      }

      case "session.tool.input.started": {
        const part = toolPart(data)
        if (!part) return
        part.state = { status: "streaming", inputText: "" }
        return
      }

      case "session.tool.input.delta": {
        const delta = str(data.delta)
        if (!delta) return
        const part = toolPart(data)
        if (!part) return
        const previous =
          part.state?.status === "streaming" ? (part.state.inputText ?? "") : ""
        part.state = { status: "streaming", inputText: `${previous}${delta}` }
        return
      }

      case "session.tool.input.ended": {
        const part = toolPart(data)
        if (!part) return
        const text =
          typeof data.text === "string"
            ? data.text
            : part.state?.status === "streaming"
              ? (part.state.inputText ?? "")
              : ""
        part.state = { status: "streaming", inputText: text }
        return
      }

      case "session.tool.called": {
        const part = toolPart(data)
        if (!part) return
        part.state = {
          status: "running",
          title: toolTitle(part),
          input: record(data.input) ?? undefined,
          time: { start: Date.now() },
        }
        return
      }

      case "session.tool.progress": {
        const part = toolPart(data)
        if (!part) return
        const metadata = record(data.metadata)
        part.state = {
          status: "running",
          title: str(metadata?.title) ?? toolTitle(part),
          input: toolInput(part),
          time: { start: toolStart(part) },
        }
        return
      }

      case "session.tool.success": {
        const part = toolPart(data)
        if (!part) return
        const metadata = record(data.metadata)
        part.state = {
          status: "completed",
          title: str(metadata?.title) ?? toolTitle(part),
          input: toolInput(part),
          output: toolOutput(data.content),
          metadata: metadata ?? undefined,
          time: { start: toolStart(part), end: Date.now() },
        }
        return
      }

      case "session.tool.failed": {
        const part = toolPart(data)
        if (!part) return
        const metadata = record(data.metadata)
        part.state = {
          status: "error",
          error: str(record(data.error)?.message) ?? "The tool failed",
          title: str(metadata?.title) ?? toolTitle(part),
          input: toolInput(part),
          metadata: metadata ?? undefined,
          time: { start: toolStart(part), end: Date.now() },
        }
        return
      }

      case "session.execution.started": {
        busy.value = true
        statusNote.value = null
        // v2 never announces the user's own message; this is where the server's
        // copy replaces the optimistic bubble.
        void sync()
        return
      }

      case "session.execution.succeeded":
      case "session.execution.interrupted":
      case "session.idle": {
        settle()
        return
      }

      case "session.execution.failed": {
        failActive(str(record(data.error)?.message) ?? "The turn failed.")
        settle()
        return
      }

      case "session.status": {
        const status = record(data.status)
        const type = str(status?.type)
        if (type === "busy") {
          busy.value = true
          statusNote.value = null
        } else if (type === "retry") {
          busy.value = true
          const attempt = num(status?.attempt)
          const reason = str(status?.message) ?? "retrying"
          statusNote.value = attempt ? `${reason} (attempt ${attempt})` : reason
        } else if (type === "idle") {
          settle()
        }
        return
      }

      case "session.retry.scheduled": {
        busy.value = true
        const attempt = num(data.attempt)
        const reason = str(record(data.error)?.message) ?? "the turn failed"
        statusNote.value = attempt ? `retrying (attempt ${attempt}) — ${reason}` : `retrying — ${reason}`
        return
      }

      case "session.renamed": {
        title.value = str(data.title)
        return
      }

      case "session.agent.selected": {
        agent.value = str(data.agent)
        return
      }

      case "session.model.selected": {
        const ref = record(data.model)
        const modelID = str(ref?.id) ?? str(ref?.modelID)
        const providerID = str(ref?.providerID)
        if (modelID && providerID)
          model.value = { providerID, modelID, variant: str(ref?.variant) ?? undefined }
        return
      }

      case "session.compaction.started": {
        compactionNote("Compacting the conversation…", false)
        return
      }

      case "session.compaction.ended": {
        compactionNote("Conversation compacted.", true)
        return
      }

      case "session.compaction.failed": {
        compactionNote(
          `Compaction failed — ${str(record(data.error)?.message) ?? "unknown error"}`,
          true,
        )
        return
      }

      case "permission.asked": {
        const id = str(data.id)
        if (!id || permissions.value.some((request) => request.id === id)) return
        permissions.value = [
          ...permissions.value,
          {
            id,
            sessionID: sid,
            action: str(data.action) ?? "run",
            resources: Array.isArray(data.resources)
              ? data.resources.filter((entry): entry is string => typeof entry === "string")
              : [],
            save: Array.isArray(data.save)
              ? data.save.filter((entry): entry is string => typeof entry === "string")
              : undefined,
            metadata: record(data.metadata) ?? undefined,
          },
        ]
        return
      }

      case "permission.replied": {
        // Answered here, from the desktop, or by a saved rule — all the same.
        const requestID = str(data.requestID)
        permissions.value = permissions.value.filter((request) => request.id !== requestID)
        return
      }

      case "question.asked": {
        const request = toQuestionRequest(data)
        if (!request || questions.value.some((entry) => entry.id === request.id)) return
        questions.value = [...questions.value, request]
        return
      }

      case "question.replied":
      case "question.rejected": {
        const requestID = str(data.requestID)
        questions.value = questions.value.filter((entry) => entry.id !== requestID)
        return
      }

      case "session.inbox.enqueued": {
        const inboxID = str(data.inboxID)
        const item = record(data.item)
        if (!inboxID || queued.value.some((entry) => entry.id === inboxID)) return
        const payload = record(item?.payload)
        queued.value = [
          ...queued.value,
          {
            id: inboxID,
            sessionID: sid,
            timeCreated: Date.now(),
            type: str(item?.type) ?? "user",
            text: str(payload?.text) ?? "",
            delivery: str(item?.delivery) === "steer" ? "steer" : "queue",
            attachments: Array.isArray(payload?.files) ? payload.files.length : 0,
          },
        ]
        return
      }

      case "session.inbox.delivered":
      case "session.inbox.cancelled": {
        const inboxID = str(data.inboxID)
        queued.value = queued.value.filter((entry) => entry.id !== inboxID)
        // Delivery turns it into a real message; the transcript needs to catch up.
        if (event.type === "session.inbox.delivered") void sync()
        return
      }

      case "session.inbox.delivery.changed": {
        const inboxID = str(data.inboxID)
        const delivery = str(data.delivery) === "steer" ? "steer" : "queue"
        queued.value = queued.value.map((entry) =>
          entry.id === inboxID ? { ...entry, delivery } : entry,
        )
        return
      }

      default:
    }
  }

  // ── loading ──────────────────────────────────────────────────────────────

  async function load(): Promise<void> {
    const sid = toValue(sessionId)
    if (!sid) return
    const token = ++loadToken
    const requestController = controller
    const dir = toValue(directory)

    loading.value = true
    error.value = null
    try {
      const client = requireClient()
      const [history, detail, statuses, pending, inbox, asked] = await Promise.all([
        client.listMessages(sid, dir, requestController.signal),
        client.getSession(sid, dir, requestController.signal).catch(() => null),
        client.getSessionStatuses(dir, requestController.signal).catch(() => null),
        client.listPermissions(sid, requestController.signal).catch(() => []),
        client.listInbox(sid, requestController.signal).catch(() => []),
        client.listQuestions(sid, dir, requestController.signal).catch(() => []),
      ])
      if (token !== loadToken || requestController.signal.aborted) return
      mergeHistory(history)
      permissions.value = pending
      questions.value = asked.filter((request) => request.sessionID === sid)
      queued.value = inbox
      title.value = detail?.title?.trim() || null

      /*
       * Three sources, in descending order of authority: what the session is
       * already set to, what the user last ran in this directory, and what the
       * server would pick on its own. Without the last two a new session shows
       * an empty selector and the choice has to be made again every time.
       */
      const remembered = loadPreference(dir)
      const sessionModelID = detail?.model?.modelID ?? detail?.model?.id
      const sessionProviderID = detail?.model?.providerID ?? detail?.model?.provider

      agent.value = detail?.agent ?? remembered.agent ?? null
      model.value =
        sessionModelID && sessionProviderID
          ? {
              providerID: sessionProviderID,
              modelID: sessionModelID,
              variant: detail?.model?.variant,
            }
          : (remembered.model ?? null)

      if (!agent.value || !model.value) {
        const defaults = await client.getDefaults(dir, requestController.signal).catch(() => null)
        if (token !== loadToken) return
        agent.value = agent.value ?? defaults?.agent ?? null
        model.value = model.value ?? defaults?.model ?? null
      }

      const status = statuses?.[sid]?.type
      busy.value = status === "busy" || status === "retry"
    } catch (cause) {
      if (token !== loadToken || (isApiError(cause) && cause.kind === "aborted")) return
      error.value = toUserMessage(cause)
    } finally {
      if (token === loadToken) loading.value = false
    }
  }

  /** Refresh the history without touching the loading state or the transcript. */
  async function sync(): Promise<void> {
    const sid = toValue(sessionId)
    if (!sid || syncing) return
    syncing = true
    const requestController = controller
    try {
      const history = await requireClient().listMessages(
        sid,
        toValue(directory),
        requestController.signal,
      )
      if (toValue(sessionId) !== sid || requestController.signal.aborted) return
      mergeHistory(history)
    } catch {
      // The transcript already holds its own copy of the turn; a refresh that
      // failed is not worth a banner.
    } finally {
      syncing = false
    }
  }

  function reload(): void {
    controller.abort()
    controller = new AbortController()
    void load()
  }

  // ── sending ──────────────────────────────────────────────────────────────

  async function deliver(message: SessionMessage): Promise<void> {
    const sid = toValue(sessionId)
    const requestController = new AbortController()
    promptController = requestController
    message.delivery = "sending"
    message.failure = null
    sending.value = true
    // A prompt sent into a running turn is queued, not started — the turn in
    // flight owns `busy` until it ends.
    const queueing = busy.value
    if (!queueing) busy.value = true

    try {
      // The prompt is only *admitted* here — the turn arrives on the stream.
      await requireClient().sendPrompt(sid, message.draft ?? "", {
        directory: toValue(directory),
        providerID: model.value?.providerID,
        modelID: model.value?.modelID,
        variant: model.value?.variant,
        agent: agent.value ?? undefined,
        attachments: message.draftAttachments,
        ...(queueing ? { delivery: deliveryMode.value } : {}),
        signal: requestController.signal,
      })
      message.delivery = "sent"
      // Queued prompts live in the inbox strip, not the transcript: the server
      // has not turned them into messages yet, and showing both would double.
      if (queueing) removeMessage(message.info.id)
    } catch (cause) {
      // Unmount aborts the request; the screen is gone, so there is nobody to
      // tell and no failed bubble worth keeping.
      if (isApiError(cause) && cause.kind === "aborted") return
      message.delivery = "failed"
      message.failure = toUserMessage(cause)
      if (!queueing) busy.value = false
    } finally {
      if (promptController === requestController) promptController = null
      sending.value = false
    }
  }

  /** Optimistic: the bubble is on screen before the request leaves the phone. */
  async function send(text: string, attachments: PromptAttachment[] = []): Promise<void> {
    const body = text.trim()
    // An image on its own is a legitimate prompt — "what is this?" is implied.
    // Sending mid-turn is allowed: it queues.
    if ((!body && attachments.length === 0) || loading.value || sending.value) return

    const id = `${LOCAL_PREFIX}${Date.now()}:${localCounter++}`
    const sid = toValue(sessionId)
    const parts: Part[] = attachments.map((attachment) => ({
      id: `${id}:file:${attachment.id}`,
      messageID: id,
      sessionID: sid,
      type: "file",
      mime: attachment.mime,
      filename: attachment.filename,
      url: attachment.url,
    }))
    if (body)
      parts.push({ id: `${id}:text`, messageID: id, sessionID: sid, type: "text", text: body })

    const optimistic: SessionMessage = {
      info: { id, sessionID: sid, role: "user", kind: "user", time: { created: Date.now() } },
      parts,
      delivery: "sending",
      failure: null,
      draft: body,
      draftAttachments: attachments,
    }
    insertMessage(optimistic)
    await deliver(optimistic)
  }

  /** Resend a turn the server never accepted, from its own failed bubble. */
  async function retry(messageId: string): Promise<void> {
    const message = messages.value.find((candidate) => candidate.info.id === messageId)
    if (!message || message.delivery !== "failed" || loading.value || sending.value || busy.value)
      return
    await deliver(message)
  }

  async function abort(): Promise<void> {
    const sid = toValue(sessionId)
    const requestController = promptController
    try {
      await requireClient().abortSession(sid, toValue(directory))
    } catch {
      // Abort is best-effort: the turn may already have finished on its own,
      // and there is nothing useful to say if the request itself fails.
    } finally {
      requestController?.abort()
      if (promptController === requestController) promptController = null
      sending.value = false
      busy.value = false
      statusNote.value = null
      activeAssistantId.value = null
    }
  }

  /**
   * Answer the request the agent is blocked on. The row goes away immediately —
   * `permission.replied` confirms it, but the agent resumes either way and the
   * card must not sit there looking unanswered.
   */
  async function respondPermission(requestId: string, reply: PermissionReply): Promise<void> {
    const request = permissions.value.find((candidate) => candidate.id === requestId)
    if (!request) return
    permissions.value = permissions.value.filter((candidate) => candidate.id !== requestId)
    try {
      await requireClient().replyPermission(toValue(sessionId), requestId, reply)
    } catch (cause) {
      // Put it back: an unanswered request is the whole reason this screen
      // exists, so failing quietly would be the worst outcome.
      permissions.value = [...permissions.value, request].sort((left, right) =>
        left.id.localeCompare(right.id),
      )
      throw cause
    }
  }

  async function respondQuestion(requestId: string, answers: string[][]): Promise<void> {
    const request = questions.value.find((candidate) => candidate.id === requestId)
    if (!request) return
    questions.value = questions.value.filter((candidate) => candidate.id !== requestId)
    try {
      await requireClient().replyQuestion(toValue(sessionId), requestId, answers, toValue(directory))
    } catch (cause) {
      questions.value = [...questions.value, request].sort((left, right) =>
        left.id.localeCompare(right.id),
      )
      throw cause
    }
  }

  async function rejectQuestion(requestId: string): Promise<void> {
    const request = questions.value.find((candidate) => candidate.id === requestId)
    if (!request) return
    questions.value = questions.value.filter((candidate) => candidate.id !== requestId)
    try {
      await requireClient().rejectQuestion(toValue(sessionId), requestId, toValue(directory))
    } catch (cause) {
      questions.value = [...questions.value, request].sort((left, right) =>
        left.id.localeCompare(right.id),
      )
      throw cause
    }
  }

  /**
   * Run a `/command`. The server owns the template — the client sends the name
   * and whatever followed it, never the expansion.
   */
  async function runCommand(name: string, args: string): Promise<void> {
    if (loading.value || sending.value) return
    const sid = toValue(sessionId)
    const queueing = busy.value
    sending.value = true
    if (!queueing) busy.value = true
    try {
      await requireClient().runCommand(sid, name, args, {
        ...(queueing ? { delivery: deliveryMode.value } : {}),
      })
    } catch (cause) {
      if (!queueing) busy.value = false
      error.value = toUserMessage(cause)
    } finally {
      sending.value = false
    }
  }

  /** Drop a waiting prompt before the agent gets to it. */
  async function cancelQueued(inboxId: string): Promise<void> {
    const previous = queued.value
    queued.value = queued.value.filter((entry) => entry.id !== inboxId)
    try {
      await requireClient().cancelInbox(toValue(sessionId), inboxId)
    } catch {
      queued.value = previous
    }
  }

  /** Move a waiting prompt between "after this turn" and "cut in now". */
  async function setQueuedDelivery(inboxId: string, delivery: InboxDelivery): Promise<void> {
    const previous = queued.value
    queued.value = queued.value.map((entry) =>
      entry.id === inboxId ? { ...entry, delivery } : entry,
    )
    try {
      await requireClient().setInboxDelivery(toValue(sessionId), inboxId, delivery)
    } catch {
      queued.value = previous
    }
  }

  /** Switch the session's agent; the next prompt runs under it. */
  async function setAgent(next: string): Promise<void> {
    const previous = agent.value
    if (next === previous) return
    agent.value = next
    try {
      await requireClient().switchAgent(toValue(sessionId), next)
      savePreference(toValue(directory), { agent: next, model: model.value ?? undefined })
    } catch (cause) {
      agent.value = previous
      throw cause
    }
  }

  /** Switch the session's model (and optional variant); the next prompt uses it. */
  async function setModel(next: ModelRef): Promise<void> {
    const previous = model.value
    const same =
      previous?.providerID === next.providerID &&
      previous?.modelID === next.modelID &&
      (previous?.variant ?? null) === (next.variant ?? null)
    if (same) return
    model.value = next
    try {
      await requireClient().switchModel(toValue(sessionId), next)
      savePreference(toValue(directory), { agent: agent.value ?? undefined, model: next })
    } catch (cause) {
      model.value = previous
      throw cause
    }
  }

  // ── lifecycle ────────────────────────────────────────────────────────────

  const stopEvents = onServerEvent(handleEvent)

  watch(
    () => toValue(sessionId),
    () => {
      // The route can swap sessions under a mounted view; drop everything the
      // previous one had in flight before touching the list.
      controller.abort()
      promptController?.abort()
      promptController = null
      controller = new AbortController()
      messages.value = []
      title.value = null
      agent.value = null
      model.value = null
      permissions.value = []
      questions.value = []
      queued.value = []
      sending.value = false
      busy.value = false
      statusNote.value = null
      activeAssistantId.value = null
      compactionNoteId = null
      void load()
    },
    { immediate: true },
  )

  onUnmounted(() => {
    stopEvents()
    promptController?.abort()
    controller.abort()
  })

  return {
    messages,
    loading,
    error,
    sending,
    isStreaming,
    statusNote,
    permissions,
    questions,
    queued,
    deliveryMode,
    title,
    agent,
    model,
    send,
    retry,
    abort,
    reload,
    respondPermission,
    respondQuestion,
    rejectQuestion,
    runCommand,
    cancelQueued,
    setQueuedDelivery,
    setAgent,
    setModel,
  }
}

// ── event payload readers ───────────────────────────────────────────────────

function toQuestionRequest(data: Record<string, unknown>): QuestionRequest | null {
  const id = str(data.id)
  const sessionID = str(data.sessionID)
  if (!id || !sessionID || !Array.isArray(data.questions)) return null

  const questions = data.questions
    .flatMap((entry): QuestionInfo[] => {
      const info = record(entry)
      const question = str(info?.question)
      if (!question) return []
      const options = Array.isArray(info?.options)
        ? info.options
            .flatMap((option): QuestionOption[] => {
              const parsed = record(option)
              const label = str(parsed?.label)
              return label
                ? [{ label, description: str(parsed?.description) ?? undefined }]
                : []
            })
        : []
      return [
        {
          question,
          header: str(info?.header) ?? undefined,
          options,
          multiple: info?.multiple === true,
          custom: info?.custom !== false,
        },
      ]
    })

  if (questions.length === 0) return null
  return { id, sessionID, questions }
}

function str(value: unknown): string | null {
  return typeof value === "string" && value ? value : null
}

function num(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null
}

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null ? (value as Record<string, unknown>) : null
}

function tokensOf(value: unknown): TokenUsage | undefined {
  const raw = record(value)
  if (!raw) return undefined
  const cache = record(raw.cache)
  return {
    input: num(raw.input) ?? undefined,
    output: num(raw.output) ?? undefined,
    reasoning: num(raw.reasoning) ?? undefined,
    cache: cache
      ? { read: num(cache.read) ?? undefined, write: num(cache.write) ?? undefined }
      : undefined,
  }
}
