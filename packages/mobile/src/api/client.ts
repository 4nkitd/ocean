import { ApiError } from "./errors"
import type {
  AgentInfo,
  AppInfo,
  CommandInfo,
  FileContent,
  FileNode,
  FileChangeStatus,
  FileStatus,
  GitCommit,
  GitCommitDetail,
  GitCommitFile,
  InboxDelivery,
  InboxItem,
  McpServer,
  MessageInfo,
  MessageWithParts,
  ModelInfo,
  ModelRef,
  Part,
  PermissionReply,
  PermissionRequest,
  Project,
  PromptAttachment,
  ServerCredentials,
  ServerEvent,
  Session,
  ShellChunk,
  ShellCommand,
  ShellResult,
  ToolState,
  VcsCommitResult,
  VcsDiffFile,
  VcsDiffMode,
  VcsFileStatus,
  VcsInfo,
  VcsPushResult,
} from "./types"

const DEFAULT_TIMEOUT_MS = 15_000
/** Every v2 route lives under this prefix; anything else is the server's own UI. */
const API_PREFIX = "/api"

/**
 * Talks to one `opencode serve` (v2) process over HTTP.
 *
 * Two things shape this class:
 *
 * 1. The server is on the user's own network, addressed by an arbitrary URL, so
 *    every request can fail in ways a same-origin app never sees — CORS blocks,
 *    self-signed TLS, a tunnel that dropped. `request` normalises all of those
 *    into `ApiError` with a `kind` the UI can branch on.
 *
 * 2. v2 answers location-scoped routes with a `{location, data}` envelope and
 *    session routes with `{data}`. Unwrapping happens here so no screen sees an
 *    envelope, and paths cross the boundary absolute even though v2 speaks in
 *    paths relative to the directory.
 */
export class OpenCodeClient {
  readonly baseUrl: string
  /** The address the user recognises, shown in headers and the recents list. */
  readonly displayHost: string
  private readonly authHeader: string | null

  constructor(credentials: ServerCredentials) {
    const target = normaliseBaseUrl(credentials.url)
    if (credentials.proxy) {
      // Same-origin relay: /proxy/<encoded target>/<original path>. The browser
      // only ever talks to this app's origin, which is the only way to reach a
      // v2 server from a deployed build — v2 allows CORS for localhost and
      // *.opencode.ai and nothing else.
      this.baseUrl = `${location.origin}/proxy/${encodeURIComponent(target)}`
    } else {
      this.baseUrl = target
    }
    this.displayHost = hostOf(target)
    this.authHeader =
      credentials.useBasicAuth && credentials.username
        ? `Basic ${base64(`${credentials.username}:${credentials.password}`)}`
        : null
  }

  // ── core transport ──────────────────────────────────────────────────────

  private headers(extra?: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = { Accept: "application/json", ...extra }
    if (this.authHeader) headers.Authorization = this.authHeader
    return headers
  }

  private url(path: string, query?: Query): string {
    const url = new URL(this.baseUrl + API_PREFIX + path)
    for (const [key, value] of Object.entries(query ?? {})) {
      if (value !== undefined && value !== null && value !== "")
        url.searchParams.set(key, String(value))
    }
    return url.toString()
  }

  async request<T>(
    path: string,
    options: {
      method?: string
      query?: Query
      body?: unknown
      signal?: AbortSignal
      timeoutMs?: number
      /** Return null on 404 instead of throwing — for optional endpoints. */
      optional?: boolean
    } = {},
  ): Promise<T> {
    const {
      method = "GET",
      query,
      body,
      signal,
      timeoutMs = DEFAULT_TIMEOUT_MS,
      optional = false,
    } = options
    const url = this.url(path, query)

    // Compose the caller's signal with our own timeout so either can cancel.
    const timeoutController = new AbortController()
    const timer = setTimeout(() => timeoutController.abort(), timeoutMs)
    const signals = signal ? [signal, timeoutController.signal] : [timeoutController.signal]
    const composed = anySignal(signals)

    let response: Response
    try {
      response = await fetch(url, {
        method,
        headers: this.headers(
          body !== undefined ? { "Content-Type": "application/json" } : undefined,
        ),
        body: body !== undefined ? JSON.stringify(body) : undefined,
        signal: composed,
        mode: "cors",
        credentials: "omit",
      })
    } catch (cause) {
      // fetch rejects for network failure and for abort; the caller's signal
      // firing means "cancelled", ours means "timed out", and neither is a
      // server error the user should see as one.
      if (signal?.aborted) throw new ApiError("aborted", "Request cancelled", null, url)
      if (timeoutController.signal.aborted)
        throw new ApiError("timeout", "Request timed out", null, url)
      throw new ApiError(
        "network",
        cause instanceof Error ? cause.message : "Network request failed",
        null,
        url,
      )
    } finally {
      clearTimeout(timer)
    }

    if (response.status === 401 || response.status === 403) {
      throw new ApiError("auth", "Authentication failed", response.status, url)
    }
    if (response.status === 404) {
      if (optional) return null as T
      throw new ApiError("notfound", `Not found: ${path}`, 404, url)
    }
    if (!response.ok) {
      throw new ApiError("server", await errorBody(response), response.status, url)
    }

    if (response.status === 204) return null as T

    /*
     * A v2 server serves its own web UI from the same origin, with a catch-all
     * that answers any non-`/api` path with 200 and the SPA's index.html rather
     * than a 404. Reaching that page means we asked a v1 server (or a proxy in
     * front of one) for a v2 route, and saying so beats handing a screen a page
     * of HTML where it expected an object.
     */
    const contentType = response.headers.get("content-type") ?? ""
    if (contentType.includes("text/html")) {
      if (optional) return null as T
      throw new ApiError("notfound", `No v2 API at ${path} — the server answered with a web UI`, 404, url)
    }

    const text = await response.text()
    if (!text) return null as T
    try {
      return JSON.parse(text) as T
    } catch {
      // File bodies come back as text/plain.
      if (contentType.includes("application/json")) {
        throw new ApiError("parse", `Malformed JSON from ${path}`, response.status, url)
      }
      return text as unknown as T
    }
  }

  /** A request whose payload is wrapped in v2's `{data}` / `{location, data}` envelope. */
  private async data<T>(
    path: string,
    options: Parameters<OpenCodeClient["request"]>[1] = {},
  ): Promise<T | null> {
    const result = await this.request<{ data?: T } | null>(path, options)
    if (result === null || result === undefined) return null
    return (result.data ?? null) as T | null
  }

  // ── connection ──────────────────────────────────────────────────────────

  /**
   * Confirm the server is reachable, the credentials work, and report what it
   * is and where it is rooted. This is the handshake screen's whole job.
   *
   * `/api/health` is the reachability and version check, `/api/location` says
   * where the server is rooted, `/api/project/current` carries `vcs` (the only
   * authoritative answer to "is this a repository", which gates the Git tab),
   * and `/api/config` is mined for the server user's home so paths can be shown
   * as `~/dev/x`. Only health is required; the rest are allowed to fail on a
   * server started outside any project.
   */
  async getAppInfo(signal?: AbortSignal): Promise<AppInfo> {
    const health = await this.request<{ healthy?: boolean; version?: string }>("/health", {
      signal,
      timeoutMs: 8_000,
    })

    const [location, projects, config] = await Promise.all([
      this.request<{ directory?: string; project?: { directory?: string; canonical?: string } }>(
        "/location",
        { signal, optional: true, timeoutMs: 8_000 },
      ).catch(() => null),
      this.request<RawProject[]>("/project", { signal, optional: true, timeoutMs: 8_000 }).catch(
        () => null,
      ),
      this.data<ConfigEntry[]>("/config", { signal, optional: true, timeoutMs: 8_000 }).catch(
        () => null,
      ),
    ])

    const cwd = location?.directory
    // `/api/project/current` does not report `vcs`; the project list does, so
    // the entry that owns this directory is the authoritative "is a repo".
    const owning = (projects ?? []).find(
      (project) =>
        project.canonical === cwd || (project.sandboxes ?? []).includes(cwd ?? ""),
    )
    return {
      git: owning?.vcs === "git",
      home: homeFromConfig(config, cwd),
      path: {
        root: owning?.canonical ?? location?.project?.canonical ?? cwd,
        cwd,
        config: config?.find((entry) => entry.type === "document")?.path,
      },
      version: health?.version,
    }
  }

  // ── shell ───────────────────────────────────────────────────────────────

  /**
   * Run one command on the server and hand back its output.
   *
   * v2 has a first-class shell endpoint that is not attached to a session, so
   * nothing lands in a conversation the user is reading. The command is started,
   * polled until it leaves `running`, then its output is read and the record is
   * removed.
   */
  async runShell(
    directory: string,
    command: string,
    options: { timeoutMs?: number; signal?: AbortSignal } = {},
  ): Promise<ShellResult> {
    const timeoutMs = options.timeoutMs ?? 60_000
    const signal = options.signal
    const query = at(directory)

    const started = await this.data<ShellInfo>("/shell", {
      method: "POST",
      query,
      body: { command, cwd: directory, timeout: timeoutMs },
      signal,
    })
    if (!started?.id) throw new ApiError("server", "The server did not start the command")

    const id = encodeURIComponent(started.id)
    let info = started
    const deadline = Date.now() + timeoutMs
    try {
      while (info.status === "running" && Date.now() < deadline) {
        if (!(await sleep(150, signal))) throw new ApiError("aborted", "Request cancelled")
        info = (await this.data<ShellInfo>(`/shell/${id}`, { query, signal })) ?? info
      }
      const output = await this.data<{ output?: string }>(`/shell/${id}/output`, { query, signal })
      return { output: output?.output ?? "", exit: info.exit ?? null, status: info.status }
    } finally {
      void this.request(`/shell/${id}`, { method: "DELETE", query, optional: true }).catch(
        () => undefined,
      )
    }
  }

  /**
   * Start a command and return straight away.
   *
   * `runShell` above is the right shape for the one-shot commands the Git
   * screens run. A terminal is the other shape: the caller wants the output as
   * it is printed, so it owns the record instead — poll `getShell`, page the
   * output with `readShellOutput`, and `removeShell` when finished.
   */
  async startShell(
    directory: string,
    command: string,
    options: { cwd?: string; timeoutMs?: number; signal?: AbortSignal } = {},
  ): Promise<ShellCommand> {
    const started = await this.data<ShellInfo>("/shell", {
      method: "POST",
      query: at(directory),
      body: {
        command,
        cwd: options.cwd || directory,
        timeout: options.timeoutMs ?? 600_000,
      },
      signal: options.signal,
    })
    if (!started?.id) throw new ApiError("server", "The server did not start the command")
    return { id: started.id, status: started.status, exit: started.exit ?? null }
  }

  /** Status and exit code of a started command. */
  async getShell(
    directory: string,
    id: string,
    signal?: AbortSignal,
  ): Promise<ShellCommand | null> {
    const info = await this.data<ShellInfo>(`/shell/${encodeURIComponent(id)}`, {
      query: at(directory),
      signal,
      optional: true,
    })
    if (!info) return null
    return { id: info.id ?? id, status: info.status, exit: info.exit ?? null }
  }

  /**
   * The next page of combined output. `cursor` is an absolute byte offset, so
   * handing back the one from the previous page streams a running command
   * without re-reading what has already been printed.
   */
  async readShellOutput(
    directory: string,
    id: string,
    cursor = 0,
    signal?: AbortSignal,
  ): Promise<ShellChunk> {
    const page = await this.data<{ output?: string; cursor?: number; truncated?: boolean }>(
      `/shell/${encodeURIComponent(id)}/output`,
      { query: { ...at(directory), cursor }, signal },
    )
    const output = page?.output ?? ""
    // The server reports where it left off, but only its own cursor advances
    // the read — if it echoes the request back, count the bytes ourselves so
    // the next page cannot repeat this one forever.
    const reported = Number(page?.cursor)
    const nextCursor =
      Number.isFinite(reported) && reported > cursor
        ? reported
        : cursor + new TextEncoder().encode(output).length
    return { output, cursor: nextCursor, truncated: page?.truncated === true }
  }

  /** Drop the record, killing the process if it is still running. */
  async removeShell(directory: string, id: string): Promise<void> {
    await this.request(`/shell/${encodeURIComponent(id)}`, {
      method: "DELETE",
      query: at(directory),
      optional: true,
    }).catch(() => undefined)
  }

  // ── vcs ─────────────────────────────────────────────────────────────────

  /** Branch, plus ahead/behind counted against the upstream when there is one. */
  async getVcsInfo(directory: string, signal?: AbortSignal): Promise<VcsInfo | null> {
    const info = await this.data<{ branch?: { current?: string; default?: string } }>("/vcs", {
      query: at(directory),
      signal,
      optional: true,
    })
    if (!info) return null

    const tracking = await this.runShell(
      directory,
      "git rev-list --left-right --count @{u}...HEAD 2>/dev/null || true",
      { timeoutMs: 15_000, signal },
    ).catch(() => null)
    const [behind, ahead] = (tracking?.output ?? "").trim().split(/\s+/).map(Number)

    return {
      branch: info.branch?.current ?? null,
      default_branch: info.branch?.default ?? null,
      ahead: Number.isFinite(ahead) ? ahead : 0,
      behind: Number.isFinite(behind) ? behind : 0,
    }
  }

  /**
   * Just the current branch.
   *
   * `getVcsInfo` also counts ahead/behind, which costs a whole shell round trip;
   * a list of project cards only names the branch, and pays for one request.
   */
  async getVcsBranch(directory: string, signal?: AbortSignal): Promise<string | null> {
    const info = await this.data<{ branch?: { current?: string } }>("/vcs", {
      query: at(directory),
      signal,
      optional: true,
    })
    const branch = info?.branch?.current?.trim() ?? ""
    return branch && branch !== "HEAD" ? branch : null
  }

  /** Recent commits from `git log`, which is the only source with real depth. */
  async getVcsCommits(directory: string, limit = 20, signal?: AbortSignal): Promise<GitCommit[]> {
    const count = Math.max(1, Math.trunc(limit))
    const result = await this.runShell(
      directory,
      `git log --no-color --max-count=${count} --format=%H%x1f%an%x1f%at%x1f%s%x1f%D`,
      { timeoutMs: 30_000, signal },
    )
    return result.output
      .split("\n")
      .map((line) => line.split("\u001f"))
      .filter((fields) => fields.length >= 4 && /^[0-9a-f]{7,40}$/.test(fields[0] ?? ""))
      .map(([hash, author, seconds, subject, refs]) => ({
        hash: hash!,
        shortHash: hash!.slice(0, 7),
        subject: subject ?? "",
        author: author ?? "",
        date: Number(seconds) * 1_000,
        refs: (refs ?? "")
          .split(", ")
          .map((ref) => ref.trim())
          .filter(Boolean),
      }))
  }

  /** One commit, with the files it touched and their line counts. */
  async getCommitDetail(
    directory: string,
    hash: string,
    signal?: AbortSignal,
  ): Promise<GitCommitDetail | null> {
    if (!isCommitHash(hash)) return null
    const result = await this.runShell(
      directory,
      `git show --no-color --format=%H%x1f%an%x1f%at%x1f%s%x1f%D --name-status ${hash};` +
        ` printf '\\036';` +
        ` git show --no-color --format= --numstat ${hash}`,
      { timeoutMs: 30_000, signal },
    )
    return parseCommitDetail(result.output)
  }

  /** The patch for one file in one commit, ready for `parseUnifiedDiff`. */
  async getCommitFileDiff(
    directory: string,
    hash: string,
    path: string,
    signal?: AbortSignal,
  ): Promise<string> {
    if (!isCommitHash(hash)) return ""
    const result = await this.runShell(
      directory,
      `git show --no-color --format= ${hash} -- ${quoteShellArgument(path)}`,
      { timeoutMs: 30_000, signal },
    )
    return result.output
  }

  /** Working-tree changes, straight from the VCS API. */
  async getVcsStatus(directory: string, signal?: AbortSignal): Promise<VcsFileStatus[]> {
    const result = await this.data<VcsFileStatus[]>("/vcs/status", {
      query: at(directory),
      signal,
      optional: true,
    })
    return result ?? []
  }

  /** Per-file patches from the VCS API. */
  async getVcsDiff(
    directory: string,
    mode: VcsDiffMode = "working",
    signal?: AbortSignal,
  ): Promise<VcsDiffFile[]> {
    const result = await this.data<VcsDiffFile[]>("/vcs/diff", {
      query: { ...at(directory), mode },
      signal,
      optional: true,
    })
    return result ?? []
  }

  /**
   * Stage everything and commit it.
   *
   * v2's VCS API is read-only, so this is `git` through the shell endpoint. The
   * commit stages tracked *and* untracked files first, which is what the Git
   * screen's "commit all" affordance has always meant.
   */
  async commitVcs(
    directory: string,
    message: string,
    signal?: AbortSignal,
  ): Promise<VcsCommitResult> {
    const staged = await this.runShell(directory, "git add -A", { timeoutMs: 60_000, signal })
    if (staged.exit !== 0) {
      return { committed: false, message: firstLine(staged.output) || "git add failed" }
    }

    const result = await this.runShell(
      directory,
      `git commit -m ${quoteShellArgument(message)} && git rev-parse HEAD`,
      { timeoutMs: 60_000, signal },
    )
    if (result.exit !== 0) {
      return { committed: false, message: lastLine(result.output) || "git commit failed" }
    }
    const hash = result.output.trim().split("\n").pop()?.trim()
    return {
      committed: true,
      hash: hash && isCommitHash(hash) ? hash : undefined,
      message: firstLine(result.output),
    }
  }

  async pushVcs(directory: string, signal?: AbortSignal): Promise<VcsPushResult> {
    const result = await this.runShell(directory, "git push 2>&1", { timeoutMs: 120_000, signal })
    return {
      pushed: result.exit === 0,
      message: lastLine(result.output) || (result.exit === 0 ? "Pushed" : "git push failed"),
    }
  }

  // ── projects ────────────────────────────────────────────────────────────

  async listProjects(signal?: AbortSignal): Promise<Project[]> {
    const result = await this.request<RawProject[]>("/project", { signal, optional: true })
    return (result ?? [])
      .map(toProject)
      // v2 keeps a `global` project for anything outside a known root. It is
      // only noise when it has no real directory behind it — when it does, it
      // is the directory the server was started in and belongs on the screen.
      .filter((project) => project.worktree && project.worktree !== "/")
  }

  async getCurrentProject(directory?: string, signal?: AbortSignal): Promise<Project | null> {
    const result = await this.request<RawProject>("/project/current", {
      query: at(directory),
      signal,
      optional: true,
    })
    return result ? toProject(result) : null
  }

  // ── sessions ────────────────────────────────────────────────────────────

  /** Subagent sessions are filtered here so no caller can forget. */
  async listSessions(directory?: string, signal?: AbortSignal): Promise<Session[]> {
    const result = await this.data<RawSession[]>("/session", {
      query: { directory, limit: 200, order: "desc" },
      signal,
    })
    return (result ?? []).map(toSession).filter((session) => !isHiddenSession(session))
  }

  /** One session, including the agent and model it currently runs under. */
  async getSession(
    sessionId: string,
    _directory?: string,
    signal?: AbortSignal,
  ): Promise<Session | null> {
    const result = await this.data<RawSession>(`/session/${encodeURIComponent(sessionId)}`, {
      signal,
      optional: true,
    })
    return result ? toSession(result) : null
  }

  /** Which sessions are mid-turn right now, keyed by id. */
  async getSessionStatuses(
    _directory?: string,
    signal?: AbortSignal,
  ): Promise<Record<string, { type?: string }> | null> {
    const result = await this.data<Record<string, { type?: string } | string>>("/session/active", {
      signal,
      optional: true,
    })
    if (!result) return null
    return Object.fromEntries(
      Object.entries(result).map(([id, status]) => [
        id,
        typeof status === "string" ? { type: status } : { type: status?.type ?? "busy" },
      ]),
    )
  }

  /**
   * Every session working right now, across every project on this server.
   *
   * `/api/session/active` answers with ids and nothing else, so each one is
   * resolved to a real session — the screen has to name the project and the
   * conversation, not an id. A session that has since gone away is dropped
   * rather than shown as a blank row.
   */
  async listActiveSessions(signal?: AbortSignal): Promise<Session[]> {
    const statuses = await this.getSessionStatuses(undefined, signal)
    const ids = Object.entries(statuses ?? {})
      .filter(([, status]) => status.type && status.type !== "idle")
      .map(([id]) => id)
    if (ids.length === 0) return []

    const sessions = await Promise.all(
      ids.map((id) => this.getSession(id, undefined, signal).catch(() => null)),
    )
    return sessions.filter((session): session is Session => session !== null)
  }

  /** Every request waiting on a human, across the sessions this server runs. */
  async listPendingPermissions(
    directory?: string,
    signal?: AbortSignal,
  ): Promise<PermissionRequest[]> {
    const result = await this.data<PermissionRequest[]>("/permission/request", {
      query: at(directory),
      signal,
      optional: true,
    })
    return result ?? []
  }

  async createSession(directory?: string, title?: string, signal?: AbortSignal): Promise<Session> {
    const result = await this.data<RawSession>("/session", {
      method: "POST",
      body: { title, ...(directory ? { location: { directory } } : {}) },
      signal,
    })
    if (!result) throw new ApiError("server", "The server did not return the new session")
    return toSession(result)
  }

  async deleteSession(id: string, _directory?: string, signal?: AbortSignal): Promise<void> {
    await this.request<void>(`/session/${encodeURIComponent(id)}`, { method: "DELETE", signal })
  }

  async listMessages(
    sessionId: string,
    _directory?: string,
    signal?: AbortSignal,
  ): Promise<MessageWithParts[]> {
    const result = await this.data<RawMessage[]>(
      `/session/${encodeURIComponent(sessionId)}/message`,
      { query: { order: "asc", limit: 200 }, signal },
    )
    return (result ?? []).map((message) => toMessage(message, sessionId))
  }

  async getMessage(
    sessionId: string,
    messageId: string,
    signal?: AbortSignal,
  ): Promise<MessageWithParts | null> {
    const result = await this.data<RawMessage>(
      `/session/${encodeURIComponent(sessionId)}/message/${encodeURIComponent(messageId)}`,
      { signal, optional: true },
    )
    return result ? toMessage(result, sessionId) : null
  }

  /**
   * Admit a prompt. The reply is the inbox record, not the answer — assistant
   * output arrives on the SSE stream.
   */
  async sendPrompt(
    sessionId: string,
    text: string,
    options: {
      directory?: string
      providerID?: string
      modelID?: string
      variant?: string
      agent?: string
      attachments?: PromptAttachment[]
      /**
       * How to deliver it when the session is mid-turn. `queue` waits for the
       * turn to end, `steer` cuts into it. Omitted for an idle session, which
       * runs the prompt immediately.
       */
      delivery?: InboxDelivery
      signal?: AbortSignal
    } = {},
  ): Promise<void> {
    const encoded = encodeURIComponent(sessionId)

    // v2 sets the agent and model on the session, not on the prompt. Skipped
    // for a queued prompt: the running turn owns the session's settings until
    // it ends, and changing them underneath it would apply to the wrong turn.
    if (!options.delivery) {
      if (options.agent) await this.switchAgent(sessionId, options.agent)
      if (options.providerID && options.modelID) {
        await this.switchModel(sessionId, {
          providerID: options.providerID,
          modelID: options.modelID,
          variant: options.variant,
        })
      }
    }

    await this.request(`/session/${encoded}/prompt`, {
      method: "POST",
      body: {
        text,
        ...(options.delivery ? { delivery: options.delivery } : {}),
        // The bytes ride along as a data URL — there is no upload step.
        ...(options.attachments?.length
          ? {
              files: options.attachments.map((attachment) => ({
                uri: attachment.url,
                name: attachment.filename,
              })),
            }
          : {}),
      },
      signal: options.signal,
      timeoutMs: 60_000,
    })
  }

  // ── commands ────────────────────────────────────────────────────────────

  /** The saved prompts this project can run, which is what `/` offers. */
  async listCommands(directory?: string, signal?: AbortSignal): Promise<CommandInfo[]> {
    const result = await this.data<CommandInfo[]>("/command", {
      query: at(directory),
      signal,
      optional: true,
    })
    return (result ?? []).filter((command) => !!command.name)
  }

  /**
   * Run one. The server expands the template — `$ARGUMENTS` and all — so the
   * client sends the name and the rest of the line, never the expansion.
   */
  async runCommand(
    sessionId: string,
    command: string,
    args: string,
    options: { delivery?: InboxDelivery; signal?: AbortSignal } = {},
  ): Promise<void> {
    await this.request(`/session/${encodeURIComponent(sessionId)}/command`, {
      method: "POST",
      body: {
        command,
        ...(args ? { arguments: args } : {}),
        ...(options.delivery ? { delivery: options.delivery } : {}),
      },
      signal: options.signal,
      timeoutMs: 60_000,
    })
  }

  // ── inbox ───────────────────────────────────────────────────────────────

  /** Prompts admitted while the agent was busy, still waiting their turn. */
  async listInbox(sessionId: string, signal?: AbortSignal): Promise<InboxItem[]> {
    const result = await this.data<RawInboxItem[]>(
      `/session/${encodeURIComponent(sessionId)}/inbox`,
      { signal, optional: true },
    )
    return (result ?? []).map(toInboxItem)
  }

  /** Drop a queued prompt before it runs. */
  async cancelInbox(sessionId: string, inboxId: string): Promise<void> {
    await this.request(
      `/session/${encodeURIComponent(sessionId)}/inbox/${encodeURIComponent(inboxId)}`,
      { method: "DELETE" },
    )
  }

  /** Move a waiting prompt between "after this turn" and "cut in now". */
  async setInboxDelivery(
    sessionId: string,
    inboxId: string,
    delivery: InboxDelivery,
  ): Promise<void> {
    await this.request(
      `/session/${encodeURIComponent(sessionId)}/inbox/${encodeURIComponent(inboxId)}/${delivery}`,
      { method: "POST" },
    )
  }

  async abortSession(sessionId: string, _directory?: string): Promise<void> {
    await this.request<void>(`/session/${encodeURIComponent(sessionId)}/interrupt`, {
      method: "POST",
    })
  }

  // ── files ───────────────────────────────────────────────────────────────

  /**
   * One directory level. The tree screen expands lazily, one level per tap.
   *
   * v2 speaks in paths relative to the location, and answers a directory that
   * holds a single subdirectory with that whole run collapsed
   * (`packages/mobile/`). Paths are returned absolute so callers keep working
   * in one namespace.
   */
  async listDirectory(path: string, directory?: string, signal?: AbortSignal): Promise<FileNode[]> {
    const root = directory ?? path
    const result = await this.data<{ path: string; type: string }[]>("/fs/list", {
      query: { ...at(root), path: relativeTo(root, path) || "." },
      signal,
      optional: true,
    })
    return (result ?? []).map((entry) => {
      const trimmed = entry.path.replace(/\/+$/, "")
      return {
        name: trimmed.split("/").pop() ?? trimmed,
        path: absoluteIn(root, trimmed),
        type: entry.type === "directory" ? "directory" : "file",
      }
    })
  }

  async readFile(path: string, directory?: string, signal?: AbortSignal): Promise<FileContent> {
    const root = directory ?? ""
    const relative = relativeTo(root, path)
    const result = await this.request<string | { content?: string }>(
      `/fs/read/${relative.split("/").map(encodeURIComponent).join("/")}`,
      { query: at(root), signal },
    )
    if (typeof result === "string") return { content: result }
    return { content: result?.content ?? "" }
  }

  /** Working-tree changes, in the client's `FileStatus` shape (repo-relative). */
  async fileStatus(directory?: string, signal?: AbortSignal): Promise<FileStatus[]> {
    if (!directory) return []
    const status = await this.getVcsStatus(directory, signal)
    return status.map((entry) => ({
      path: entry.file,
      status: entry.status,
      added: entry.additions,
      removed: entry.deletions,
    }))
  }

  /** Fuzzy path search, backing the tree's filter field. */
  async findFiles(query: string, directory?: string, signal?: AbortSignal): Promise<string[]> {
    if (!directory || !query) return []
    const result = await this.data<{ path: string; type: string }[]>("/fs/find", {
      query: { ...at(directory), query, type: "file", limit: 100 },
      signal,
      optional: true,
    })
    return (result ?? []).map((entry) => absoluteIn(directory, entry.path))
  }

  // ── agents and models ────────────────────────────────────────────────────

  /** The agents this server can run a session under. */
  async listAgents(directory?: string, signal?: AbortSignal): Promise<AgentInfo[]> {
    const result = await this.data<RawAgent[]>("/agent", {
      query: at(directory),
      signal,
      optional: true,
    })
    return (result ?? [])
      .filter((agent) => !agent.hidden)
      .map((agent) => ({
        id: agent.id,
        name: agent.name ?? agent.id,
        description: agent.description,
        mode: agent.mode,
        hidden: agent.hidden ?? false,
      }))
  }

  /** The models this server can run. */
  async listModels(directory?: string, signal?: AbortSignal): Promise<ModelInfo[]> {
    const result = await this.data<RawModel[]>("/model", {
      query: at(directory),
      signal,
      optional: true,
    })
    return (result ?? [])
      .filter((model) => model.disabled !== true)
      .map((model) => ({
        id: model.modelID ?? model.id,
        providerID: model.providerID,
        name: model.name ?? model.modelID ?? model.id,
        family: model.family,
        variants: (model.variants ?? [])
          .map((variant) => (typeof variant === "string" ? variant : variant?.id))
          .filter((variant): variant is string => !!variant),
      }))
  }

  /**
   * What a prompt runs as when the session has not been told otherwise.
   *
   * A fresh v2 session carries no agent or model of its own — the server picks
   * at prompt time. The composer has to name something, and "whatever the
   * server would pick" is the only honest answer, so it is read rather than
   * guessed.
   */
  async getDefaults(
    directory?: string,
    signal?: AbortSignal,
  ): Promise<{ model: ModelRef | null; agent: string | null }> {
    const [model, agents] = await Promise.all([
      this.data<{ id?: string; modelID?: string; providerID?: string; variant?: string }>(
        "/model/default",
        { query: at(directory), signal, optional: true },
      ).catch(() => null),
      this.listAgents(directory, signal).catch(() => [] as AgentInfo[]),
    ])

    const modelID = model?.modelID ?? model?.id
    // Primary agents are the ones a session can actually run under; the server
    // lists them in its own order of preference, so the first is the default.
    const agent = agents.find((entry) => entry.mode === "primary") ?? agents[0]
    return {
      model:
        modelID && model?.providerID
          ? { providerID: model.providerID, modelID, variant: model.variant }
          : null,
      agent: agent?.id ?? null,
    }
  }

  /** Point a session at a different agent. */
  async switchAgent(sessionId: string, agent: string, _directory?: string): Promise<void> {
    await this.request(`/session/${encodeURIComponent(sessionId)}/agent`, {
      method: "POST",
      body: { agent },
    })
  }

  /** Point a session at a different model (and optional variant). */
  async switchModel(sessionId: string, model: ModelRef, _directory?: string): Promise<void> {
    await this.request(`/session/${encodeURIComponent(sessionId)}/model`, {
      method: "POST",
      body: {
        model: {
          id: model.modelID,
          providerID: model.providerID,
          ...(model.variant ? { variant: model.variant } : {}),
        },
      },
    })
  }

  // ── permissions ─────────────────────────────────────────────────────────

  /**
   * What this session is blocked on right now.
   *
   * Fetched on load as well as watched on the stream: a request raised before
   * the screen opened is exactly the case that leaves an agent stuck, so it has
   * to survive a reconnect rather than only arriving as an event.
   */
  async listPermissions(sessionId: string, signal?: AbortSignal): Promise<PermissionRequest[]> {
    const result = await this.data<PermissionRequest[]>(
      `/session/${encodeURIComponent(sessionId)}/permission`,
      { signal, optional: true },
    )
    return result ?? []
  }

  /** Answer one request. `always` saves the decision for the rest of the session. */
  async replyPermission(
    sessionId: string,
    requestId: string,
    reply: PermissionReply,
    message?: string,
  ): Promise<void> {
    await this.request(
      `/session/${encodeURIComponent(sessionId)}/permission/${encodeURIComponent(requestId)}/reply`,
      { method: "POST", body: { reply, ...(message ? { message } : {}) } },
    )
  }

  // ── mcp ─────────────────────────────────────────────────────────────────

  /**
   * The MCP servers this opencode process knows about, with their live state.
   *
   * `null` — not an empty list — when the endpoint is missing, so the UI can
   * say "this build cannot do it" rather than "none configured".
   */
  async listMcp(directory?: string, signal?: AbortSignal): Promise<McpServer[] | null> {
    const result = await this.data<RawMcp[]>("/mcp", {
      query: at(directory),
      signal,
      optional: true,
    })
    if (!result) return null
    return result
      .map((entry) => {
        const status = entry.status?.status
        return {
          name: entry.name,
          status: (status === "connected" || status === "failed"
            ? status
            : "disabled") as McpServer["status"],
          error: entry.status?.error,
        }
      })
      .sort((left, right) => left.name.localeCompare(right.name))
  }

  /**
   * Connect or disconnect one MCP server.
   *
   * This is the running process's state, not its config file — a disabled
   * server comes back on restart. The UI says so rather than implying it is
   * saved somewhere.
   */
  async setMcpEnabled(name: string, enabled: boolean, directory?: string): Promise<void> {
    const action = enabled ? "connect" : "disconnect"
    await this.request(`/mcp/${encodeURIComponent(name)}/${action}`, {
      method: "POST",
      query: at(directory),
      // Connecting a remote server can take a while to hand-shake.
      timeoutMs: 60_000,
    })
  }

  // ── events ──────────────────────────────────────────────────────────────

  /**
   * Subscribe to the server's SSE stream.
   *
   * `EventSource` cannot carry an Authorization header, so this reads the
   * stream over fetch and parses the wire format by hand. The v2 stream is
   * global — every location and session on the server — so events carry their
   * own `location` and consumers filter. Returns a function that closes it.
   */
  subscribe(handlers: {
    onEvent: (event: ServerEvent) => void
    onError?: (error: unknown) => void
    onOpen?: () => void
  }): () => void {
    const controller = new AbortController()
    let closed = false
    let retryDelay = 1_000

    const run = async () => {
      while (!closed) {
        try {
          const response = await fetch(this.url("/event"), {
            headers: this.headers({ Accept: "text/event-stream" }),
            signal: controller.signal,
            mode: "cors",
            credentials: "omit",
          })
          if (response.status === 401 || response.status === 403) {
            throw new ApiError("auth", `Event stream failed (${response.status})`, response.status)
          }
          const contentType = response.headers.get("content-type") ?? ""
          if (!response.ok || !response.body || !contentType.includes("text/event-stream")) {
            throw new ApiError("network", "The server has no v2 event stream at /api/event")
          }

          handlers.onOpen?.()
          retryDelay = 1_000 // a successful open resets the backoff

          const reader = response.body.getReader()
          const decoder = new TextDecoder()
          let buffer = ""

          while (!closed) {
            const { done, value } = await reader.read()
            if (done) {
              if (!closed) handlers.onError?.(new ApiError("network", "Event stream closed"))
              break
            }
            buffer += decoder.decode(value, { stream: true })
            buffer = buffer.replace(/\r\n?/g, "\n")

            // SSE frames are separated by a blank line.
            let boundary = buffer.indexOf("\n\n")
            while (boundary !== -1) {
              const frame = buffer.slice(0, boundary)
              buffer = buffer.slice(boundary + 2)
              const payload = frame
                .split("\n")
                .filter((line) => line.startsWith("data:"))
                .map((line) => line.slice(5).trim())
                .join("\n")
              if (payload) {
                try {
                  const event = normaliseServerEvent(JSON.parse(payload) as unknown)
                  if (event) handlers.onEvent(event)
                } catch {
                  // A malformed frame is not worth tearing the stream down for.
                }
              }
              boundary = buffer.indexOf("\n\n")
            }
          }
        } catch (error) {
          if (closed || controller.signal.aborted) return
          handlers.onError?.(error)
        }

        if (closed) return
        // Reconnect with backoff — a phone changing networks is routine.
        const shouldRetry = await sleep(retryDelay, controller.signal)
        if (!shouldRetry) return
        retryDelay = Math.min(retryDelay * 2, 15_000)
      }
    }

    void run()

    return () => {
      closed = true
      controller.abort()
    }
  }
}

// ── wire shapes ───────────────────────────────────────────────────────────

type Query = Record<string, string | number | boolean | undefined>

interface ConfigEntry {
  type: string
  path?: string
}

interface ShellInfo {
  id: string
  status: "running" | "exited" | "timeout" | "killed"
  exit?: number
}

interface RawProject {
  id: string
  canonical?: string
  directory?: string
  vcs?: string
  time?: { created?: number; initialized?: number }
  sandboxes?: string[]
}

interface RawSession {
  id: string
  parentID?: string
  projectID?: string
  title?: string
  time: { created: number; updated: number }
  agent?: string
  model?: { id?: string; providerID?: string; variant?: string }
  cost?: number
  tokens?: { input?: number; output?: number; reasoning?: number; cache?: Record<string, number> }
  location?: { directory?: string }
  revert?: unknown
}

interface RawAgent {
  id: string
  name?: string
  description?: string
  mode?: string
  hidden?: boolean
}

interface RawModel {
  id: string
  modelID?: string
  providerID: string
  name?: string
  family?: string
  disabled?: boolean
  variants?: ({ id?: string } | string)[]
}

interface RawMcp {
  name: string
  status?: { status?: string; error?: string }
}

interface RawInboxItem {
  id: string
  sessionID?: string
  timeCreated?: number
  type?: string
  delivery?: string
  payload?: { text?: string; files?: unknown[] }
}

type RawToolState =
  | { status: "streaming"; input?: string }
  | { status: "running"; input?: Record<string, unknown>; metadata?: Record<string, unknown> }
  | {
      status: "completed"
      input?: Record<string, unknown>
      content?: RawToolContent[]
      metadata?: Record<string, unknown>
    }
  | {
      status: "error"
      input?: Record<string, unknown>
      error?: { type?: string; message?: string }
      content?: RawToolContent[]
      metadata?: Record<string, unknown>
    }

type RawToolContent =
  | { type: "text"; text?: string }
  | { type: "file"; uri?: string; mime?: string; name?: string }

interface RawContentPart {
  type: string
  text?: string
  id?: string
  name?: string
  state?: RawToolState
  time?: { created?: number; ran?: number; completed?: number }
}

interface RawMessage {
  id: string
  type: string
  time: { created: number; completed?: number }
  text?: string
  agent?: string
  model?: { id?: string; providerID?: string; variant?: string }
  content?: RawContentPart[]
  files?: { data?: string; mime?: string; name?: string; source?: { type?: string; uri?: string } }[]
  cost?: number
  tokens?: { input?: number; output?: number; reasoning?: number; cache?: Record<string, number> }
  error?: { type?: string; message?: string }
  finish?: string
  summary?: string
  skill?: string
  name?: string
  description?: string
  command?: string
}

// ── helpers ───────────────────────────────────────────────────────────────

/** The `location[directory]=…` scoping v2 puts on most routes. */
function at(directory?: string): Query {
  return directory ? { "location[directory]": directory } : {}
}

/** v2 speaks in paths relative to the location; the app speaks in absolute ones. */
function relativeTo(root: string, path: string): string {
  const base = root.replace(/\/+$/, "")
  const value = path.replace(/\/+$/, "")
  if (!base || value === base) return ""
  if (value.startsWith(`${base}/`)) return value.slice(base.length + 1)
  return value.replace(/^\/+/, "")
}

function absoluteIn(root: string, path: string): string {
  if (path.startsWith("/")) return path
  const base = root.replace(/\/+$/, "")
  return base ? `${base}/${path}` : path
}

/**
 * Accept what a user would actually type. `192.168.1.24:4096` is a host and
 * port, not a path, but `new URL` reads it as the `192.168.1.24:` scheme — so
 * a missing scheme is filled in before parsing. Trailing paths are kept, since
 * the server may sit behind a reverse proxy on a sub-path.
 */
export function normaliseBaseUrl(input: string): string {
  let value = input.trim()
  if (!value) return value
  if (!/^https?:\/\//i.test(value)) value = `http://${value}`
  return value.replace(/\/+$/, "")
}

/** True when the string could address a server. Drives the Connect button. */
export function isValidServerUrl(input: string): boolean {
  const value = normaliseBaseUrl(input)
  if (!value) return false
  try {
    const url = new URL(value)
    return Boolean(url.hostname)
  } catch {
    return false
  }
}

/** `192.168.1.24:4096` — the address without scheme, for display. */
function hostOf(rawUrl: string): string {
  try {
    const parsed = new URL(rawUrl)
    return parsed.port ? `${parsed.hostname}:${parsed.port}` : parsed.hostname
  } catch {
    return rawUrl
  }
}

function base64(value: string): string {
  // btoa is latin1-only; encode first so non-ASCII passwords survive.
  const bytes = new TextEncoder().encode(value)
  let binary = ""
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary)
}

async function errorBody(response: Response): Promise<string> {
  try {
    const text = await response.text()
    if (!text) return response.statusText || `HTTP ${response.status}`
    try {
      const parsed = JSON.parse(text) as {
        message?: string
        error?: string
        data?: { message?: string }
      }
      return parsed.data?.message ?? parsed.message ?? parsed.error ?? text.slice(0, 300)
    } catch {
      return text.slice(0, 300)
    }
  } catch {
    return response.statusText || `HTTP ${response.status}`
  }
}

/** `AbortSignal.any` is not on every mobile Safari we target. */
function anySignal(signals: AbortSignal[]): AbortSignal {
  if (signals.length === 1) return signals[0]!
  if (typeof AbortSignal.any === "function") return AbortSignal.any(signals)
  const controller = new AbortController()
  for (const signal of signals) {
    if (signal.aborted) {
      controller.abort()
      break
    }
    signal.addEventListener("abort", () => controller.abort(), { once: true })
  }
  return controller.signal
}

function sleep(ms: number, signal?: AbortSignal): Promise<boolean> {
  return new Promise((resolve) => {
    if (signal?.aborted) {
      resolve(false)
      return
    }

    const timer = setTimeout(() => {
      signal?.removeEventListener("abort", onAbort)
      resolve(true)
    }, ms)
    const onAbort = () => {
      clearTimeout(timer)
      resolve(false)
    }
    signal?.addEventListener("abort", onAbort, { once: true })
  })
}

/**
 * The v2 frame is `{id, type, data, location}`. Sessions are identified inside
 * `data`, and the directory comes from the event's own location — the stream is
 * global, so that is the only way to tell whose event this is.
 */
function normaliseServerEvent(value: unknown): ServerEvent | null {
  const root = record(value)
  if (!root) return null
  const type = stringValue(root.type)
  if (!type) return null

  const data = record(root.data) ?? {}
  const location = record(root.location)

  return {
    type,
    id: stringValue(root.id) ?? undefined,
    directory: stringValue(location?.directory) ?? undefined,
    sessionID: stringValue(data.sessionID) ?? undefined,
    data,
  }
}

/**
 * True for anything the session list has no business showing: the children a
 * `task` tool spawns for a subagent belong to their parent's transcript, not
 * beside it.
 */
export function isHiddenSession(session: {
  id?: string | null
  title?: string | null
  parentID?: string | null
}): boolean {
  return !!session.parentID
}

function isCommitHash(value: string): boolean {
  return /^[0-9a-f]{4,40}$/i.test(value)
}

/** Single-quote for `sh`, which only has to survive an embedded quote. */
function quoteShellArgument(value: string): string {
  return `'${value.replaceAll("'", `'\\''`)}'`
}

function firstLine(value: string): string {
  return value.split("\n").find((line) => line.trim())?.trim() ?? ""
}

function lastLine(value: string): string {
  return (
    value
      .split("\n")
      .filter((line) => line.trim())
      .pop()
      ?.trim() ?? ""
  )
}

/**
 * The server user's home, mined from the config document paths so absolute
 * paths can be shown as `~/dev/x`. v2 has no endpoint that reports it.
 */
function homeFromConfig(entries: ConfigEntry[] | null, cwd?: string): string | undefined {
  for (const entry of entries ?? []) {
    const path = entry.path
    if (!path) continue
    const match = /^(.*)\/(?:\.claude|\.agents|\.config\/opencode)(?:\/|$)/.exec(path)
    if (match?.[1]) return match[1]
  }
  // Last resort: the first two segments of the working directory.
  const match = /^(\/(?:Users|home)\/[^/]+)(?:\/|$)/.exec(cwd ?? "")
  return match?.[1]
}

function toProject(project: RawProject): Project {
  const worktree = project.canonical ?? project.directory ?? ""
  return {
    id: project.id,
    worktree,
    vcs: project.vcs === "git" ? "git" : null,
    time: project.time,
    directories: project.sandboxes?.length ? project.sandboxes : [worktree],
  }
}

export function toInboxItem(item: RawInboxItem): InboxItem {
  return {
    id: item.id,
    sessionID: item.sessionID ?? "",
    timeCreated: item.timeCreated ?? Date.now(),
    type: item.type ?? "user",
    text: item.payload?.text ?? "",
    delivery: item.delivery === "steer" ? "steer" : "queue",
    attachments: Array.isArray(item.payload?.files) ? item.payload.files.length : 0,
  }
}

function toSession(session: RawSession): Session {
  return {
    id: session.id,
    projectID: session.projectID,
    directory: session.location?.directory,
    parentID: session.parentID,
    title: session.title,
    time: session.time,
    agent: session.agent,
    model: session.model
      ? {
          id: session.model.id,
          modelID: session.model.id,
          providerID: session.model.providerID,
          variant: session.model.variant,
        }
      : undefined,
    cost: session.cost,
    tokens: session.tokens
      ? {
          input: session.tokens.input,
          output: session.tokens.output,
          reasoning: session.tokens.reasoning,
          cache: session.tokens.cache,
        }
      : undefined,
    revert: session.revert,
  }
}

/** v2 message types that are neither a prompt nor a turn, rendered as notes. */
const SYSTEM_MESSAGE_TYPES = new Set([
  "synthetic",
  "system",
  "skill",
  "shell",
  "compaction",
  "agent-switched",
  "model-switched",
  "location-switched",
])

/**
 * A v2 message and its `content` array, flattened into the `{info, parts}`
 * shape every screen reads. Parts have no ids of their own, so they are keyed
 * by their position in the message — which is also how the event stream
 * addresses them (`ordinal` for text and reasoning, the call id for tools).
 */
export function toMessage(message: RawMessage, sessionID: string): MessageWithParts {
  const role: MessageInfo["role"] =
    message.type === "user"
      ? "user"
      : message.type === "assistant"
        ? "assistant"
        : SYSTEM_MESSAGE_TYPES.has(message.type)
          ? "system"
          : "system"

  const info: MessageInfo = {
    id: message.id,
    sessionID,
    role,
    kind: message.type,
    time: message.time,
    agent: message.agent,
    modelID: message.model?.id,
    providerID: message.model?.providerID,
    variant: message.model?.variant,
    cost: message.cost,
    tokens: message.tokens,
    finish: message.finish,
    error: message.error
      ? { name: message.error.type, data: { message: message.error.message } }
      : undefined,
  }

  const parts: Part[] = []
  const push = (part: Omit<Part, "messageID" | "sessionID">) =>
    parts.push({ ...part, messageID: message.id, sessionID } as Part)

  for (const [index, item] of (message.content ?? []).entries()) {
    if (item.type === "text" || item.type === "reasoning") {
      push({
        id: `${message.id}:${index}`,
        type: item.type,
        text: item.text ?? "",
        ordinal: index,
      })
      continue
    }
    if (item.type === "tool") {
      push({
        id: `${message.id}:tool:${item.id ?? index}`,
        type: "tool",
        tool: item.name,
        callID: item.id,
        ordinal: index,
        state: toToolState(item),
      })
    }
  }

  // The prompt itself, plus anything the user attached to it.
  if (message.type === "user") {
    for (const [index, file] of (message.files ?? []).entries()) {
      push({
        id: `${message.id}:file:${index}`,
        type: "file",
        filename: file.name,
        mime: file.mime,
        url: fileUrl(file),
      })
    }
  }
  const plain = message.text ?? message.summary ?? message.description
  if (plain) {
    push({ id: `${message.id}:text`, type: "text", text: plain })
  }

  return { info, parts }
}

function fileUrl(file: {
  data?: string
  mime?: string
  source?: { type?: string; uri?: string }
}): string | undefined {
  if (file.source?.type === "uri" && file.source.uri) return file.source.uri
  if (file.data) return `data:${file.mime ?? "application/octet-stream"};base64,${file.data}`
  return undefined
}

export function toToolState(item: RawContentPart): ToolState {
  const state = item.state
  const start = item.time?.ran ?? item.time?.created ?? 0
  const end = item.time?.completed ?? 0

  if (!state) return { status: "pending" }
  const metadata = "metadata" in state ? state.metadata : undefined
  const title = typeof metadata?.title === "string" ? metadata.title : undefined
  if (state.status === "streaming") {
    return { status: "streaming", inputText: state.input, time: start ? { start } : undefined }
  }
  if (state.status === "running") {
    return { status: "running", title, input: state.input, time: start ? { start } : undefined }
  }
  if (state.status === "completed") {
    return {
      status: "completed",
      title,
      input: state.input,
      output: toolOutput(state.content),
      metadata: state.metadata,
      time: start ? { start, end } : undefined,
    }
  }
  return {
    status: "error",
    title,
    error: state.error?.message ?? "The tool failed",
    input: state.input,
    metadata: state.metadata,
    time: start ? { start, end } : undefined,
  }
}

/** Tool output is a list of content blocks in v2; screens want one string. */
export function toolOutput(content: unknown): string {
  const blocks = Array.isArray(content) ? content : []
  return blocks
    .map((block) => {
      const entry = record(block) ?? {}
      if (entry.type === "text") return typeof entry.text === "string" ? entry.text : ""
      if (entry.type === "file")
        return typeof entry.name === "string" ? entry.name : stringValue(entry.uri) ?? ""
      return ""
    })
    .filter(Boolean)
    .join("\n")
}

const STATUS_LETTERS: Record<string, FileChangeStatus> = {
  A: "added",
  D: "deleted",
  M: "modified",
  R: "modified",
  C: "modified",
  T: "modified",
}

/**
 * `git show --name-status` and `--numstat` cannot be asked for together — the
 * last flag wins — so the command runs both and separates them with a record
 * separator. The first section carries the header and each file's status, the
 * second the line counts for the same paths.
 */
function parseCommitDetail(output: string): GitCommitDetail | null {
  const [statusSection = "", numstatSection = ""] = output.split("\u001e")

  const lines = statusSection.split("\n")
  const header = lines.find((line) => line.includes("\u001f"))
  if (!header) return null

  const [hash, author, seconds, subject, refs] = header.split("\u001f")
  if (!hash || !isCommitHash(hash)) return null

  const counts = new Map<string, { added: number; removed: number }>()
  for (const line of numstatSection.split("\n")) {
    const [added, removed, path] = line.split("\t")
    if (!path) continue
    counts.set(path.trim(), { added: toCount(added), removed: toCount(removed) })
  }

  const files: GitCommitFile[] = []
  for (const line of lines) {
    const [letter, first, second] = line.split("\t")
    // A rename reports the old path and the new one; the new one is the file.
    const path = (second || first)?.trim()
    if (!letter || !path || letter.includes("\u001f")) continue
    const status = STATUS_LETTERS[letter.trim().charAt(0).toUpperCase()]
    if (!status) continue
    const count = counts.get(path) ?? { added: 0, removed: 0 }
    files.push({ path, status, added: count.added, removed: count.removed })
  }

  return {
    hash,
    shortHash: hash.slice(0, 7),
    subject: subject ?? "",
    author: author ?? "",
    date: Number(seconds) * 1_000,
    refs: (refs ?? "")
      .split(", ")
      .map((ref) => ref.trim())
      .filter(Boolean),
    files,
  }
}

/** `-` is what numstat prints for a binary file. */
function toCount(value: string | undefined): number {
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : 0
}

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null ? (value as Record<string, unknown>) : null
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value ? value : null
}
