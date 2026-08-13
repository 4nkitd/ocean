import { computed, onMounted, onUnmounted, ref } from "vue"
import type { PermissionRequest, ServerEvent, Session } from "@/api/types"
import { toUserMessage } from "@/api/errors"
import { basename } from "@/lib/format"
import { onServerEvent, requireClient } from "@/stores/connection"
import { readString, sessionIdOf } from "@/stores/projects"

/**
 * Every session working right now, across every project on this server.
 *
 * The app is otherwise organised by project, which is the right shape when you
 * are choosing what to work on and the wrong one when something is already
 * running: an agent left going an hour ago is three taps away, and an agent
 * blocked on a permission is invisible until you go looking. This is the other
 * axis — time, not place — and it is shared by the mobile tab and the desktop
 * panel so the two can never disagree.
 */
export interface ActiveRow {
  session: Session
  directory: string
  project: string
  /** Set when the agent is blocked and doing nothing until answered. */
  request: PermissionRequest | null
  started: number | null
}

export function useActiveSessions() {
  const sessions = ref<Session[]>([])
  const blocked = ref<Map<string, PermissionRequest>>(new Map())
  const since = ref<Map<string, number>>(new Map())
  const loading = ref(true)
  const error = ref<string | null>(null)
  /** Ticks so the elapsed column counts up without a refetch. */
  const now = ref(Date.now())

  let controller = new AbortController()
  let stopEvents: (() => void) | null = null
  let tick: ReturnType<typeof setInterval> | null = null

  const rows = computed<ActiveRow[]>(() => {
    const list = sessions.value.map<ActiveRow>((session) => {
      const directory = session.directory ?? ""
      return {
        session,
        directory,
        project: directory ? basename(directory) : "unknown project",
        request: blocked.value.get(session.id) ?? null,
        started: since.value.get(session.id) ?? session.time?.updated ?? null,
      }
    })
    // Blocked first: those are the ones that will never finish on their own.
    return list.sort((left, right) => {
      if (!!left.request !== !!right.request) return left.request ? -1 : 1
      return (right.started ?? 0) - (left.started ?? 0)
    })
  })

  const blockedCount = computed(() => rows.value.filter((row) => row.request).length)

  function elapsed(row: ActiveRow): string {
    if (!row.started) return ""
    const seconds = Math.max(0, Math.round((now.value - row.started) / 1000))
    if (seconds < 60) return `${seconds}s`
    const minutes = Math.floor(seconds / 60)
    if (minutes < 60) return `${minutes}m ${seconds % 60}s`
    return `${Math.floor(minutes / 60)}h ${minutes % 60}m`
  }

  async function load(): Promise<void> {
    controller.abort()
    controller = new AbortController()
    const own = controller
    loading.value = true
    error.value = null
    try {
      const client = requireClient()
      const [active, pending] = await Promise.all([
        client.listActiveSessions(own.signal),
        client.listPendingPermissions(undefined, own.signal).catch(() => []),
      ])
      if (own.signal.aborted) return
      sessions.value = active
      blocked.value = new Map(pending.map((request) => [request.sessionID, request]))
      const stamps = new Map(since.value)
      for (const session of active) {
        if (!stamps.has(session.id)) stamps.set(session.id, session.time?.updated ?? Date.now())
      }
      since.value = stamps
    } catch (cause) {
      if (own.signal.aborted) return
      error.value = toUserMessage(cause)
    } finally {
      if (!own.signal.aborted) loading.value = false
    }
  }

  /**
   * The stream is global, so this stays live from events alone — a session that
   * starts anywhere on the server appears here without a refetch.
   */
  function handleEvent(event: ServerEvent): void {
    const id = sessionIdOf(event)
    if (!id) return

    if (event.type === "permission.asked") {
      blocked.value = new Map(blocked.value).set(id, {
        id: readString(event.data, "id") ?? id,
        sessionID: id,
        action: readString(event.data, "action") ?? "run",
        resources: Array.isArray(event.data.resources)
          ? event.data.resources.filter((entry): entry is string => typeof entry === "string")
          : [],
      })
      if (!sessions.value.some((session) => session.id === id)) void load()
      return
    }

    if (event.type === "permission.replied") {
      const next = new Map(blocked.value)
      next.delete(id)
      blocked.value = next
      return
    }

    if (event.type === "session.execution.started" || event.type === "session.step.started") {
      if (!since.value.has(id)) since.value = new Map(since.value).set(id, Date.now())
      if (!sessions.value.some((session) => session.id === id)) void load()
      return
    }

    if (
      event.type === "session.idle" ||
      event.type === "session.execution.succeeded" ||
      event.type === "session.execution.failed" ||
      event.type === "session.execution.interrupted" ||
      event.type === "session.deleted"
    ) {
      sessions.value = sessions.value.filter((session) => session.id !== id)
      const stamps = new Map(since.value)
      stamps.delete(id)
      since.value = stamps
      const next = new Map(blocked.value)
      next.delete(id)
      blocked.value = next
    }
  }

  onMounted(() => {
    stopEvents = onServerEvent(handleEvent)
    tick = setInterval(() => (now.value = Date.now()), 1000)
    void load()
  })

  onUnmounted(() => {
    stopEvents?.()
    controller.abort()
    if (tick) clearInterval(tick)
  })

  return { rows, loading, error, blockedCount, elapsed, reload: load }
}
