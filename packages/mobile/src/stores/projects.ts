import { computed, onMounted, onUnmounted, ref } from "vue"
import type { OpenCodeClient } from "@/api/client"
import { ApiError, toUserMessage } from "@/api/errors"
import type { Project, ProjectSummary, ServerEvent, Session } from "@/api/types"
import { basename, displayPath, initials } from "@/lib/format"
import { connection, onServerEvent, requireClient } from "@/stores/connection"

/**
 * The Projects screen's data.
 *
 * A composable rather than a module singleton like `connection`: the list is
 * only interesting while the screen is mounted, and every visit should re-read
 * it — the user has been away typing at the machine the server runs on.
 */

/** User-chosen card order, by project id. Survives reconnects, hence local. */
const ORDER_KEY = "opencode.mobile.projectOrder"

export interface ProjectRow extends ProjectSummary {
  /** True while one of this project's sessions is producing a turn. */
  running: boolean
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
  /** Sessions the event stream has shown mid-turn since this screen mounted. */
  const runningSessions = ref(new Set<string>())

  let controller: AbortController | null = null
  let unsubscribe: (() => void) | null = null

  const projects = computed<ProjectRow[]>(() => {
    const running = runningSessions.value
    const rows = loaded.value.map<ProjectRow>((project) => ({
      ...project,
      running: project.sessionIds.some((id) => running.has(id)),
    }))
    return sortByOrder(rows, order.value)
  })

  async function refresh(): Promise<void> {
    controller?.abort()
    const current = new AbortController()
    controller = current

    loading.value = true
    error.value = null

    try {
      const client = requireClient()
      const list = await client.listProjects(current.signal)
      const targets = list.length > 0 ? list : fallbackProjects()

      // One failing project must not empty the screen, so each is settled on
      // its own and contributes whatever it managed to answer.
      const results = await Promise.all(
        targets.map((project) => decorate(client, project, current.signal)),
      )
      if (current.signal.aborted) return
      loaded.value = results
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

  function handleEvent(event: ServerEvent): void {
    const sessionId = sessionIdOf(event)
    if (!sessionId) return

    const next = new Set(runningSessions.value)
    if (event.type === "session.idle" || event.type === "session.error") next.delete(sessionId)
    else if (event.type.startsWith("message.")) next.add(sessionId)
    else return

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

  return { loading, error, projects, refresh, move }
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
function fallbackProjects(): Project[] {
  const worktree = connection.workingDirectory.value
  if (!worktree) return []
  return [
    {
      id: `cwd:${worktree}`,
      worktree,
      vcs: connection.isGitRepo.value ? "git" : null,
    },
  ]
}

// ── ordering ───────────────────────────────────────────────────────────────

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
 * Pull a session id out of whichever shape this build's event uses. Older
 * servers put it at the top level, newer ones nest it under the changed record,
 * and the payload itself has moved from `properties` to `data`.
 */
export function sessionIdOf(event: ServerEvent): string | null {
  const properties = (event.data ?? event.properties ?? {}) as Record<string, unknown>
  return (
    readString(properties, "sessionID") ??
    readString(properties, "sessionId") ??
    readString(properties, "part", "sessionID") ??
    readString(properties, "info", "sessionID") ??
    (event.type.startsWith("session.") ? readString(properties, "info", "id") : null)
  )
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
