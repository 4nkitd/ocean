/**
 * Shapes returned by the opencode v2 server's HTTP API (`/api/…`).
 *
 * These are hand-written rather than generated: the wire shapes are wider than
 * what the screens need, so the client narrows them here once and every screen
 * reads the same normalised types.
 */

/**
 * Where the server is rooted, what it is running, and whether it is a
 * repository.
 *
 * Assembled by the client from `GET /api/health`, `GET /api/location`,
 * `GET /api/project/current` and `GET /api/config` — no single endpoint
 * carries all of it.
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

/** `GET /api/project` — a directory the server knows about. */
export interface Project {
  id: string
  /** Absolute path to the project directory (v2 calls it `canonical`). */
  worktree: string
  /** Present when the directory is a git repository. */
  vcs?: "git" | null
  time?: { created?: number; initialized?: number }
  /** Extra worktrees / sandboxes v2 associates with the project. */
  directories?: string[]
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

/** `GET /api/session` — an agent conversation rooted at a directory. */
export interface Session {
  id: string
  projectID?: string
  directory?: string
  parentID?: string
  title?: string
  version?: string
  time: { created: number; updated: number }
  /** The agent this session runs under. */
  agent?: string
  /** The model this session runs under. */
  model?: {
    id?: string
    modelID?: string
    providerID?: string
    provider?: string
    variant?: string
  }
  cost?: number
  tokens?: TokenUsage
  /** Present when a revert is staged on the session. */
  revert?: unknown
}

export interface TokenUsage {
  input?: number
  output?: number
  reasoning?: number
  cache?: { read?: number; write?: number }
}

/**
 * `system` covers every v2 message type that is neither a user prompt nor an
 * assistant turn — synthetic notes, skill activations, compactions and the
 * agent / model / location switches the server records inline.
 */
export type MessageRole = "user" | "assistant" | "system"

export interface MessageInfo {
  id: string
  sessionID: string
  role: MessageRole
  /** The raw v2 message type, for screens that label system notes. */
  kind?: string
  time: { created: number; completed?: number }
  /** Assistant turns carry the agent, model and token accounting. */
  agent?: string
  modelID?: string
  providerID?: string
  variant?: string
  tokens?: TokenUsage
  cost?: number
  finish?: string
  error?: { name?: string; data?: { message?: string } }
}

export type PartType = "text" | "reasoning" | "tool" | "file"

export type ToolState =
  | { status: "pending" }
  | {
      status: "streaming"
      title?: string
      /** Partial JSON the model is still emitting. */
      inputText?: string
      time?: { start: number }
    }
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
      title?: string
      input?: Record<string, unknown>
      metadata?: Record<string, unknown>
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
  /** Position of the part inside its message, which is how v2 keys deltas. */
  ordinal?: number
  /** Set on parts the server is still streaming. */
  synthetic?: boolean
}

/**
 * An image the user attached to a prompt, held as a `data:` URL.
 *
 * The server takes the bytes inline on the prompt body rather than through a
 * separate upload, so there is nothing to clean up if the send fails.
 */
export interface PromptAttachment {
  /** Client-side only, for keying the thumbnail list and removal. */
  id: string
  mime: string
  filename: string
  url: string
}

/** A message and its parts, which is how every screen wants to consume it. */
export interface MessageWithParts {
  info: MessageInfo
  parts: Part[]
}

/** One entry of a directory listing, with an absolute `path`. */
export interface FileNode {
  name: string
  path: string
  type: "file" | "directory"
  /** Git working-tree state, when the server reports it. */
  status?: FileChangeStatus
  size?: number
}

/**
 * What `GET /api/vcs/status` can say about a file. There is no untracked
 * marker: a file git has never seen is reported as `added`, same as a staged
 * new file, and no endpoint distinguishes the index from the worktree.
 */
export type FileChangeStatus = "added" | "modified" | "deleted"

/** `GET /api/fs/read/*` — the body of one file. */
export interface FileContent {
  content: string
}

/** The working tree, as `GET /api/vcs/status` sees it. Paths are repo-relative. */
export interface FileStatus {
  path: string
  status: FileChangeStatus
  added?: number
  removed?: number
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

/**
 * `GET /api/vcs` gives the branch; ahead/behind come from `git rev-list`
 * through the shell endpoint, since v2 has no upstream-tracking route.
 */
export interface VcsInfo {
  branch?: string | null
  default_branch?: string | null
  ahead?: number
  behind?: number
}

/** `GET /api/vcs/status` — one changed file, as the VCS service reports it. */
export interface VcsFileStatus {
  file: string
  additions: number
  deletions: number
  status: "added" | "deleted" | "modified"
}

/** `GET /api/vcs/diff` — one changed file and its unified-diff patch. */
export interface VcsDiffFile {
  file: string
  patch: string
  additions: number
  deletions: number
  status: "added" | "deleted" | "modified"
}

/** What the working tree is diffed against. */
export type VcsDiffMode = "working" | "branch"

/** The result of `git commit`, run through `POST /api/shell`. */
export interface VcsCommitResult {
  committed: boolean
  hash?: string
  message?: string
}

/** The result of `git push`, run through `POST /api/shell`. */
export interface VcsPushResult {
  pushed: boolean
  message?: string
}

/** `POST /api/shell` — one command the server ran on our behalf. */
export interface ShellResult {
  output: string
  exit: number | null
  status: "running" | "exited" | "timeout" | "killed"
}

/** `GET /api/shell/{id}` — where a started command has got to. */
export interface ShellCommand {
  id: string
  status: "running" | "exited" | "timeout" | "killed"
  exit: number | null
}

/** `GET /api/shell/{id}/output` — one page of the captured combined output. */
export interface ShellChunk {
  output: string
  /** Absolute byte offset to resume from on the next read. */
  cursor: number
  /** Bytes were dropped before this page because the capture wrapped. */
  truncated: boolean
}

/** `GET /api/event` — one frame of the server's SSE stream. */
export interface ServerEvent {
  type: string
  id?: string
  /** From the event's `location`, so screens can ignore other directories. */
  directory?: string
  sessionID?: string
  data: Record<string, unknown>
}

/** `GET /api/command` — a saved prompt template the session can run. */
export interface CommandInfo {
  name: string
  description?: string
  /** The prompt it expands to; `$ARGUMENTS` is where the rest of the line goes. */
  template: string
  agent?: string
  subtask?: boolean
}

/** `GET /api/session/{id}/inbox` — a prompt admitted but not yet delivered. */
export interface InboxItem {
  id: string
  sessionID: string
  timeCreated: number
  type: string
  text: string
  /** `queue` runs after the current turn; `steer` cuts into it. */
  delivery: InboxDelivery
  attachments: number
}

export type InboxDelivery = "steer" | "queue"

/**
 * `permission.asked` / `GET /api/session/{id}/permission` — the agent is
 * blocked until this is answered.
 */
export interface PermissionRequest {
  id: string
  sessionID: string
  /** What it wants to do: `edit`, `bash`, `webfetch`, `external_directory`… */
  action: string
  /** What it wants to do it to — a path, a command, a URL. */
  resources: string[]
  /** The patterns an `always` answer would save. */
  save?: string[]
  metadata?: Record<string, unknown>
  /** The tool call that raised it, for pointing at the right turn. */
  source?: { type: string; messageID: string; id: string }
}

export type PermissionReply = "once" | "always" | "reject"

/** `GET /api/agent` — one agent the session can run under. */
export interface AgentInfo {
  id: string
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

/**
 * One MCP server the opencode process knows about.
 *
 * `GET /api/mcp` returns `{name, status: {status}}` entries; this narrows them,
 * because every screen wants a flat list. `failed` carries the reason — it is a
 * server the user meant to run, so the error is the whole story.
 */
export interface McpServer {
  name: string
  status: "connected" | "disabled" | "failed"
  error?: string
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
