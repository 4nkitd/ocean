import { computed, onMounted, onUnmounted, ref } from "vue"
import type { OpenCodeClient } from "@/api/client"
import { ApiError, toUserMessage } from "@/api/errors"
import type { Project, ProjectSummary, ServerEvent, Session } from "@/api/types"
import { basename, displayPath, initials } from "@/lib/format"
import { onServerEvent, requireClient } from "@/stores/connection"

/**
 * The Projects screen's data.
 *
 * A composable rather than a module singleton like `connection`: the list is
 * only interesting while the screen is mounted, and every visit should re-read
 * it — the user has been away typing at the machine the server runs on.
 */

/** User-chosen card order, by project id. Survives reconnects, hence local. */
const ORDER_KEY = "opencode.mobile.projectOrder"
/** Starred project ids. A favourite outranks the manual order. */
const FAVOURITES_KEY = "opencode.mobile.projectFavourites"

export interface ProjectRow extends ProjectSummary {
  /** True while one of this project's sessions is producing a turn. */
  running: boolean
  favourite: boolean
}

/** What `refresh` assembles per project before the running flag is layered on. */
interface LoadedProject extends ProjectSummary {
  /** Session ids, so an event carrying only a session id can be attributed. */
  sessionIds: string[]
}

export function useProjects() {
  const loaded = ref<LoadedProject[]>([])
  const loading = ref(true)
  const error = ref<string | null>(null)
  const order = ref<string[]>(loadOrder())
  const favourites = ref<Set<string>>(new Set(loadFavourites()))
  /** Sessions the event stream has shown mid-turn since this screen mounted. */
  const runningSessions = ref(new Set<string>())

  let controller: AbortController | null = null
  let unsubscribe: (() => void) | null = null

  const projects = computed<ProjectRow[]>(() => {
    const running = runningSessions.value
    const starred = favourites.value
    const rows = loaded.value.map<ProjectRow>((project) => ({
      ...project,
      running: project.sessionIds.some((id) => running.has(id)),
      favourite: starred.has(project.id),
    }))
    // Starred projects float to the top; everything below keeps the order the
    // user arranged, so pinning never scrambles the rest of the list.
    const ordered = sortByOrder(rows, order.value)
    return [
      ...ordered.filter((project) => project.favourite),
      ...ordered.filter((project) => !project.favourite),
    ]
  })

  function toggleFavourite(id: string): void {
    const next = new Set(favourites.value)
    if (next.has(id)) next.delete(id)
    else next.add(id)
    favourites.value = next
    try {
      localStorage.setItem(FAVOURITES_KEY, JSON.stringify([...next]))
    } catch {
      // Private browsing refuses writes; the pin still holds for this visit.
    }
  }

  async function refresh(): Promise<void> {
    controller?.abort()
    const current = new AbortController()
    controller = current

    loading.value = true
    error.value = null

    try {
      const client = requireClient()
      // The stream only says a session went busy while this screen is mounted;
      // the active list is what a session already mid-turn looks like on load.
      const [list, statuses] = await Promise.all([
        client.listProjects(current.signal),
        client.getSessionStatuses(undefined, current.signal).catch(() => null),
      ])

      // One failing project must not empty the screen, so each is settled on
      // its own and contributes whatever it managed to answer.
      const results = await Promise.all(
        list.map((project) => decorate(client, project, current.signal)),
      )
      if (current.signal.aborted) return
      loaded.value = results
      runningSessions.value = new Set(
        Object.entries(statuses ?? {})
          .filter(([, status]) => status.type !== "idle")
          .map(([id]) => id),
      )
    } catch (cause) {
      if (current.signal.aborted || (cause instanceof ApiError && cause.kind === "aborted")) return
      error.value = toUserMessage(cause)
    } finally {
      if (controller === current) {
        controller = null
        loading.value = false
      }
    }
  }

  /**
   * Move a card one place. The design's "Reorder" affordance is drag on a
   * desktop mock; on a phone, two buttons per row are reachable one-handed and
   * are the only form of this that works with a screen reader.
   */
  function move(id: string, delta: -1 | 1): void {
    const ids = projects.value.map((project) => project.id)
    const from = ids.indexOf(id)
    const to = from + delta
    if (from === -1 || to < 0 || to >= ids.length) return
    ids.splice(to, 0, ...ids.splice(from, 1))
    order.value = ids
    try {
      localStorage.setItem(ORDER_KEY, JSON.stringify(ids))
    } catch {
      // Private browsing refuses writes; the order still holds for this visit.
    }
  }

  /** The card whose project owns this directory — a worktree or one of its sandboxes. */
  function projectAt(directory: string | undefined): LoadedProject | undefined {
    if (!directory) return undefined
    return loaded.value.find(
      (project) =>
        project.worktree === directory || (project.directories ?? []).includes(directory),
    )
  }

  function handleEvent(event: ServerEvent): void {
    const sessionId = sessionIdOf(event)
    if (!sessionId) return

    // A session appearing or going away changes a card's count, and the whole
    // list is too expensive to re-read for one row.
    if (event.type === "session.created") {
      if (readString(event.data, "parentID")) return
      const project = projectAt(
        event.directory ?? readString(event.data, "location", "directory") ?? undefined,
      )
      if (!project || project.sessionIds.includes(sessionId)) return
      project.sessionIds = [...project.sessionIds, sessionId]
      project.sessionCount += 1
      project.lastActivity = Date.now()
      return
    }

    if (event.type === "session.deleted") {
      for (const project of loaded.value) {
        if (!project.sessionIds.includes(sessionId)) continue
        project.sessionIds = project.sessionIds.filter((id) => id !== sessionId)
        project.sessionCount = Math.max(0, project.sessionCount - 1)
      }
      return
    }

    const busy = busyChange(event)
    if (busy === null) return

    const next = new Set(runningSessions.value)
    if (busy) next.add(sessionId)
    else next.delete(sessionId)
    runningSessions.value = next
  }

  onMounted(() => {
    unsubscribe = onServerEvent(handleEvent)
    void refresh()
  })

  onUnmounted(() => {
    unsubscribe?.()
    unsubscribe = null
    controller?.abort()
  })

  return { loading, error, projects, refresh, move, toggleFavourite }
}

// ── loading one project ────────────────────────────────────────────────────

async function decorate(
  client: OpenCodeClient,
  project: Project,
  signal: AbortSignal,
): Promise<LoadedProject> {
  const [sessions, branch] = await Promise.all([
    client.listSessions(project.worktree, signal).catch(() => [] as Session[]),
    project.vcs === "git" ? currentBranch(client, project.worktree, signal) : Promise.resolve(null),
  ])

  const name = basename(project.worktree)
  const lastActivity = sessions.reduce<number | null>((latest, session) => {
    const stamp = session.time?.updated ?? session.time?.created ?? 0
    return stamp > (latest ?? 0) ? stamp : latest
  }, null)

  return {
    ...project,
    name,
    displayPath: displayPath(project.worktree),
    initials: initials(name),
    isGit: project.vcs === "git",
    branch,
    sessionCount: sessions.length,
    lastActivity,
    sessionIds: sessions.map((session) => session.id),
  }
}

/**
 * The server's `/vcs` endpoint reports the branch; a build without it answers
 * `notfound` and the card falls back to saying only that the directory is a
 * repository.
 */
async function currentBranch(
  client: OpenCodeClient,
  directory: string,
  signal: AbortSignal,
): Promise<string | null> {
  try {
    const info = await client.getVcsInfo(directory, signal)
    const branch = info?.branch?.trim() ?? ""
    return branch && branch !== "HEAD" ? branch : null
  } catch {
    return null
  }
}

/**
 * Server builds before `/project` return nothing from it, but they are working
 * servers rooted at a real directory — so the screen shows that directory
 * rather than claiming the machine has no projects.
 */

// ── ordering ───────────────────────────────────────────────────────────────

function loadFavourites(): string[] {
  try {
    const raw = localStorage.getItem(FAVOURITES_KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw) as unknown
    return Array.isArray(parsed) ? parsed.filter((id): id is string => typeof id === "string") : []
  } catch {
    return []
  }
}

function loadOrder(): string[] {
  try {
    const raw = localStorage.getItem(ORDER_KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw) as unknown
    return Array.isArray(parsed) ? parsed.filter((id): id is string => typeof id === "string") : []
  } catch {
    return []
  }
}

/**
 * Pinned projects keep the position the user gave them; anything the server has
 * grown since then falls in behind, most recently active first.
 */
function sortByOrder(rows: ProjectRow[], order: string[]): ProjectRow[] {
  const pinned = new Map(order.map((id, index) => [id, index]))
  return [...rows].sort((a, b) => {
    const left = pinned.get(a.id)
    const right = pinned.get(b.id)
    if (left !== undefined && right !== undefined) return left - right
    if (left !== undefined) return -1
    if (right !== undefined) return 1
    return (b.lastActivity ?? 0) - (a.lastActivity ?? 0)
  })
}

// ── events ─────────────────────────────────────────────────────────────────

/**
 * Pull a session id out of a v2 event. The client already lifts `sessionID`
 * from `data` at parse time, so events can be filtered on it directly.
 */
export function sessionIdOf(event: ServerEvent): string | null {
  return event.sessionID ?? readString(event.data, "sessionID")
}

/**
 * Which events move a session between running and idle. `null` means the event
 * says nothing about running state.
 */
function busyChange(event: ServerEvent): boolean | null {
  if (event.type === "session.execution.started" || event.type === "session.step.started")
    return true
  if (
    event.type === "session.idle" ||
    event.type === "session.execution.succeeded" ||
    event.type === "session.execution.failed" ||
    event.type === "session.execution.interrupted"
  )
    return false
  if (event.type === "session.status") {
    const status = readString(event.data, "status", "type")
    if (status === "busy" || status === "retry") return true
    if (status === "idle") return false
  }
  return null
}

/** Read a nested string without asserting a shape the server may not send. */
export function readString(source: unknown, ...path: string[]): string | null {
  let current = source
  for (const key of path) {
    if (typeof current !== "object" || current === null) return null
    current = (current as Record<string, unknown>)[key]
  }
  return typeof current === "string" && current ? current : null
}
