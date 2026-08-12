import { ApiError } from "./errors"
import type {
  AgentInfo,
  AppInfo,
  FileContent,
  FileNode,
  FileChangeStatus,
  FileStatus,
  GitCommit,
  GitCommitDetail,
  GitCommitFile,
  FsEntry,
  MessageWithParts,
  ModelInfo,
  ModelRef,
  Project,
  ServerCredentials,
  ServerEvent,
  Session,
  VcsCommitResult,
  VcsDiffFile,
  VcsFileStatus,
  VcsInfo,
  VcsPushResult,
} from "./types"

const DEFAULT_TIMEOUT_MS = 15_000

/**
 * Talks to one `opencode serve` process over HTTP.
 *
 * Two things shape this class:
 *
 * 1. The server is on the user's own network, addressed by an arbitrary URL, so
 *    every request can fail in ways a same-origin app never sees — CORS blocks,
 *    self-signed TLS, a tunnel that dropped. `request` normalises all of those
 *    into `ApiError` with a `kind` the UI can branch on.
 *
 * 2. Endpoints moved between server versions. Rather than probing the version
 *    and branching, the methods that have a history try each known path in turn
 *    and cache which one answered, so the cost is paid once per connection.
 */
export class OpenCodeClient {
  readonly baseUrl: string
  /** The address the user recognises, shown in headers and the recents list. */
  readonly displayHost: string
  private readonly authHeader: string | null
  /** Remembers which of several candidate paths this server actually serves. */
  private readonly resolvedPaths = new Map<string, string>()

  constructor(credentials: ServerCredentials) {
    const target = normaliseBaseUrl(credentials.url)
    if (credentials.proxy) {
      // Same-origin relay: /proxy/<encoded target>/<original path>. The browser
      // only ever talks to this app's origin, so there is no CORS preflight for
      // a reverse proxy to 401, and a server that strips CORS headers works.
      this.baseUrl = `${location.origin}/proxy/${encodeURIComponent(target)}`
      this.displayHost = hostOf(target)
    } else {
      this.baseUrl = target
      this.displayHost = hostOf(target)
    }
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

  private url(path: string, query?: Record<string, string | number | boolean | undefined>): string {
    const url = new URL(this.baseUrl + path)
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
      query?: Record<string, string | number | boolean | undefined>
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
    if (response.status >= 500) {
      throw new ApiError("server", await errorBody(response), response.status, url)
    }
    if (!response.ok) {
      throw new ApiError("server", await errorBody(response), response.status, url)
    }

    if (response.status === 204) return null as T

    /*
     * An opencode server serves its own web UI from the same origin, with a
     * catch-all that answers ANY unknown path with 200 and the SPA's index.html
     * rather than a 404. Without this guard two things go wrong: `requestFirst`
     * latches onto the first candidate path forever because nothing ever 404s,
     * and a screen receives a page of HTML where it expected an object, then
     * fails somewhere far away from the cause.
     *
     * Treating it as `notfound` is what makes the candidate-path fallback work
     * on these builds, and gives an honest error everywhere else.
     */
    const contentType = response.headers.get("content-type") ?? ""
    if (contentType.includes("text/html")) {
      if (optional) return null as T
      throw new ApiError(
        "notfound",
        `No API at ${path} — the server answered with its web UI`,
        404,
        url,
      )
    }

    const text = await response.text()
    if (!text) return null as T
    try {
      return JSON.parse(text) as T
    } catch {
      // Some endpoints (file bodies) legitimately return text/plain.
      if (contentType.includes("application/json")) {
        throw new ApiError("parse", `Malformed JSON from ${path}`, response.status, url)
      }
      return text as unknown as T
    }
  }

  /**
   * Try candidate paths in order, remembering the one that answers.
   *
   * `key` groups the candidates so the memo survives across calls with
   * different query strings.
   */
  private async requestFirst<T>(
    key: string,
    candidates: string[],
    options: Parameters<OpenCodeClient["request"]>[1] = {},
  ): Promise<T> {
    const known = this.resolvedPaths.get(key)
    if (known) return this.request<T>(known, options)

    let lastError: unknown
    for (const candidate of candidates) {
      try {
        const result = await this.request<T>(candidate, options)
        this.resolvedPaths.set(key, candidate)
        return result
      } catch (error) {
        // Only a missing endpoint justifies trying the next candidate — an auth
        // or network failure would fail identically on all of them.
        if (error instanceof ApiError && error.kind === "notfound") {
          lastError = error
          continue
        }
        throw error
      }
    }
    throw lastError ?? new ApiError("notfound", `No endpoint found for ${key}`)
  }

  // ── connection ──────────────────────────────────────────────────────────

  /**
   * Confirm the server is reachable, the credentials work, and report where it
   * is rooted. This is the handshake screen's whole job.
   *
   * Assembled from two endpoints because no single one carries all of it:
   * `/path` gives the directories (including the server user's home, which is
   * what lets paths be shown as `~/dev/x` instead of guessed at), and
   * `/project/current` carries `vcs`, which is the only authoritative answer to
   * "is this a repository" and therefore what gates the whole Git tab.
   *
   * `/project/current` is allowed to fail: a server started outside any project
   * still works, it just has no repository.
   */
  async getAppInfo(signal?: AbortSignal): Promise<AppInfo> {
    const path = await this.request<{
      home?: string
      worktree?: string
      directory?: string
      config?: string
      state?: string
    }>("/path", { signal, timeoutMs: 8_000 })

    const project = await this.request<Project>("/project/current", {
      signal,
      optional: true,
      timeoutMs: 8_000,
    }).catch(() => null)

    return {
      git: project?.vcs === "git",
      home: path?.home,
      path: {
        root: project?.worktree ?? path?.worktree ?? path?.directory,
        cwd: path?.directory,
        config: path?.config,
        state: path?.state,
      },
    }
  }

  // ── vcs ─────────────────────────────────────────────────────────────────

  /**
   * Branch and ahead/behind. There is no version endpoint on any build we
   * support, so the handshake reports the branch as its only identifier.
   */
  async getVcsInfo(directory: string, signal?: AbortSignal): Promise<VcsInfo | null> {
    return this.request<VcsInfo>("/vcs", { query: { directory }, signal, optional: true })
  }

  /**
   * Recent commits, in descending order of preference: a real log endpoint if a
   * build ever ships one, then `git log` through the shell endpoint, then git's
   * own reflog. The reflog is last because a cloned repository has one entry in
   * it, which is history in name only.
   */
  async getVcsCommits(directory: string, limit = 20, signal?: AbortSignal): Promise<GitCommit[]> {
    try {
      const result = await this.requestFirst<
        GitCommit[] | { data?: GitCommit[]; commits?: GitCommit[] }
      >("vcs-log", ["/vcs/log", "/vcs/commits", "/vcs/history"], {
        query: { directory, limit },
        signal,
      })
      const commits = Array.isArray(result) ? result : (result?.data ?? result?.commits ?? [])
      if (commits.length > 0) {
        return commits.slice(0, limit).map((commit) => ({
          ...commit,
          shortHash: commit.shortHash || commit.hash.slice(0, 7),
          refs: commit.refs ?? [],
        }))
      }
    } catch (error) {
      if (!(error instanceof ApiError && error.kind === "notfound")) throw error
    }

    try {
      const commits = await this.readGitLog(directory, limit, signal)
      if (commits.length > 0) return commits
    } catch (error) {
      if (error instanceof ApiError && error.kind === "aborted") throw error
      // A build without the shell endpoint still gets the reflog below.
    }

    return this.readReflogCommits(directory, limit, signal)
  }

  /**
   * Run one command on the server and hand back its stdout.
   *
   * The shell endpoint belongs to a session, so a session is created for the
   * call and removed straight after — the command never lands in a
   * conversation the user is reading. No model runs; the output is the
   * command's own.
   */
  private async runCommand(
    directory: string,
    command: string,
    signal?: AbortSignal,
  ): Promise<string> {
    const session = await this.createSession(directory, INTERNAL_SESSION_TITLE, signal)
    try {
      const message = await this.request<MessageWithParts>(
        `/session/${encodeURIComponent(session.id)}/shell`,
        {
          method: "POST",
          query: { directory },
          body: { command, agent: "build" },
          signal,
          timeoutMs: 60_000,
        },
      )
      for (const part of message?.parts ?? []) {
        if (part.type !== "tool" || part.state?.status !== "completed") continue
        const output = part.state.output
        if (typeof output === "string") return output
      }
      return ""
    } finally {
      // Best effort: a stranded session is noise, but not worth an error.
      void this.deleteSession(session.id, directory).catch(() => undefined)
    }
  }

  /** Commits from `git log`, which is the only source with real depth. */
  private async readGitLog(
    directory: string,
    limit: number,
    signal?: AbortSignal,
  ): Promise<GitCommit[]> {
    const output = await this.runCommand(
      directory,
      `git log --no-color --max-count=${Math.max(1, Math.trunc(limit))} --format=%H%x1f%an%x1f%at%x1f%s%x1f%D`,
      signal,
    )
    return output
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
    const output = await this.runCommand(
      directory,
      `git show --no-color --format=%H%x1f%an%x1f%at%x1f%s%x1f%D --name-status ${hash};` +
        ` printf '\\036';` +
        ` git show --no-color --format= --numstat ${hash}`,
      signal,
    )
    return parseCommitDetail(output)
  }

  /** The patch for one file in one commit, ready for `parseUnifiedDiff`. */
  async getCommitFileDiff(
    directory: string,
    hash: string,
    path: string,
    signal?: AbortSignal,
  ): Promise<string> {
    if (!isCommitHash(hash)) return ""
    return this.runCommand(
      directory,
      `git show --no-color --format= ${hash} -- ${quoteShellArgument(path)}`,
      signal,
    )
  }

  /**
   * The branch's reflog, then HEAD's. The branch file records only what landed
   * on that branch, so it reads as history; HEAD's also carries checkouts and
   * is the fallback for a detached or freshly cloned worktree.
   */
  private async readReflogCommits(
    directory: string,
    limit: number,
    signal?: AbortSignal,
  ): Promise<GitCommit[]> {
    const root = directory.replace(/\/+$/, "")
    const info = await this.getVcsInfo(directory, signal).catch(() => null)
    const branch = info?.branch?.trim()
    const candidates = [
      branch ? `${root}/.git/logs/refs/heads/${branch}` : null,
      `${root}/.git/logs/HEAD`,
    ].filter((path): path is string => path !== null)

    for (const path of candidates) {
      try {
        const file = await this.readFile(path, directory, signal)
        const commits = parseReflog(file.content, limit)
        if (commits.length > 0) return commits
      } catch (error) {
        if (error instanceof ApiError && error.kind === "aborted") throw error
      }
    }
    return []
  }

  /**
   * Working-tree changes from the first-class VCS endpoint. Modern builds
   * answer this; older ones return `/file/status`-shaped data instead.
   */
  async getVcsStatus(directory: string, signal?: AbortSignal): Promise<VcsFileStatus[]> {
    const result = await this.request<VcsFileStatus[]>("/vcs/status", {
      query: { directory },
      signal,
      optional: true,
    })
    return result ?? []
  }

  /** Per-file patches from the VCS API. `mode` is `"git"` (worktree) or `"branch"`. */
  async getVcsDiff(
    directory: string,
    mode: "git" | "branch" = "git",
    signal?: AbortSignal,
  ): Promise<VcsDiffFile[]> {
    const result = await this.request<VcsDiffFile[]>("/vcs/diff", {
      query: { directory, mode },
      signal,
      optional: true,
    })
    return result ?? []
  }

  /** Commit everything currently staged, via the VCS API. */
  async commitVcs(
    directory: string,
    message: string,
    signal?: AbortSignal,
  ): Promise<VcsCommitResult> {
    return this.request<VcsCommitResult>("/vcs/commit", {
      method: "POST",
      query: { directory },
      body: { message },
      signal,
    })
  }

  async pushVcs(directory: string, signal?: AbortSignal): Promise<VcsPushResult> {
    return this.request<VcsPushResult>("/vcs/push", {
      method: "POST",
      query: { directory },
      signal,
    })
  }

  // ── projects ────────────────────────────────────────────────────────────

  async listProjects(signal?: AbortSignal): Promise<Project[]> {
    const result = await this.request<Project[]>("/project", { signal, optional: true })
    return result ?? []
  }

  async getCurrentProject(signal?: AbortSignal): Promise<Project | null> {
    return this.request<Project>("/project/current", { signal, optional: true })
  }

  // ── sessions ────────────────────────────────────────────────────────────

  async listSessions(directory?: string, signal?: AbortSignal): Promise<Session[]> {
    const result = await this.request<Session[]>("/session", { query: { directory }, signal })
    return result ?? []
  }

  /** One session, including the agent and model it currently runs under. */
  async getSession(
    sessionId: string,
    directory?: string,
    signal?: AbortSignal,
  ): Promise<Session | null> {
    const result = await this.request<Session>(`/session/${encodeURIComponent(sessionId)}`, {
      query: { directory },
      signal,
      optional: true,
    })
    return result ?? null
  }

  async getSessionStatuses(
    directory?: string,
    signal?: AbortSignal,
  ): Promise<Record<string, { type?: string }> | null> {
    try {
      const result = await this.requestFirst<Record<string, { type?: string }>>(
        "session-status",
        ["/session/status", "/api/session/status"],
        { query: { directory }, signal },
      )
      return result ?? {}
    } catch (error) {
      if (error instanceof ApiError && error.kind === "notfound") return null
      throw error
    }
  }

  async createSession(directory?: string, title?: string, signal?: AbortSignal): Promise<Session> {
    return this.request<Session>("/session", {
      method: "POST",
      query: { directory },
      body: { title },
      signal,
    })
  }

  async deleteSession(id: string, directory?: string, signal?: AbortSignal): Promise<void> {
    await this.request<void>(`/session/${encodeURIComponent(id)}`, {
      method: "DELETE",
      query: { directory },
      signal,
    })
  }

  async listMessages(
    sessionId: string,
    directory?: string,
    signal?: AbortSignal,
  ): Promise<MessageWithParts[]> {
    const encoded = encodeURIComponent(sessionId)
    const result = await this.requestFirst<MessageWithParts[]>(
      "session-messages",
      [`/session/${encoded}/message`, `/api/session/${encoded}/message`],
      { query: { directory }, signal },
    )
    return result ?? []
  }

  /** Send a prompt admission request; assistant output arrives on the SSE stream. */
  async sendPrompt(
    sessionId: string,
    text: string,
    options: {
      directory?: string
      providerID?: string
      modelID?: string
      variant?: string
      agent?: string
      signal?: AbortSignal
    } = {},
  ): Promise<MessageWithParts | null> {
    const model =
      options.providerID && options.modelID
        ? { providerID: options.providerID, modelID: options.modelID }
        : undefined
    const encoded = encodeURIComponent(sessionId)
    return this.requestFirst<MessageWithParts | null>(
      "session-prompt",
      [
        `/session/${encoded}/prompt_async`,
        `/session/${encoded}/message`,
        `/api/session/${encoded}/prompt`,
      ],
      {
        method: "POST",
        query: { directory: options.directory },
        body: {
          parts: [{ type: "text", text }],
          ...(model
            ? {
                model: {
                  ...model,
                  ...(options.variant ? { variant: options.variant } : {}),
                },
              }
            : {}),
          ...(options.agent ? { agent: options.agent } : {}),
        },
        signal: options.signal,
        timeoutMs: 10 * 60_000,
      },
    )
  }

  async abortSession(sessionId: string, directory?: string): Promise<void> {
    const encoded = encodeURIComponent(sessionId)
    await this.requestFirst<void>(
      "session-abort",
      [`/session/${encoded}/abort`, `/api/session/${encoded}/interrupt`],
      {
        method: "POST",
        query: { directory },
      },
    )
  }

  // ── files ───────────────────────────────────────────────────────────────

  /**
   * One directory level. The tree screen expands lazily, one level per tap.
   *
   * Modern builds serve this from `/api/fs/list`, which takes the directory as
   * a bracket-encoded `location` object; older builds used `/file?path=`. Both
   * are tried in order, and the response shapes are normalised here.
   */
  async listDirectory(path: string, directory?: string, signal?: AbortSignal): Promise<FileNode[]> {
    const modern = await this.request<{ location?: { directory?: string }; data?: FsEntry[] }>(
      "/api/fs/list",
      {
        query: { "location[directory]": path, directory },
        signal,
        optional: true,
      },
    )
    if (modern?.data) {
      const base = modern.location?.directory ?? path
      return modern.data.map((entry) => ({
        name: entry.path.replace(/\/+$/, "").split("/").pop() ?? entry.path,
        path: `${base}/${entry.path}`,
        type: entry.type === "directory" ? "directory" : "file",
      }))
    }
    const legacy = await this.requestFirst<FileNode[]>("readdir", ["/file", "/file/list"], {
      query: { path, directory },
      signal,
    })
    return legacy ?? []
  }

  async readFile(path: string, directory?: string, signal?: AbortSignal): Promise<FileContent> {
    const result = await this.requestFirst<FileContent | string>(
      "readfile",
      ["/file/content", "/file/read"],
      { query: { path, directory }, signal },
    )
    if (typeof result === "string") return { type: "raw", content: result }
    return result ?? { type: "raw", content: "" }
  }

  /**
   * Working-tree changes, in the client's `FileStatus` shape.
   *
   * The source differs by server build: modern ones answer `/vcs/status` with
   * `{file, additions, deletions, status}`; older ones answer `/file/status`
   * with `{path, status, added, removed}` and no staged flag. Both map onto the
   * same shape so screens never branch on which endpoint answered.
   */
  async fileStatus(directory?: string, signal?: AbortSignal): Promise<FileStatus[]> {
    const vcs = await this.request<VcsFileStatus[]>("/vcs/status", {
      query: { directory },
      signal,
      optional: true,
    })
    if (vcs && vcs.length > 0) {
      return vcs.map((entry) => ({
        path: entry.file,
        status: entry.status,
        added: entry.additions,
        removed: entry.deletions,
      }))
    }
    const legacy = await this.request<FileStatus[]>("/file/status", {
      query: { directory },
      signal,
      optional: true,
    })
    return legacy ?? []
  }

  /** Fuzzy path search, backing the tree's filter field. */
  async findFiles(query: string, directory?: string, signal?: AbortSignal): Promise<string[]> {
    const result = await this.request<string[]>("/find/file", {
      query: { query, directory },
      signal,
      optional: true,
    })
    return result ?? []
  }

  // ── agents and models ────────────────────────────────────────────────────

  /**
   * The agents this server can run a session under. Modern builds answer
   * `/api/agent` with a `{location, data}` envelope; older ones answer `/agent`
   * with a bare array — both are normalised to the `AgentInfo` shape.
   */
  async listAgents(directory?: string, signal?: AbortSignal): Promise<AgentInfo[]> {
    const modern = await this.request<{ data?: unknown[] }>("/api/agent", {
      query: { directory },
      signal,
      optional: true,
    })
    if (Array.isArray(modern?.data))
      return modern.data.map(toAgent).filter((agent): agent is AgentInfo => !!agent)

    const legacy = await this.request<unknown[]>("/agent", {
      query: { directory },
      signal,
      optional: true,
    })
    return (legacy ?? []).map(toAgent).filter((agent): agent is AgentInfo => !!agent)
  }

  /** The models this server can run, newest-first, active and enabled only. */
  async listModels(directory?: string, signal?: AbortSignal): Promise<ModelInfo[]> {
    const modern = await this.request<{ data?: ModelInfo[] }>("/api/model", {
      query: { directory },
      signal,
      optional: true,
    })
    const candidates = Array.isArray(modern?.data)
      ? modern.data
      : ((await this.request<ModelInfo[]>("/model", {
          query: { directory },
          signal,
          optional: true,
        })) ?? [])
    return candidates
      .filter((model) => model.enabled !== false && model.status !== "deprecated")
      .map((model) => ({
        ...model,
        name: model.name ?? model.id,
        variants: Array.isArray(model.variants)
          ? model.variants.map((variant) =>
              typeof variant === "string" ? variant : String(variant),
            )
          : [],
      }))
  }

  /**
   * Point a session at a different agent. Returns without error on servers
   * that do not expose the endpoint — the next prompt simply keeps its old
   * agent, which the UI surfaces.
   */
  async switchAgent(sessionId: string, agent: string, directory?: string): Promise<void> {
    await this.request(`/api/session/${encodeURIComponent(sessionId)}/agent`, {
      method: "POST",
      query: { directory },
      body: { agent },
      optional: true,
    }).catch(() => undefined)
  }

  /** Point a session at a different model (and optional variant). */
  async switchModel(sessionId: string, model: ModelRef, directory?: string): Promise<void> {
    await this.request(`/api/session/${encodeURIComponent(sessionId)}/model`, {
      method: "POST",
      query: { directory },
      body: { model },
      optional: true,
    }).catch(() => undefined)
  }

  // ── events ──────────────────────────────────────────────────────────────

  /**
   * Subscribe to the server's SSE stream.
   *
   * `EventSource` cannot carry an Authorization header, so this reads the
   * stream over fetch and parses the wire format by hand. Returns a function
   * that closes the connection.
   */
  subscribe(
    handlers: {
      onEvent: (event: ServerEvent) => void
      onError?: (error: unknown) => void
      onOpen?: () => void
    },
    directory?: string,
  ): () => void {
    const controller = new AbortController()
    let closed = false
    let retryDelay = 1_000
    let streamPath: string | null = null

    const run = async () => {
      while (!closed) {
        try {
          const candidates = streamPath ? [streamPath] : ["/global/event", "/event", "/api/event"]
          let response: Response | null = null
          for (const path of candidates) {
            const candidate = await fetch(this.url(path, { directory }), {
              headers: this.headers({ Accept: "text/event-stream" }),
              signal: controller.signal,
              mode: "cors",
              credentials: "omit",
            })
            const contentType = candidate.headers.get("content-type") ?? ""
            if (candidate.status === 401 || candidate.status === 403) {
              throw new ApiError(
                "auth",
                `Event stream failed (${candidate.status})`,
                candidate.status,
              )
            }
            if (candidate.ok && candidate.body && contentType.includes("text/event-stream")) {
              response = candidate
              streamPath = path
              break
            }
          }
          if (!response)
            throw new ApiError("network", "No compatible event stream endpoint responded")

          handlers.onOpen?.()
          retryDelay = 1_000 // a successful open resets the backoff

          const body = response.body
          if (!body) throw new ApiError("network", "Event stream has no response body")
          const reader = body.getReader()
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

// ── helpers ───────────────────────────────────────────────────────────────

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

function normaliseServerEvent(value: unknown): ServerEvent | null {
  const root = record(value)
  if (!root) return null
  const payload = record(root.payload)
  const source = payload?.type ? payload : root
  const type = typeof source.type === "string" ? source.type : null
  if (!type) return null

  const rootData = record(root.data) ?? record(root.properties)
  const sourceData = record(source.data) ?? record(source.properties)
  const data = { ...(rootData ?? {}), ...(sourceData ?? {}) }
  const sessionID =
    stringValue(source.sessionID) ??
    stringValue(root.sessionID) ??
    stringValue(data.sessionID) ??
    undefined
  if (sessionID && !data.sessionID) data.sessionID = sessionID

  return {
    type,
    id: stringValue(root.id) ?? undefined,
    directory: stringValue(root.directory) ?? stringValue(source.directory) ?? undefined,
    sessionID,
    data,
  }
}

/** The throwaway session a server command runs in, named so it is recognisable. */
const INTERNAL_SESSION_TITLE = "opencode mobile · internal"

export function isInternalSessionTitle(title: string | undefined): boolean {
  return title?.trim() === INTERNAL_SESSION_TITLE
}

function isCommitHash(value: string): boolean {
  return /^[0-9a-f]{4,40}$/i.test(value)
}

/** Single-quote for `sh`, which only has to survive an embedded quote. */
function quoteShellArgument(value: string): string {
  return `'${value.replaceAll("'", `'\\''`)}'`
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

/**
 * One reflog line is `<old> <new> <name> <email> <ts> <tz>\t<action>: <subject>`.
 * Only the actions that create a commit are history; a checkout or a reset
 * repeats a hash that is already in the list under its real subject.
 */
const REFLOG_LINE = /^([0-9a-f]{7,40}) ([0-9a-f]{7,40}) (.*?) <(.*?)> (\d+) [+-]\d{4}\t(.*)$/
const REFLOG_COMMIT_ACTIONS = /^(commit|merge|rebase|cherry-pick|revert|am|pull)\b/

function parseReflog(content: string, limit: number): GitCommit[] {
  const commits: GitCommit[] = []
  const seen = new Set<string>()

  // Newest last on disk, newest first on screen.
  for (const line of content.split("\n").reverse()) {
    const match = REFLOG_LINE.exec(line.trim())
    if (!match) continue

    const [, , hash, author, , seconds, entry] = match
    if (!hash || seen.has(hash)) continue

    const separator = entry?.indexOf(": ") ?? -1
    const action = separator === -1 ? (entry ?? "") : entry!.slice(0, separator)
    const subject = separator === -1 ? "" : entry!.slice(separator + 2).trim()
    if (!REFLOG_COMMIT_ACTIONS.test(action) || !subject) continue

    seen.add(hash)
    commits.push({
      hash,
      shortHash: hash.slice(0, 7),
      subject,
      author: author ?? "",
      date: Number(seconds) * 1_000,
      refs: [],
    })
    if (commits.length >= limit) break
  }

  return commits
}

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null ? (value as Record<string, unknown>) : null
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value ? value : null
}

/** Normalise either agent envelope (array items or `{id}`) into `AgentInfo`. */
function toAgent(value: unknown): AgentInfo | null {
  if (!value || typeof value !== "object") return null
  const entry = value as Record<string, unknown>
  const id =
    typeof entry.id === "string" ? entry.id : typeof entry.name === "string" ? entry.name : null
  if (!id) return null
  return {
    id,
    name: typeof entry.name === "string" ? entry.name : id,
    description: typeof entry.description === "string" ? entry.description : undefined,
    mode: typeof entry.mode === "string" ? entry.mode : undefined,
    hidden: typeof entry.hidden === "boolean" ? entry.hidden : false,
  }
}
