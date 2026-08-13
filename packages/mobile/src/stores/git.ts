import { onScopeDispose, ref } from "vue"
import { ApiError, toUserMessage } from "@/api/errors"
import type {
  FileChangeStatus,
  FileDiff,
  FileStatus,
  GitCommit,
  GitCommitDetail,
  VcsCommitResult,
} from "@/api/types"
import { parseUnifiedDiff } from "@/lib/diff"
import { relativeTo } from "@/lib/format"
import { onServerEvent, requireClient } from "@/stores/connection"

/** A git operation that failed, translated into something readable. */
export class GitOperationError extends Error {
  /** Raw stderr, kept for the collapsible detail a developer will open. */
  readonly detail: string | null

  constructor(message: string, detail: string | null = null) {
    super(message)
    this.name = "GitOperationError"
    this.detail = detail
  }
}

export interface GitFailure {
  message: string
  detail: string | null
}

/** Normalise anything thrown by an action into what the UI renders. */
export function toGitFailure(error: unknown): GitFailure {
  if (error instanceof GitOperationError) return { message: error.message, detail: error.detail }
  return { message: toUserMessage(error), detail: null }
}

export interface CommitResult {
  shortHash: string | null
  subject: string
}

export function useGit(directory: string) {
  const controller = new AbortController()
  const signal = controller.signal

  const status = ref<GitStatus | null>(null)
  const statusLoading = ref(false)
  const statusError = ref<string | null>(null)

  const diff = ref<FileDiff | null>(null)
  const diffLoading = ref(false)
  const diffError = ref<string | null>(null)

  const commits = ref<GitCommit[]>([])
  const commitsLoading = ref(false)
  const commitsError = ref<string | null>(null)

  // A commit never changes once written, so both are safe to keep for the
  // lifetime of the screen — reopening a commit tab costs nothing.
  const commitCache = new Map<string, GitCommitDetail>()
  const commitDiffCache = new Map<string, FileDiff>()

  // Late responses from a superseded refresh must not overwrite a newer one.
  let statusToken = 0
  let diffToken = 0
  let commitsToken = 0

  // ── status ──────────────────────────────────────────────────────────────

  async function refreshStatus(): Promise<void> {
    const token = ++statusToken
    statusLoading.value = true
    statusError.value = null

    try {
      const [info, files] = await Promise.all([
        requireClient()
          .getVcsInfo(directory, signal)
          .catch(() => null),
        requireClient().fileStatus(directory, signal),
      ])

      const isRepo = info !== null || files.length > 0
      if (token !== statusToken) return
      status.value = {
        isRepo,
        branch: info?.branch ?? null,
        upstream: info?.default_branch ?? null,
        ahead: info?.ahead ?? 0,
        behind: info?.behind ?? 0,
        files,
      }
    } catch (error) {
      if (isAborted(error) || token !== statusToken) return
      statusError.value = toUserMessage(error)
    } finally {
      if (token === statusToken) statusLoading.value = false
    }
  }

  // ── one file's diff ─────────────────────────────────────────────────────

  async function refreshDiff(path: string): Promise<void> {
    const token = ++diffToken
    diffLoading.value = true
    diffError.value = null
    try {
      const patch = await readPatch(path)
      if (token !== diffToken) return
      diff.value = parseUnifiedDiff(patch, path)
    } catch (error) {
      if (isAborted(error) || token !== diffToken) return
      diffError.value = toUserMessage(error)
    } finally {
      if (token === diffToken) diffLoading.value = false
    }
  }

  async function refreshCommits(limit = 20): Promise<void> {
    const token = ++commitsToken
    commitsLoading.value = true
    commitsError.value = null
    try {
      const result = await requireClient().getVcsCommits(directory, limit, signal)
      if (token !== commitsToken) return
      commits.value = result
    } catch (error) {
      if (isAborted(error) || token !== commitsToken) return
      commitsError.value = toUserMessage(error)
    } finally {
      if (token === commitsToken) commitsLoading.value = false
    }
  }

  /** One commit and the files it touched. Cached: a tab can be reopened. */
  async function loadCommit(hash: string): Promise<GitCommitDetail | null> {
    const cached = commitCache.get(hash)
    if (cached) return cached
    const detail = await requireClient().getCommitDetail(directory, hash, signal)
    if (detail) commitCache.set(hash, detail)
    return detail
  }

  /** One file's patch inside a commit, parsed into hunks. */
  async function loadCommitDiff(hash: string, path: string): Promise<FileDiff> {
    const key = `${hash}:${path}`
    const cached = commitDiffCache.get(key)
    if (cached) return cached
    const patch = await requireClient().getCommitFileDiff(directory, hash, path, signal)
    const parsed = parseUnifiedDiff(patch, path)
    commitDiffCache.set(key, parsed)
    return parsed
  }

  /**
   * The server's diff is the whole tree in one response; the one file we want
   * is picked out and parsed.
   */
  async function readPatch(path: string): Promise<string> {
    const changes = await requireClient().getVcsDiff(directory, "working", signal)
    const match = changes.find(
      (entry) => relativeTo(directory, entry.file) === relativeTo(directory, path),
    )
    return match?.patch ?? ""
  }

  // ── mutations ───────────────────────────────────────────────────────────

  async function commit(message: string): Promise<CommitResult> {
    const result = await requireClient().commitVcs(directory, message, signal)
    assertCommitted(result)
    await refreshStatus()
    const shortHash = result.hash ? result.hash.slice(0, 7) : null
    return { shortHash, subject: message.split("\n")[0]!.trim() }
  }

  /** Resolves with the line to show on success — the remote it reached. */
  async function push(): Promise<string> {
    const result = await requireClient().pushVcs(directory, signal)
    if (!result.pushed) {
      throw new GitOperationError(
        explainPushFailure(result.message ?? ""),
        result.message?.trim() || null,
      )
    }
    await refreshStatus()
    const target = status.value?.upstream
    return target ? `Pushed to ${target}.` : "Pushed."
  }

  function assertCommitted(result: VcsCommitResult): void {
    if (!result.committed) {
      const text = result.message ?? ""
      throw new GitOperationError(
        explainCommitFailure(text),
        text.includes("\n") ? text : text.trim() || null,
      )
    }
  }

  // ── live refresh ────────────────────────────────────────────────────────

  // The agent edits files while this screen is open; without this the status
  // list silently goes stale behind a running session. `filesystem.changed`
  // only fires for writes the server itself made, so a finished turn or a vcs
  // event is also treated as "the tree may have changed", and a periodic poll
  // catches edits made outside the server entirely.
  let pending: ReturnType<typeof setTimeout> | null = null
  const schedule = () => {
    if (pending) clearTimeout(pending)
    pending = setTimeout(() => {
      pending = null
      if (status.value) void refreshStatus()
    }, 500)
  }

  // The v2 stream is global, so an event from another directory is not ours.
  const stopListening = onServerEvent((event) => {
    if (event.directory && !samePath(event.directory, directory)) return
    if (
      event.type === "filesystem.changed" ||
      event.type.startsWith("vcs.") ||
      event.type === "session.idle" ||
      event.type === "session.step.ended" ||
      event.type === "session.execution.succeeded"
    ) {
      schedule()
    }
  })

  const pollTimer = setInterval(() => {
    if (document.visibilityState === "visible" && status.value) void refreshStatus()
  }, 30_000)

  onScopeDispose(() => {
    stopListening()
    clearInterval(pollTimer)
    if (pending) clearTimeout(pending)
    controller.abort()
  })

  return {
    status,
    statusLoading,
    statusError,
    diff,
    diffLoading,
    diffError,
    commits,
    commitsLoading,
    commitsError,
    refreshStatus,
    refreshDiff,
    refreshCommits,
    loadCommit,
    loadCommitDiff,
    commit,
    push,
  }
}

export type GitStore = ReturnType<typeof useGit>

export interface GitStatus {
  isRepo: boolean
  branch: string | null
  /** The repository's default branch, which is the nearest thing to upstream. */
  upstream: string | null
  ahead: number
  behind: number
  /** Every changed file, in one flat list — the VCS API does not bucket. */
  files: FileStatus[]
}

// ── failure copy ──────────────────────────────────────────────────────────

/** What comes back is git's own line; restate the ones worth restating. */
function explainCommitFailure(text: string): string {
  const lower = text.toLowerCase()
  if (lower.includes("nothing to commit") || lower.includes("no changes added")) {
    return "The working tree is clean, so there is nothing to commit."
  }
  if (
    lower.includes("please tell me who you are") ||
    lower.includes("unable to auto-detect email")
  ) {
    return "git has no identity configured on the server. Set user.name and user.email there first."
  }
  if (lower.includes("not a git repository")) {
    return "The server's working directory is not a git repository."
  }
  if (lower.includes("index.lock")) {
    return "Another git process is holding the index lock. Try again in a moment."
  }
  const trimmed = text.trim()
  return trimmed ? `git refused the commit: ${trimmed.split("\n")[0]}` : "git refused the commit."
}

/** Push failures arrive as one sentence; keep the raw text for the detail. */
function explainPushFailure(text: string): string {
  const lower = text.toLowerCase()
  if (lower.includes("no upstream") || lower.includes("no configured push destination")) {
    return "This branch has no upstream yet. Set one on the server with git push -u."
  }
  if (
    lower.includes("non-fast-forward") ||
    lower.includes("rejected") ||
    lower.includes("fetch first")
  ) {
    return "The push was rejected — the remote has commits this branch does not. Pull or rebase on the server first."
  }
  if (
    lower.includes("authentication failed") ||
    lower.includes("could not read username") ||
    lower.includes("permission denied") ||
    lower.includes("publickey")
  ) {
    return "The remote refused these credentials. The server's git needs access to the remote."
  }
  if (lower.includes("everything up-to-date")) {
    return "Everything is already up to date on the remote."
  }
  const trimmed = text.trim()
  return trimmed ? `git refused to push: ${trimmed.split("\n")[0]}` : "git refused to push."
}

function isAborted(error: unknown): boolean {
  return error instanceof ApiError && error.kind === "aborted"
}

/** macOS resolves /tmp to /private/tmp, so the two spellings must compare equal. */
function samePath(left: string, right: string): boolean {
  const strip = (value: string) => value.replace(/^\/private(?=\/)/, "").replace(/\/+$/, "")
  return strip(left) === strip(right)
}

/** Re-exported so callers don't need the type import twice. */
export type { FileChangeStatus }
