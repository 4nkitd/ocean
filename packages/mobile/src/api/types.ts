/**
 * Shapes returned by the opencode server's HTTP API.
 *
 * These are hand-written rather than generated because the client targets a
 * range of server builds and has to tolerate fields that only newer ones send.
 * Anything not guaranteed across the versions we support is optional here, and
 * the client normalises it — screens should never branch on server version.
 */

/**
 * Where the server is rooted and whether it is a repository.
 *
 * Assembled by the client from `GET /path` and `GET /project/current`. There is
 * no `/app` endpoint — an early version of this client assumed one, and because
 * the server answers unknown paths with its web UI rather than a 404, the
 * mistake surfaced as a blank working directory rather than as an error.
 */
export interface AppInfo {
  hostname?: string
  /** True when the server's directory is a git worktree (`vcs === "git"`). */
  git?: boolean
  /** The server user's home directory, for collapsing paths to `~`. */
  home?: string
  path?: {
    /** Repository / worktree root. Absent on non-repo directories. */
    root?: string
    /** Directory the server was started in. */
    cwd?: string
    config?: string
    data?: string
    state?: string
  }
  version?: string
}

/** `GET /project` — a directory the server knows about. */
export interface Project {
  id: string
  /** Absolute path to the project directory. */
  worktree: string
  /** Present when the directory is a git repository. */
  vcs?: "git" | null
  time?: { created?: number; initialized?: number }
}

/** A project decorated with everything the Projects screen renders. */
export interface ProjectSummary extends Project {
  /** Last path segment of `worktree`, used as the display name. */
  name: string
  /** `worktree` with the user's home collapsed to `~`. */
  displayPath: string
  /** Two-letter monogram for the card tile. */
  initials: string
  isGit: boolean
  branch: string | null
  sessionCount: number
  lastActivity: number | null
}

/** `GET /session` — an agent conversation rooted at a directory. */
export interface Session {
  id: string
  projectID?: string
  directory?: string
  parentID?: string
  title?: string
  version?: string
  time: { created: number; updated: number }
  /** The agent this session runs under, on builds that report it. */
  agent?: string
  /** The model this session runs under, on builds that report it. */
  model?: {
    id?: string
    modelID?: string
    providerID?: string
    provider?: string
    variant?: string
  }
  /** Present while the assistant is producing a turn. */
  revert?: unknown
}

export type MessageRole = "user" | "assistant"

export interface MessageInfo {
  id: string
  sessionID: string
  role: MessageRole
  time: { created: number; completed?: number }
  /** Assistant turns carry model and token accounting. */
  modelID?: string
  providerID?: string
  tokens?: {
    input?: number
    output?: number
    reasoning?: number
    cache?: { read?: number; write?: number }
  }
  cost?: number
  error?: { name?: string; data?: { message?: string } }
}

export type PartType =
  | "text"
  | "reasoning"
  | "tool"
  | "file"
  | "step-start"
  | "step-finish"
  | "snapshot"
  | "patch"
  | "agent"

export type ToolState =
  | { status: "pending" }
  | { status: "running"; title?: string; input?: Record<string, unknown>; time?: { start: number } }
  | {
      status: "completed"
      title?: string
      input?: Record<string, unknown>
      output?: string
      metadata?: Record<string, unknown>
      time?: { start: number; end: number }
    }
  | {
      status: "error"
      error: string
      input?: Record<string, unknown>
      time?: { start: number; end: number }
    }

export interface Part {
  id: string
  messageID: string
  sessionID: string
  type: PartType
  /** `text` and `reasoning` parts. */
  text?: string
  /** `tool` parts. */
  tool?: string
  callID?: string
  state?: ToolState
  /** `file` parts. */
  filename?: string
  mime?: string
  url?: string
  /** Set on text parts the server streamed but has not finalised. */
  synthetic?: boolean
}

/** A message and its parts, which is how every screen wants to consume it. */
export interface MessageWithParts {
  info: MessageInfo
  parts: Part[]
}

/** `GET /file` — a directory listing entry or a read result. */
export interface FileNode {
  name: string
  path: string
  type: "file" | "directory"
  /** Git working-tree state, when the server reports it. */
  status?: FileChangeStatus
  size?: number
}

/** `GET /api/fs/list` — one entry in the modern directory listing. */
export interface FsEntry {
  path: string
  type: "file" | "directory"
}

export type FileChangeStatus = "added" | "modified" | "deleted" | "untracked"

/** `GET /file/content` — the body of one file. */
export interface FileContent {
  /** `raw` for a clean file, `patch` when the server returns a diff instead. */
  type: "raw" | "patch"
  content: string
}

/** `GET /file/status` — the working tree, as the server sees it. */
export interface FileStatus {
  path: string
  status: FileChangeStatus
  added?: number
  removed?: number
  /** Present on servers that distinguish index from worktree. */
  staged?: boolean
}

/** Everything the Git screens need, assembled by `GitService`. */
export interface GitStatus {
  isRepo: boolean
  branch: string | null
  upstream: string | null
  ahead: number
  behind: number
  staged: FileStatus[]
  changed: FileStatus[]
  untracked: FileStatus[]
}

export interface GitCommit {
  hash: string
  shortHash: string
  subject: string
  author: string
  date: number
  refs: string[]
}

/** One file touched by a commit, as `git show --name-status --numstat` reports it. */
export interface GitCommitFile {
  path: string
  status: FileChangeStatus
  added: number
  removed: number
}

export interface GitCommitDetail extends GitCommit {
  files: GitCommitFile[]
}

export interface GitBranch {
  name: string
  current: boolean
  remote: boolean
  upstream: string | null
  lastCommit: string | null
}

/** One `@@` block of a unified diff. */
export interface DiffHunk {
  header: string
  lines: DiffLine[]
}

export interface DiffLine {
  kind: "context" | "add" | "del"
  text: string
  oldNumber: number | null
  newNumber: number | null
}

export interface FileDiff {
  path: string
  hunks: DiffHunk[]
  added: number
  removed: number
}

/** `GET /vcs` — branch, upstream and ahead/behind, in one call. */
export interface VcsInfo {
  branch?: string | null
  default_branch?: string | null
  ahead?: number
  behind?: number
}

/** `GET /vcs/status` — one changed file, as the VCS service reports it. */
export interface VcsFileStatus {
  file: string
  additions: number
  deletions: number
  status: "added" | "deleted" | "modified"
}

/** `GET /vcs/diff` — one changed file and its unified-diff patch. */
export interface VcsDiffFile {
  file: string
  patch: string
  additions: number
  deletions: number
  status: "added" | "deleted" | "modified"
}

/** `POST /vcs/commit` — the server's answer to "did the commit land". */
export interface VcsCommitResult {
  committed: boolean
  hash?: string
  message?: string
}

/** `POST /vcs/push` — the server's answer to "did the push land". */
export interface VcsPushResult {
  pushed: boolean
  message?: string
}

/** `GET /event` — the server's SSE stream. */
export interface ServerEvent {
  type: string
  id?: string
  directory?: string
  sessionID?: string
  /**
   * The event payload. Modern builds deliver it under `data` (with `sessionID`
   * at the top level); older builds used `properties`. Consumers read both.
   */
  data?: Record<string, unknown>
  properties?: Record<string, unknown>
}

/** `GET /api/agent` — one agent the session can run under. */
export interface AgentInfo {
  id: string
  /** Older builds call it `name` instead of `id`. */
  name?: string
  description?: string
  /** `primary` agents can be run directly; `subagent` cannot. */
  mode?: string
  hidden?: boolean
}

/** `GET /api/model` — one model the session can run. */
export interface ModelInfo {
  id: string
  providerID: string
  name?: string
  family?: string
  /** The model's named variants, e.g. a "thinking" mode. */
  variants?: string[]
  enabled?: boolean
  status?: string
}

/** What a session is running under, mirroring the server's `Model.Ref`. */
export interface ModelRef {
  providerID: string
  modelID: string
  variant?: string
}

/** A saved connection target. Passwords are held only for the active session. */
export interface ServerCredentials {
  url: string
  useBasicAuth: boolean
  username: string
  password: string
  /**
   * Route requests through this app's own `/proxy/…` function instead of
   * calling the server directly. Needed when the server sits behind a reverse
   * proxy that strips CORS headers or rejects preflights — the browser then
   * only ever makes same-origin calls.
   */
  proxy?: boolean
  /**
   * Keep this server — password included — in localStorage so the app attaches
   * again without the form. Opt-in per server, because it outlives the tab.
   */
  remember?: boolean
}

export interface RecentServer {
  url: string
  username: string | null
  useBasicAuth: boolean
  proxy?: boolean
  lastConnected: number
  /** Working directory reported by the server the last time we reached it. */
  lastDirectory: string | null
}
