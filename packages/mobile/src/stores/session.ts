import { computed, onUnmounted, ref, toValue, watch, type MaybeRefOrGetter } from "vue"
import { isApiError, toUserMessage } from "@/api/errors"
import type { MessageInfo, MessageWithParts, ModelRef, Part, ServerEvent } from "@/api/types"
import { onServerEvent, requireClient } from "@/stores/connection"

/**
 * One chat session: its history, the live stream that grows it, and sending.
 *
 * A session is fed by two transports at once — the POST that starts a turn
 * returns the finished assistant message, while the SSE stream delivers the
 * same message and its parts as they are produced. Neither is authoritative and
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

/** A turn whose last event is older than this is assumed dead, not streaming. */
const STALE_TURN_MS = 10 * 60_000

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

  /** The agent this session runs under, for the composer's selector. */
  const agent = ref<string | null>(null)
  /** The model (and variant) this session runs under, for the composer. */
  const model = ref<ModelRef | null>(null)

  /**
   * Parts can arrive before the message that owns them; the stream makes no
   * ordering promise across event types. They wait here rather than being
   * dropped or inventing a message shell we'd have to guess the role of.
   */
  const orphanParts = new Map<string, Part[]>()

  let controller = new AbortController()
  let localCounter = 0

  const isStreaming = computed(() => sending.value || busy.value)

  // ── reading ──────────────────────────────────────────────────────────────

  function adopt(message: MessageWithParts): SessionMessage {
    return { info: message.info, parts: message.parts ?? [], delivery: "sent", failure: null, draft: null }
  }

  function indexOfMessage(id: string): number {
    return messages.value.findIndex((message) => message.info.id === id)
  }

  /** Insert by creation time so a message that arrives late still lands in order. */
  function insertMessage(message: SessionMessage): void {
    const created = message.info.time.created
    const at = messages.value.findIndex((existing) => existing.info.time.created > created)
    if (at === -1) messages.value.push(message)
    else messages.value.splice(at, 0, message)

    const waiting = orphanParts.get(message.info.id)
    if (waiting) {
      orphanParts.delete(message.info.id)
      for (const part of waiting) upsertPart(part)
    }
  }

  function upsertInfo(info: MessageInfo): void {
    const at = indexOfMessage(info.id)
    if (at !== -1) {
      // Keep our local parts and delivery flags; only the server's view of the
      // message envelope (tokens, model, completion, error) is being replaced.
      messages.value[at]!.info = info
      if (info.role === "assistant") busy.value = !info.time.completed
      return
    }

    // The server announcing a user message while our optimistic one is still in
    // flight *is* that message — adopt the real id rather than showing both.
    if (info.role === "user") {
      const optimistic = messages.value.find(
        (message) => isLocalId(message.info.id) && message.delivery === "sending",
      )
      if (optimistic) {
        optimistic.info = info
        optimistic.delivery = "sent"
        const waiting = orphanParts.get(info.id)
        if (waiting) {
          orphanParts.delete(info.id)
          for (const part of waiting) upsertPart(part)
        }
        return
      }
    }

    if (info.role === "assistant" && !info.time.completed) busy.value = true
    insertMessage(adopt({ info, parts: [] }))
  }

  function upsertPart(part: Part): void {
    const at = indexOfMessage(part.messageID)
    if (at === -1) {
      const queue = orphanParts.get(part.messageID) ?? []
      const existing = queue.findIndex((queued) => queued.id === part.id)
      if (existing === -1) queue.push(part)
      else queue[existing] = part
      orphanParts.set(part.messageID, queue)
      return
    }

    const message = messages.value[at]!
    if (!isLocalId(part.id) && message.parts.some((existing) => isLocalId(existing.id))) {
      message.parts = message.parts.filter((existing) => !isLocalId(existing.id))
    }

    const partAt = message.parts.findIndex((existing) => existing.id === part.id)
    if (partAt === -1) {
      message.parts.push(part)
      return
    }

    // Some builds patch a part rather than resending it whole; a payload that
    // has lost the text it already delivered must not blank the bubble.
    const previous = message.parts[partAt]!
    message.parts[partAt] = part.text === undefined && previous.text ? { ...part, text: previous.text } : part
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

  function removeMessage(id: string): void {
    const at = indexOfMessage(id)
    if (at !== -1) messages.value.splice(at, 1)
    orphanParts.delete(id)
  }

  function removePart(messageId: string, partId: string): void {
    const at = indexOfMessage(messageId)
    if (at === -1) return
    const message = messages.value[at]!
    message.parts = message.parts.filter((part) => part.id !== partId)
  }

  // ── server events ────────────────────────────────────────────────────────

  /** Event payloads have moved between builds; read defensively, not by version. */
  function readInfo(props: Record<string, unknown>): MessageInfo | null {
    const candidate = (props.info ?? props.message ?? props) as Partial<MessageInfo>
    if (!candidate || typeof candidate.id !== "string" || typeof candidate.role !== "string") return null
    if (!candidate.time) return null
    return candidate as MessageInfo
  }

  function readPart(props: Record<string, unknown>): Part | null {
    const candidate = (props.part ?? props) as Partial<Part>
    if (!candidate || typeof candidate.id !== "string" || typeof candidate.messageID !== "string") return null
    return candidate as Part
  }

  function handleEvent(event: ServerEvent): void {
    const sid = toValue(sessionId)
    // The payload moved between builds: current ones put it in `data` with the
    // sessionID at the top level, older ones in `properties`. Read both.
    const props = (event.data ?? event.properties ?? {}) as Record<string, unknown>

    switch (event.type) {
      case "message.updated":
      case "message.created": {
        const info = readInfo(props)
        if (!info || info.sessionID !== sid) return
        upsertInfo(info)
        return
      }
      case "message.part.updated":
      case "message.part.created": {
        const part = readPart(props)
        if (!part) return
        // A part without a sessionID is trusted only when we already hold its
        // message, so another session's stream can never leak into this list.
        if (part.sessionID ? part.sessionID !== sid : indexOfMessage(part.messageID) === -1) return
        // Builds that stream incrementally send only a `delta`; builds that
        // resend the part whole carry `text`. Preferring `text` when it is
        // present is what stops a payload holding both from being counted twice.
        const delta = typeof props.delta === "string" ? props.delta : ""
        if (part.text === undefined && delta) {
          if (!appendDelta(part.messageID, part.id, delta)) upsertPart({ ...part, text: delta })
        } else {
          upsertPart(part)
        }
        return
      }
      case "message.part.removed": {
        const messageId = props.messageID
        const partId = props.partID ?? props.id
        if (typeof messageId === "string" && typeof partId === "string") removePart(messageId, partId)
        return
      }
      case "message.removed": {
        const messageId = props.messageID ?? props.id
        if (typeof messageId === "string") removeMessage(messageId)
        return
      }
      case "session.idle":
      case "session.error": {
        if (props.sessionID === undefined || props.sessionID === sid) busy.value = false
        return
      }
      default:
    }
  }

  // ── loading ──────────────────────────────────────────────────────────────

  async function load(): Promise<void> {
    const sid = toValue(sessionId)
    if (!sid) return

    loading.value = true
    error.value = null
    try {
      const history = await requireClient().listMessages(sid, toValue(directory), controller.signal)
      messages.value = history.map(adopt)
      // The session record carries the agent and model it is running under;
      // the composer reads these. Both are absent on older builds.
      const detail = await requireClient().getSession(sid, toValue(directory), controller.signal).catch(() => null)
      if (detail?.agent) agent.value = detail.agent
      if (detail?.model && typeof detail.model === "object") {
        const m = detail.model as Record<string, unknown>
        const modelID = typeof m.id === "string" ? m.id : typeof m.modelID === "string" ? m.modelID : null
        const providerID =
          typeof m.providerID === "string" ? m.providerID : typeof m.provider === "string" ? m.provider : null
        if (modelID && providerID) {
          model.value = {
            providerID,
            modelID,
            variant: typeof m.variant === "string" ? m.variant : undefined,
          }
        }
      }
      // Walking in cold on a live turn should still offer Stop, but an assistant
      // message left uncompleted by a crashed turn must not pin the UI to busy.
      const last = messages.value[messages.value.length - 1]
      busy.value =
        last?.info.role === "assistant" &&
        !last.info.time.completed &&
        Date.now() - last.info.time.created < STALE_TURN_MS
    } catch (cause) {
      if (isApiError(cause) && cause.kind === "aborted") return
      error.value = toUserMessage(cause)
    } finally {
      loading.value = false
    }
  }

  function reload(): void {
    void load()
  }

  // ── sending ──────────────────────────────────────────────────────────────

  async function deliver(message: SessionMessage): Promise<void> {
    const sid = toValue(sessionId)
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
        signal: controller.signal,
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
      sending.value = false
      busy.value = false
    }
  }

  /** Optimistic: the bubble is on screen before the request leaves the phone. */
  async function send(text: string): Promise<void> {
    const body = text.trim()
    if (!body || sending.value) return

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
    if (!message || message.delivery !== "failed" || sending.value) return
    await deliver(message)
  }

  async function abort(): Promise<void> {
    const sid = toValue(sessionId)
    try {
      await requireClient().abortSession(sid, toValue(directory))
    } catch {
      // Abort is best-effort: the turn may already have finished on its own,
      // and there is nothing useful to say if the request itself fails.
    } finally {
      busy.value = false
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
      controller = new AbortController()
      orphanParts.clear()
      messages.value = []
      sending.value = false
      busy.value = false
      void load()
    },
    { immediate: true },
  )

  onUnmounted(() => {
    stopEvents()
    controller.abort()
  })

  return {
    messages,
    loading,
    error,
    sending,
    isStreaming,
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
