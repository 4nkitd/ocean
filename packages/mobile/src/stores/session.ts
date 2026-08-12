import { computed, onUnmounted, ref, toValue, watch, type MaybeRefOrGetter } from "vue"
import { isApiError, toUserMessage } from "@/api/errors"
import type { MessageInfo, MessageWithParts, ModelRef, Part, ServerEvent } from "@/api/types"
import { onServerEvent, requireClient } from "@/stores/connection"

/**
 * One chat session: its history, the live stream that grows it, and sending.
 *
 * A session is fed by two transports at once — the POST that starts a turn may
 * return before the assistant is finished, while the SSE stream delivers the
 * message and its parts as they are produced. Neither is authoritative and
 * neither is ordered relative to the other, so everything here is an *upsert
 * keyed on the server's id* rather than an append. See `DEDUPE` below.
 */

/** Where an optimistic user turn is in its journey to the server. */
export type DeliveryStatus = "sent" | "sending" | "failed"

export interface SessionMessage extends MessageWithParts {
  delivery: DeliveryStatus
  /** Set when `delivery === "failed"` — rendered beside the retry control. */
  failure: string | null
  /** The prompt text, kept so a failed turn can be resent without retyping. */
  draft: string | null
}

/**
 * DEDUPE
 *
 * Every message and every part carries an id the server minted, and both the
 * POST response and the event stream repeat those same ids — the stream re-sends
 * a growing text part under its original id rather than emitting deltas. So
 * writing by id can never duplicate: whichever transport arrives last simply
 * wins for that id, and arrival order stops mattering.
 *
 * The one id we mint ourselves is the optimistic user turn's, prefixed
 * `local:`. It is adopted by the first user message the server announces while
 * that turn is in flight, and any `local:` part on a message is dropped the
 * moment a real server part lands on it — the placeholder's text and the
 * server's text are the same content under two ids, and only id-keyed writes
 * would otherwise leave both.
 */
const LOCAL_PREFIX = "local:"

function isLocalId(id: string): boolean {
  return id.startsWith(LOCAL_PREFIX)
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
  /** The server is producing a turn — set by us on send, cleared by the stream. */
  const busy = ref(false)
  const activeAssistantId = ref<string | null>(null)

  /** The agent this session runs under, for the composer's selector. */
  const agent = ref<string | null>(null)
  const title = ref<string | null>(null)
  /** The model (and variant) this session runs under, for the composer. */
  const model = ref<ModelRef | null>(null)

  /**
   * Parts can arrive before the message that owns them; the stream makes no
   * ordering promise across event types. They wait here rather than being
   * dropped or inventing a message shell we'd have to guess the role of.
   */
  const orphanParts = new Map<string, Part[]>()
  const orphanDeltas = new Map<string, Map<string, string>>()

  let controller = new AbortController()
  let promptController: AbortController | null = null
  let localCounter = 0
  let loadToken = 0

  const isStreaming = computed(() => sending.value || busy.value)

  // ── reading ──────────────────────────────────────────────────────────────

  function adopt(message: MessageWithParts): SessionMessage {
    return {
      info: message.info,
      parts: [...(message.parts ?? [])],
      delivery: "sent",
      failure: null,
      draft: null,
    }
  }

  function indexOfMessage(id: string): number {
    return messages.value.findIndex((message) => message.info.id === id)
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

  function updateAssistantActivity(info: MessageInfo): void {
    if (!info.time.completed) {
      activeAssistantId.value = info.id
      busy.value = true
      return
    }
    if (activeAssistantId.value !== info.id) return
    activeAssistantId.value = null
    if (
      !sending.value &&
      !messages.value.some(
        (message) => message.info.role === "assistant" && !message.info.time.completed,
      )
    ) {
      busy.value = false
    }
  }

  function applySessionStatus(statusType: string | undefined): void {
    if (statusType === "busy" || statusType === "retry") {
      const pending = [...messages.value]
        .reverse()
        .find((message) => message.info.role === "assistant" && !message.info.time.completed)
      activeAssistantId.value = pending?.info.id ?? activeAssistantId.value
      busy.value = true
    } else if (statusType === "idle") {
      activeAssistantId.value = null
      busy.value = false
    } else if (!activeAssistantId.value && !sending.value) {
      busy.value = false
    }
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
      (message) => isLocalId(message.info.id) && message.delivery !== "failed",
    )) {
      const draft = local.draft?.trim()
      if (!draft) continue
      const match = serverUsers.find(
        (candidate) =>
          messageText(candidate) === draft &&
          candidate.info.time.created >= local.info.time.created - 5_000,
      )
      if (match) removeMessage(local.info.id)
    }
  }

  function mergeHistory(history: MessageWithParts[]): void {
    for (const message of history) {
      upsertInfo(message.info, false)
      for (const part of message.parts ?? []) upsertPart(part)
    }
    reconcileOptimistic()
    messages.value.sort((left, right) => left.info.time.created - right.info.time.created)
  }

  function drainOrphans(messageId: string): void {
    const waiting = orphanParts.get(messageId)
    if (waiting) {
      orphanParts.delete(messageId)
      for (const part of waiting) upsertPart(part)
    }

    const deltas = orphanDeltas.get(messageId)
    if (deltas) {
      orphanDeltas.delete(messageId)
      for (const [partId, delta] of deltas) {
        if (!appendDelta(messageId, partId, delta)) queueDelta(messageId, partId, delta)
      }
    }
  }

  /** Insert by creation time so a message that arrives late still lands in order. */
  function insertMessage(message: SessionMessage): void {
    const created = message.info.time.created
    const at = messages.value.findIndex((existing) => existing.info.time.created > created)
    if (at === -1) messages.value.push(message)
    else messages.value.splice(at, 0, message)

    drainOrphans(message.info.id)
  }

  function upsertInfo(info: MessageInfo, live = true): void {
    const at = indexOfMessage(info.id)
    if (at !== -1) {
      const message = messages.value[at]!
      message.info = mergeInfo(message.info, info)
      if (live && message.info.role === "assistant") updateAssistantActivity(message.info)
      return
    }

    // The server announcing a user message while our optimistic one is still in
    // flight *is* that message — adopt the real id rather than showing both.
    if (info.role === "user") {
      const optimistic = messages.value.find(
        (message) => isLocalId(message.info.id) && message.delivery !== "failed",
      )
      if (optimistic) {
        optimistic.info = info
        optimistic.delivery = "sent"
        drainOrphans(info.id)
        return
      }
    }

    if (live && info.role === "assistant") updateAssistantActivity(info)
    insertMessage(adopt({ info, parts: [] }))
  }

  function upsertPart(part: Part): void {
    const at = indexOfMessage(part.messageID)
    if (at === -1) {
      const queue = orphanParts.get(part.messageID) ?? []
      const existing = queue.findIndex((queued) => queued.id === part.id)
      if (existing === -1) queue.push(part)
      else queue[existing] = mergePart(queue[existing]!, part)
      orphanParts.set(part.messageID, queue)
      return
    }

    const message = messages.value[at]!
    if (!isLocalId(part.id) && message.parts.some((existing) => isLocalId(existing.id))) {
      message.parts = message.parts.filter((existing) => !isLocalId(existing.id))
    }

    const partAt = message.parts.findIndex((existing) => existing.id === part.id)
    if (partAt === -1) {
      message.parts.push(withQueuedDelta(part))
      return
    }

    const previous = message.parts[partAt]!
    message.parts[partAt] = withQueuedDelta(mergePart(previous, part))
  }

  /** False when the part being grown is not on screen yet — caller decides. */
  function appendDelta(messageId: string, partId: string, delta: string): boolean {
    const at = indexOfMessage(messageId)
    if (at === -1) return false
    const part = messages.value[at]!.parts.find((existing) => existing.id === partId)
    if (!part) return false
    part.text = `${part.text ?? ""}${delta}`
    return true
  }

  function queueDelta(messageId: string, partId: string, delta: string): void {
    const parts = orphanDeltas.get(messageId) ?? new Map<string, string>()
    parts.set(partId, `${parts.get(partId) ?? ""}${delta}`)
    orphanDeltas.set(messageId, parts)
  }

  function withQueuedDelta(part: Part): Part {
    const pending = orphanDeltas.get(part.messageID)?.get(part.id)
    if (pending === undefined) return part
    const parts = orphanDeltas.get(part.messageID)!
    parts.delete(part.id)
    if (parts.size === 0) orphanDeltas.delete(part.messageID)
    return part.text === undefined ? { ...part, text: pending } : part
  }

  function removeMessage(id: string): void {
    const at = indexOfMessage(id)
    if (at !== -1) messages.value.splice(at, 1)
    orphanParts.delete(id)
    orphanDeltas.delete(id)
  }

  function removePart(messageId: string, partId: string): void {
    const at = indexOfMessage(messageId)
    if (at === -1) return
    const message = messages.value[at]!
    message.parts = message.parts.filter((part) => part.id !== partId)
  }

  // ── server events ────────────────────────────────────────────────────────

  /** Event payloads have moved between builds; read defensively, not by version. */
  function readInfo(
    props: Record<string, unknown>,
    eventSessionID: string | null,
  ): MessageInfo | null {
    const candidate = (props.info ?? props.message ?? props) as Partial<MessageInfo>
    if (!candidate || typeof candidate.id !== "string" || typeof candidate.role !== "string")
      return null
    if (!candidate.time) return null
    const sessionID = candidate.sessionID ?? eventSessionID
    if (!sessionID) return null
    return { ...candidate, sessionID } as MessageInfo
  }

  function readPart(props: Record<string, unknown>, eventSessionID: string | null): Part | null {
    const candidate = (props.part ?? props) as Partial<Part>
    if (!candidate || typeof candidate.id !== "string" || typeof candidate.messageID !== "string")
      return null
    const sessionID = candidate.sessionID ?? eventSessionID
    if (!sessionID) return null
    return { ...candidate, sessionID } as Part
  }

  function handleEvent(event: ServerEvent): void {
    const sid = toValue(sessionId)
    const props = (event.data ?? event.properties ?? {}) as Record<string, unknown>
    const eventSessionID =
      event.sessionID ?? stringValue(props.sessionID) ?? stringValue(props.sessionId)

    switch (event.type) {
      case "message.updated":
      case "message.created": {
        const info = readInfo(props, eventSessionID)
        if (!info || info.sessionID !== sid) return
        upsertInfo(info)
        return
      }
      case "message.part.updated":
      case "message.part.created": {
        const part = readPart(props, eventSessionID)
        if (!part) return
        if (part.sessionID ? part.sessionID !== sid : indexOfMessage(part.messageID) === -1) return
        const delta = typeof props.delta === "string" ? props.delta : ""
        if (part.text === undefined && delta) {
          if (!appendDelta(part.messageID, part.id, delta)) upsertPart({ ...part, text: delta })
        } else {
          upsertPart(part)
        }
        return
      }
      case "message.part.delta": {
        const messageID = stringValue(props.messageID)
        const partID =
          stringValue(props.partID) ?? stringValue(props.partId) ?? stringValue(props.id)
        const delta = typeof props.delta === "string" ? props.delta : ""
        if (!messageID || !partID || !delta || (eventSessionID && eventSessionID !== sid)) return
        if (!appendDelta(messageID, partID, delta)) queueDelta(messageID, partID, delta)
        return
      }
      case "message.part.removed": {
        const messageId = props.messageID
        const partId = props.partID ?? props.id
        if (eventSessionID && eventSessionID !== sid) return
        if (typeof messageId === "string" && typeof partId === "string")
          removePart(messageId, partId)
        return
      }
      case "message.removed": {
        const messageId = props.messageID ?? props.id
        if (eventSessionID && eventSessionID !== sid) return
        if (typeof messageId === "string") removeMessage(messageId)
        return
      }
      case "session.status": {
        if (!eventSessionID || eventSessionID !== sid) return
        const status = props.status
        const statusType =
          typeof status === "string"
            ? status
            : stringValue((status as Record<string, unknown>)?.type)
        applySessionStatus(statusType ?? undefined)
        return
      }
      case "session.idle":
      case "session.error": {
        if (!eventSessionID || eventSessionID !== sid) return
        if (event.type === "session.error") {
          const message = stringValue(props.message) ?? stringValue(props.error)
          if (message && activeAssistantId.value) {
            const active = messages.value.find((item) => item.info.id === activeAssistantId.value)
            if (active) active.info.error = { name: "Session error", data: { message } }
          }
        }
        busy.value = false
        activeAssistantId.value = null
        return
      }
      case "stream.reconnected": {
        void load()
        return
      }
      default:
    }
  }

  function stringValue(value: unknown): string | null {
    return typeof value === "string" && value ? value : null
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
      const [history, detail, statuses] = await Promise.all([
        client.listMessages(sid, dir, requestController.signal),
        client.getSession(sid, dir, requestController.signal).catch(() => null),
        client.getSessionStatuses(dir, requestController.signal).catch(() => null),
      ])
      if (token !== loadToken || requestController.signal.aborted) return
      mergeHistory(history)
      title.value = detail?.title?.trim() || null
      if (detail?.agent) agent.value = detail.agent
      if (detail?.model && typeof detail.model === "object") {
        const m = detail.model as Record<string, unknown>
        const modelID =
          typeof m.id === "string" ? m.id : typeof m.modelID === "string" ? m.modelID : null
        const providerID =
          typeof m.providerID === "string"
            ? m.providerID
            : typeof m.provider === "string"
              ? m.provider
              : null
        if (modelID && providerID) {
          model.value = {
            providerID,
            modelID,
            variant: typeof m.variant === "string" ? m.variant : undefined,
          }
        }
      }
      applySessionStatus(statuses?.[sid]?.type)
    } catch (cause) {
      if (token !== loadToken || (isApiError(cause) && cause.kind === "aborted")) return
      error.value = toUserMessage(cause)
    } finally {
      if (token === loadToken) loading.value = false
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
    busy.value = true

    try {
      const reply = await requireClient().sendPrompt(sid, message.draft ?? "", {
        directory: toValue(directory),
        providerID: model.value?.providerID,
        modelID: model.value?.modelID,
        variant: model.value?.variant,
        agent: agent.value ?? undefined,
        signal: requestController.signal,
      })
      message.delivery = "sent"
      // The reply is the finished assistant turn. It is written through the same
      // upserts as the stream, so whichever got here first is already covered.
      if (reply?.info?.id) {
        upsertInfo(reply.info)
        for (const part of reply.parts ?? []) upsertPart(part)
      }
    } catch (cause) {
      // Unmount aborts the request; the screen is gone, so there is nobody to
      // tell and no failed bubble worth keeping.
      if (isApiError(cause) && cause.kind === "aborted") return
      message.delivery = "failed"
      message.failure = toUserMessage(cause)
    } finally {
      if (promptController === requestController) promptController = null
      sending.value = false
    }
  }

  /** Optimistic: the bubble is on screen before the request leaves the phone. */
  async function send(text: string): Promise<void> {
    const body = text.trim()
    if (!body || loading.value || sending.value || busy.value) return

    const id = `${LOCAL_PREFIX}${Date.now()}:${localCounter++}`
    const sid = toValue(sessionId)
    const optimistic: SessionMessage = {
      info: { id, sessionID: sid, role: "user", time: { created: Date.now() } },
      parts: [{ id: `${id}:text`, messageID: id, sessionID: sid, type: "text", text: body }],
      delivery: "sending",
      failure: null,
      draft: body,
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
      activeAssistantId.value = null
    }
  }

  /** Switch the session's agent; the next prompt runs under it. */
  async function setAgent(next: string): Promise<void> {
    if (next === agent.value) return
    agent.value = next
    await requireClient().switchAgent(toValue(sessionId), next, toValue(directory))
  }

  /** Switch the session's model (and optional variant); the next prompt uses it. */
  async function setModel(next: ModelRef): Promise<void> {
    const same =
      model.value?.providerID === next.providerID &&
      model.value?.modelID === next.modelID &&
      (model.value?.variant ?? null) === (next.variant ?? null)
    if (same) return
    model.value = next
    await requireClient().switchModel(toValue(sessionId), next, toValue(directory))
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
      orphanParts.clear()
      orphanDeltas.clear()
      messages.value = []
      title.value = null
      agent.value = null
      model.value = null
      sending.value = false
      busy.value = false
      activeAssistantId.value = null
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
    title,
    agent,
    model,
    send,
    retry,
    abort,
    reload,
    setAgent,
    setModel,
  }
}
