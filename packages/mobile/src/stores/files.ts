import { computed, onScopeDispose, ref } from "vue"
import { ApiError, toUserMessage } from "@/api/errors"
import type { FileChangeStatus, FileNode } from "@/api/types"
import { requireClient } from "@/stores/connection"

/**
 * The file tree behind the Files screen.
 *
 * Three constraints shape it:
 *
 * 1. The server lists one directory level per request, and a monorepo has tens
 *    of thousands of files, so nothing is fetched until the user expands it.
 *    Once a level is loaded it stays cached — collapsing and re-expanding is a
 *    Set mutation, not a round trip.
 *
 * 2. The design renders the tree as one flat scrolling list with indentation,
 *    not as nested elements, so the shape exposed here is a flattened array
 *    carrying a depth. That is also what makes arrow-key navigation a matter of
 *    moving an index.
 *
 * 3. Git state comes from a separate endpoint keyed by path, so it is merged in
 *    here rather than at the row: a file carries its own marker, a directory
 *    carries the number of changed files somewhere beneath it.
 */

export interface TreeRow {
  path: string
  name: string
  type: "file" | "directory"
  /** 0 at the project root; drives the row's indentation. */
  depth: number
  expanded: boolean
  loading: boolean
  status: FileChangeStatus | null
  /** Directories only: changed files beneath this one. */
  changed: number
}

/** Search results are capped — a two-character query can match everything. */
const MAX_FILTER_RESULTS = 200
const FILTER_DEBOUNCE_MS = 220

export function useFileTree(directory: string) {
  /** Directory path → its (sorted) children. The cache *is* the tree. */
  const levels = ref(new Map<string, FileNode[]>())
  const expanded = ref(new Set<string>())
  const pending = ref(new Set<string>())
  const statuses = ref(new Map<string, FileChangeStatus>())

  const loading = ref(false)
  const error = ref<string | null>(null)
  const query = ref("")
  const filtering = ref(false)
  /** Absolute paths from the filter, or null when no filter is applied. */
  const matches = ref<string[] | null>(null)

  /** Aborts everything still in flight when the screen goes away. */
  const lifetime = new AbortController()
  let filterController: AbortController | null = null
  let debounce: ReturnType<typeof setTimeout> | null = null

  onScopeDispose(() => {
    if (debounce) clearTimeout(debounce)
    lifetime.abort()
  })

  // ── loading ──────────────────────────────────────────────────────────────

  async function loadLevel(path: string, force = false): Promise<void> {
    if (!force && levels.value.has(path)) return
    pending.value.add(path)
    try {
      const nodes = await requireClient().listDirectory(path, directory, lifetime.signal)
      levels.value.set(path, sortNodes(nodes))
    } catch (cause) {
      if (isAborted(cause)) return
      // A level that fails to open is collapsed again, so the chevron state
      // never claims to be showing contents it does not have.
      expanded.value.delete(path)
      error.value = toUserMessage(cause)
    } finally {
      pending.value.delete(path)
    }
  }

  async function loadStatus(): Promise<void> {
    try {
      const entries = await requireClient().fileStatus(directory, lifetime.signal)
      const next = new Map<string, FileChangeStatus>()
      for (const entry of entries) next.set(absolute(entry.path), entry.status)
      statuses.value = next
    } catch (cause) {
      if (isAborted(cause)) return
      // Git state is decoration on this screen; the tree is still usable
      // without it, so a failure here must not blank the list.
    }
  }

  /**
   * Reload the root, the working-tree status, and every level the user
   * currently has open — keeping their expansion intact is the whole point of
   * a refresh, otherwise it reads as "collapse everything".
   */
  async function refresh(): Promise<void> {
    error.value = null
    loading.value = true
    const open = [...expanded.value].sort((a, b) => a.length - b.length)
    levels.value.clear()
    try {
      await Promise.all([loadLevel(directory, true), loadStatus()])
      for (const path of open) await loadLevel(path, true)
    } finally {
      loading.value = false
    }
  }

  // ── expansion ────────────────────────────────────────────────────────────

  async function toggle(path: string): Promise<void> {
    if (expanded.value.has(path)) {
      expanded.value.delete(path)
      return
    }
    expanded.value.add(path)
    await loadLevel(path)
  }

  function collapseAll(): void {
    expanded.value.clear()
  }

  /**
   * Open every level between the root and `path`, so a file arrived at from
   * somewhere else (the viewer's "reveal in tree") is actually on screen.
   */
  async function reveal(path: string): Promise<void> {
    if (!path.startsWith(directory)) return
    const relative = path.slice(directory.length).replace(/^\//, "")
    const segments = relative.split("/")
    segments.pop() // the file itself is not a level to open
    let current = directory
    for (const segment of segments) {
      current = `${current}/${segment}`
      expanded.value.add(current)
      await loadLevel(current)
    }
  }

  // ── filtering ────────────────────────────────────────────────────────────

  function setFilter(next: string): void {
    query.value = next
    if (debounce) clearTimeout(debounce)
    if (!next.trim()) {
      filterController?.abort()
      filterController = null
      filtering.value = false
      matches.value = null
      return
    }
    // Typing on a phone keyboard produces a request per keystroke otherwise,
    // and a fuzzy search over a monorepo is not cheap on the server either.
    debounce = setTimeout(() => void runFilter(), FILTER_DEBOUNCE_MS)
  }

  async function runFilter(): Promise<void> {
    const term = query.value.trim()
    if (!term) return

    filterController?.abort()
    const controller = new AbortController()
    filterController = controller
    lifetime.signal.addEventListener("abort", () => controller.abort(), { once: true })

    filtering.value = true
    try {
      const found = await requireClient().findFiles(term, directory, controller.signal)
      if (controller.signal.aborted) return
      // `findFiles` returns an empty array both when the endpoint is missing
      // (the client swallows the 404) and when nothing matched. Falling back to
      // the loaded tree is the right answer in both cases: it either substitutes
      // for the absent endpoint, or agrees with it.
      matches.value = found.length ? found.slice(0, MAX_FILTER_RESULTS).map(absolute) : localMatches(term)
    } catch (cause) {
      if (isAborted(cause)) return
      matches.value = localMatches(term)
    } finally {
      if (filterController === controller) {
        filtering.value = false
        filterController = null
      }
    }
  }

  /** Substring match over everything already listed, used when search is out. */
  function localMatches(term: string): string[] {
    const needle = term.toLowerCase()
    const found: string[] = []
    for (const nodes of levels.value.values()) {
      for (const node of nodes) {
        if (node.type !== "file") continue
        if (relative(node.path).toLowerCase().includes(needle)) found.push(node.path)
        if (found.length >= MAX_FILTER_RESULTS) return found
      }
    }
    return found
  }

  // ── derived ──────────────────────────────────────────────────────────────

  const filterActive = computed(() => matches.value !== null)

  /** Changed files beneath each directory, so a collapsed level still reports. */
  const changedCounts = computed(() => {
    const counts = new Map<string, number>()
    for (const path of statuses.value.keys()) {
      let parent = parentOf(path)
      while (parent.length >= directory.length && parent.startsWith(directory)) {
        counts.set(parent, (counts.get(parent) ?? 0) + 1)
        if (parent === directory) break
        parent = parentOf(parent)
      }
    }
    return counts
  })

  const rows = computed<TreeRow[]>(() => {
    if (matches.value) {
      return matches.value.map((path) => ({
        path,
        // A search result is only meaningful with its path, not its basename.
        name: relative(path),
        type: "file" as const,
        depth: 0,
        expanded: false,
        loading: false,
        status: statuses.value.get(path) ?? null,
        changed: 0,
      }))
    }

    const out: TreeRow[] = []
    const walk = (path: string, depth: number) => {
      for (const node of levels.value.get(path) ?? []) {
        const isDirectory = node.type === "directory"
        const isOpen = isDirectory && expanded.value.has(node.path)
        out.push({
          path: node.path,
          name: node.name,
          type: node.type,
          depth,
          expanded: isOpen,
          loading: pending.value.has(node.path),
          status: isDirectory ? null : (statuses.value.get(node.path) ?? node.status ?? null),
          changed: isDirectory ? (changedCounts.value.get(node.path) ?? 0) : 0,
        })
        if (isOpen) walk(node.path, depth + 1)
      }
    }
    walk(directory, 0)
    return out
  })

  /**
   * Files seen so far. The server has no recursive count, and walking the whole
   * tree to produce one would defeat the lazy loading, so this grows as levels
   * are opened rather than claiming a total it cannot know.
   */
  const fileCount = computed(() => {
    let total = 0
    for (const nodes of levels.value.values()) {
      for (const node of nodes) if (node.type === "file") total++
    }
    return total
  })

  void refresh()

  return {
    rows,
    loading,
    error,
    query,
    filtering,
    filterActive,
    fileCount,
    expandedCount: computed(() => expanded.value.size),
    refresh,
    toggle,
    collapseAll,
    reveal,
    setFilter,
  }

  // ── path helpers, closed over the project root ───────────────────────────

  function absolute(path: string): string {
    return path.startsWith("/") ? path : `${directory}/${path}`
  }

  function relative(path: string): string {
    const prefix = directory.endsWith("/") ? directory : `${directory}/`
    return path.startsWith(prefix) ? path.slice(prefix.length) : path
  }
}

function parentOf(path: string): string {
  const cut = path.lastIndexOf("/")
  return cut <= 0 ? "" : path.slice(0, cut)
}

/** Directories first, then alphabetical — the order the design lists them in. */
function sortNodes(nodes: FileNode[]): FileNode[] {
  return [...nodes].sort((a, b) => {
    if (a.type !== b.type) return a.type === "directory" ? -1 : 1
    return a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" })
  })
}

function isAborted(cause: unknown): boolean {
  return cause instanceof ApiError && cause.kind === "aborted"
}
