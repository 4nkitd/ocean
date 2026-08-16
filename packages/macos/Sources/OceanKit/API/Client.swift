import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Every v2 route lives under this prefix; anything else is the server's own UI.
private let apiPrefix = "/api"
private let defaultTimeout: TimeInterval = 15

/**
 Talks to one `opencode serve` (v2) process over HTTP.

 Two things shape this type:

 1. The server is on the user's own network, addressed by an arbitrary URL, so
    every request can fail in ways a local call never does — refused
    connections, self-signed TLS, a tunnel that dropped. `send` normalises all
    of those into `ApiError` with a `kind` the UI can branch on.

 2. v2 answers location-scoped routes with a `{location, data}` envelope and
    session routes with `{data}`. Unwrapping happens here so no screen sees an
    envelope, and paths cross the boundary absolute even though v2 speaks in
    paths relative to the directory.

 A `final class` rather than an actor on purpose: everything it holds is a
 `let`, and `URLSession` is already safe to share. An actor would serialise
 requests that should run concurrently and buy nothing. Cancellation rides on
 the calling `Task` — that is the Swift spelling of the Vue client's
 `AbortSignal`, so there is no `signal:` parameter to thread through.
 */
public final class OpenCodeClient: Sendable {
  public let baseURL: String
  /// The address the user recognises, shown in headers and the recents list.
  public let displayHost: String
  let authHeader: String?
  private let session: URLSession

  public init(credentials: ServerCredentials, session: URLSession = .shared) {
    let target = normaliseBaseUrl(credentials.url)
    baseURL = target
    displayHost = hostOf(target)
    if credentials.useBasicAuth, !credentials.username.isEmpty {
      let raw = "\(credentials.username):\(credentials.password)"
      authHeader = "Basic " + Data(raw.utf8).base64EncodedString()
    } else {
      authHeader = nil
    }
    self.session = session
  }

  // MARK: - Core transport

  private func headers(json: Bool = false, accept: String = "application/json") -> [String: String] {
    var headers = ["Accept": accept]
    if let authHeader { headers["Authorization"] = authHeader }
    if json { headers["Content-Type"] = "application/json" }
    return headers
  }

  func url(_ path: String, _ query: Query = [:]) throws -> URL {
    var text = baseURL + apiPrefix + path
    let encoded = query.encoded()
    if !encoded.isEmpty { text += "?" + encoded }
    guard let url = URL(string: text) else {
      throw ApiError(.network, "Could not build a URL for \(path)", url: text)
    }
    return url
  }

  /// The `/api/event` request, handed to `EventStream` so it can hold the
  /// connection open itself. Nothing else should open a second stream.
  public func eventRequest() throws -> URLRequest {
    var request = URLRequest(url: try url("/event"))
    request.allHTTPHeaderFields = headers(accept: "text/event-stream")
    request.timeoutInterval = 3600
    return request
  }

  private struct RawResponse {
    let body: Data
    let contentType: String
    let status: Int
  }

  /// `nil` only when `optional` and the route is missing (404, or a web UI).
  private func send(
    _ path: String,
    method: String = "GET",
    query: Query = [:],
    body: JSONValue? = nil,
    timeout: TimeInterval = defaultTimeout,
    optional: Bool = false
  ) async throws -> RawResponse? {
    let target = try url(path, query)
    var request = URLRequest(url: target)
    request.httpMethod = method
    request.allHTTPHeaderFields = headers(json: body != nil)
    request.timeoutInterval = timeout
    if let body { request.httpBody = try body.encoded() }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch let error as URLError {
      // A cancelled URLSession task and a cancelled caller look the same from
      // here; the caller's own task is the tie-breaker.
      if Task.isCancelled { throw ApiError(.aborted, "Request cancelled", url: target.absoluteString) }
      throw apiError(from: error, url: target.absoluteString)
    } catch is CancellationError {
      throw ApiError(.aborted, "Request cancelled", url: target.absoluteString)
    }

    guard let http = response as? HTTPURLResponse else {
      throw ApiError(.parse, "The server did not answer with HTTP", url: target.absoluteString)
    }
    let status = http.statusCode
    let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()

    if status == 401 || status == 403 {
      throw ApiError(.auth, "Authentication failed", status: status, url: target.absoluteString)
    }
    if status == 404 {
      if optional { return nil }
      throw ApiError(.notfound, "Not found: \(path)", status: 404, url: target.absoluteString)
    }
    if status >= 400 {
      throw ApiError(
        .server, errorBody(data, status: status), status: status, url: target.absoluteString)
    }

    /*
     A v2 server serves its own web UI from the same origin, with a catch-all
     that answers any non-`/api` path with 200 and the SPA's index.html rather
     than a 404. Reaching that page means we asked a v1 server (or a proxy in
     front of one) for a v2 route, and saying so beats handing a screen a page
     of HTML where it expected an object.
     */
    if contentType.contains("text/html") {
      if optional { return nil }
      throw ApiError(
        .notfound,
        "No v2 API at \(path) — the server answered with a web UI",
        status: 404,
        url: target.absoluteString
      )
    }

    return RawResponse(body: data, contentType: contentType, status: status)
  }

  /// The parsed body, or `.null` for 204 and empty responses.
  @discardableResult
  private func json(
    _ path: String,
    method: String = "GET",
    query: Query = [:],
    body: JSONValue? = nil,
    timeout: TimeInterval = defaultTimeout,
    optional: Bool = false
  ) async throws -> JSONValue {
    guard
      let response = try await send(
        path, method: method, query: query, body: body, timeout: timeout, optional: optional)
    else { return .null }
    if response.status == 204 || response.body.isEmpty { return .null }
    do {
      return try JSONValue.parse(response.body)
    } catch {
      if response.contentType.contains("application/json") {
        throw ApiError(.parse, "Malformed JSON from \(path)", status: response.status)
      }
      // File bodies come back as text/plain.
      return .string(String(decoding: response.body, as: UTF8.self))
    }
  }

  /// A request whose payload is wrapped in v2's `{data}` / `{location, data}`
  /// envelope. A body that is not an envelope is passed straight through, which
  /// is how `/api/project` — a bare array — works with the same helper.
  private func data(
    _ path: String,
    method: String = "GET",
    query: Query = [:],
    body: JSONValue? = nil,
    timeout: TimeInterval = defaultTimeout,
    optional: Bool = false
  ) async throws -> JSONValue {
    let value = try await json(
      path, method: method, query: query, body: body, timeout: timeout, optional: optional)
    return unwrapEnvelope(value)
  }

  private func cachedData(
    _ path: String,
    query: Query = [:],
    ttl: TimeInterval,
    optional: Bool = false
  ) async throws -> JSONValue {
    let key = "GET|\(path)|\(query.encoded())"
    if let cached = APICache.shared.get(key) {
      if cached.isEmpty { return .null }
      let value = (try? JSONValue.parse(cached)) ?? .string(String(decoding: cached, as: UTF8.self))
      return unwrapEnvelope(value)
    }

    guard let response = try await send(path, method: "GET", query: query, optional: optional) else {
      return .null
    }

    APICache.shared.put(key, data: response.body, ttl: ttl)

    if response.status == 204 || response.body.isEmpty { return .null }
    let value: JSONValue
    do {
      value = try JSONValue.parse(response.body)
    } catch {
      if response.contentType.contains("application/json") {
        throw ApiError(.parse, "Malformed JSON from \(path)", status: response.status)
      }
      value = .string(String(decoding: response.body, as: UTF8.self))
    }
    return unwrapEnvelope(value)
  }

  // MARK: - Connection

  public func health() async throws -> ServerHealth {
    ServerHealth(json: try await json("/health", timeout: 8))
  }

  public func getLocation() async throws -> LocationInfo? {
    let value = try await json("/location", timeout: 8, optional: true)
    return value.isNull ? nil : LocationInfo(json: value)
  }

  public func getConfig() async throws -> [ConfigEntry] {
    try await cachedData("/config", ttl: 30, optional: true).array.compactMap(ConfigEntry.init(json:))
  }

  /**
   Confirm the server is reachable, the credentials work, and report what it is
   and where it is rooted. This is the handshake screen's whole job.

   `/api/health` is the reachability and version check, `/api/location` says
   where the server is rooted, the project list carries `vcs` (the only
   authoritative answer to "is this a repository", which gates the Git tab), and
   `/api/config` is mined for the server user's home so paths can be shown as
   `~/dev/x`. Only health is required; the rest are allowed to fail on a server
   started outside any project.
   */
  public func getAppInfo() async throws -> AppInfo {
    let health = try await self.health()

    async let locationTask = try? getLocation()
    async let projectsTask = (try? json("/project", timeout: 8, optional: true)) ?? .null
    async let configTask = (try? getConfig()) ?? []

    let (location, projects, config) = await (locationTask, projectsTask, configTask)
    let cwd = location?.directory

    // `/api/project/current` does not report `vcs`; the project list does, so
    // the entry that owns this directory is the authoritative "is a repo".
    let owning = projects.array.first { entry in
      guard let cwd else { return false }
      return entry["canonical"].string == cwd || entry["sandboxes"].stringArray.contains(cwd)
    }

    return AppInfo(
      git: owning?["vcs"].string == "git",
      home: homeFromConfig(config, cwd: cwd),
      path: AppInfo.Paths(
        root: owning?["canonical"].string ?? location?.projectRoot ?? cwd,
        cwd: cwd,
        config: config.first { $0.type == "document" }?.path
      ),
      version: health.version
    )
  }

  // MARK: - Shell

  /**
   Run one command on the server and hand back its output.

   v2 has a first-class shell endpoint that is not attached to a session, so
   nothing lands in a conversation the user is reading. The command is started,
   polled until it leaves `running`, then its output is read and the record is
   removed.
   */
  public func runShell(
    _ directory: String, _ command: String, timeout: TimeInterval = 60
  ) async throws -> ShellResult {
    let query = at(directory)
    let started = try await data(
      "/shell",
      method: "POST",
      query: query,
      body: .object([
        "command": .string(command),
        "cwd": .string(directory),
        "timeout": .number(timeout * 1000),
      ])
    )
    guard let id = started["id"].string else {
      throw ApiError(.server, "The server did not start the command")
    }

    let escaped = pathEscape(id)
    var status = ShellStatus(rawValue: started["status"].string ?? "") ?? .running
    var exit = started["exit"].int
    let deadline = Date().addingTimeInterval(timeout)

    // Detached so the record is still cleaned up when the caller cancels.
    defer {
      let client = self
      Task.detached {
        try? await client.send("/shell/\(escaped)", method: "DELETE", query: query, optional: true)
      }
    }

    while status == .running && Date() < deadline {
      do {
        try await Task.sleep(nanoseconds: 150_000_000)
      } catch {
        throw ApiError(.aborted, "Request cancelled")
      }
      let info = try await data("/shell/\(escaped)", query: query, optional: true)
      if info.isNull { break }
      status = ShellStatus(rawValue: info["status"].string ?? "") ?? status
      exit = info["exit"].int ?? exit
    }

    let output = try await data("/shell/\(escaped)/output", query: query)
    return ShellResult(output: output["output"].string ?? "", exit: exit, status: status)
  }

  /**
   Start a command and return straight away.

   `runShell` above is the right shape for the one-shot commands the Git screens
   run. A terminal is the other shape: the caller wants the output as it is
   printed, so it owns the record instead — poll `getShell`, page the output
   with `readShellOutput`, and `removeShell` when finished.
   */
  public func startShell(
    _ directory: String, _ command: String, cwd: String? = nil, timeout: TimeInterval = 600
  ) async throws -> ShellCommand {
    let started = try await data(
      "/shell",
      method: "POST",
      query: at(directory),
      body: .object([
        "command": .string(command),
        "cwd": .string(cwd ?? directory),
        "timeout": .number(timeout * 1000),
      ])
    )
    guard let id = started["id"].string else {
      throw ApiError(.server, "The server did not start the command")
    }
    return ShellCommand(
      id: id,
      status: ShellStatus(rawValue: started["status"].string ?? "") ?? .running,
      exit: started["exit"].int
    )
  }

  /// Status and exit code of a started command.
  public func getShell(_ directory: String, _ id: String) async throws -> ShellCommand? {
    let info = try await data("/shell/\(pathEscape(id))", query: at(directory), optional: true)
    if info.isNull { return nil }
    return ShellCommand(
      id: info["id"].string ?? id,
      status: ShellStatus(rawValue: info["status"].string ?? "") ?? .running,
      exit: info["exit"].int
    )
  }

  /**
   The next page of combined output. `cursor` is an absolute byte offset, so
   handing back the one from the previous page streams a running command without
   re-reading what has already been printed.
   */
  public func readShellOutput(
    _ directory: String, _ id: String, cursor: Int = 0
  ) async throws -> ShellChunk {
    var query = at(directory)
    query["cursor"] = String(cursor)
    let page = try await data("/shell/\(pathEscape(id))/output", query: query)
    let output = page["output"].string ?? ""
    // The server reports where it left off, but only its own cursor advances
    // the read — if it echoes the request back, count the bytes ourselves so
    // the next page cannot repeat this one forever.
    let reported = page["cursor"].int ?? 0
    let next = reported > cursor ? reported : cursor + output.utf8.count
    return ShellChunk(output: output, cursor: next, truncated: page["truncated"].isTrue)
  }

  /// Drop the record, killing the process if it is still running.
  public func removeShell(_ directory: String, _ id: String) async {
    _ = try? await send(
      "/shell/\(pathEscape(id))", method: "DELETE", query: at(directory), optional: true)
  }

  // MARK: - VCS

  /// Branch, plus ahead/behind counted against the upstream when there is one.
  public func getVcsInfo(_ directory: String) async throws -> VcsInfo? {
    let info = try await cachedData("/vcs", query: at(directory), ttl: 5, optional: true)
    if info.isNull { return nil }

    let tracking = try? await runShell(
      directory,
      "git rev-list --left-right --count @{u}...HEAD 2>/dev/null || true",
      timeout: 15
    )
    let counts = (tracking?.output ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(whereSeparator: \.isWhitespace)
      .compactMap { Int($0) }

    return VcsInfo(
      branch: info["branch"]["current"].string,
      defaultBranch: info["branch"]["default"].string,
      ahead: counts.count > 1 ? counts[1] : 0,
      behind: counts.count > 0 ? counts[0] : 0
    )
  }

  /**
   Just the current branch.

   `getVcsInfo` also counts ahead/behind, which costs a whole shell round trip;
   a list of project cards only names the branch, and pays for one request.
   */
  public func getVcsBranch(_ directory: String) async throws -> String? {
    let info = try await cachedData("/vcs", query: at(directory), ttl: 5, optional: true)
    let branch = info["branch"]["current"].string?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return branch.isEmpty || branch == "HEAD" ? nil : branch
  }

  /// Recent commits from `git log`, which is the only source with real depth.
  public func getVcsCommits(_ directory: String, limit: Int = 20) async throws -> [GitCommit] {
    let count = max(1, limit)
    let result = try await runShell(
      directory,
      "git log --no-color --max-count=\(count) --format=%H%x1f%an%x1f%at%x1f%s%x1f%D",
      timeout: 30
    )
    return result.output.split(separator: "\n", omittingEmptySubsequences: false).compactMap {
      commitFromLogLine(String($0))
    }
  }

  /// One commit, with the files it touched and their line counts.
  public func getCommitDetail(_ directory: String, _ hash: String) async throws -> GitCommitDetail? {
    guard isCommitHash(hash) else { return nil }
    let result = try await runShell(
      directory,
      "git show --no-color --format=%H%x1f%an%x1f%at%x1f%s%x1f%D --name-status \(hash);"
        + " printf '\\036';"
        + " git show --no-color --format= --numstat \(hash)",
      timeout: 30
    )
    return parseCommitDetail(result.output)
  }

  /// The patch for one file in one commit, ready for a unified-diff parser.
  public func getCommitFileDiff(
    _ directory: String, _ hash: String, _ path: String
  ) async throws -> String {
    guard isCommitHash(hash) else { return "" }
    let result = try await runShell(
      directory,
      "git show --no-color --format= \(hash) -- \(quoteShellArgument(path))",
      timeout: 30
    )
    return result.output
  }

  /// Working-tree changes, straight from the VCS API.
  public func getVcsStatus(_ directory: String) async throws -> [VcsFileStatus] {
    try await data("/vcs/status", query: at(directory), optional: true)
      .array.compactMap(VcsFileStatus.init(json:))
  }

  /// Per-file patches from the VCS API.
  public func getVcsDiff(
    _ directory: String, mode: VcsDiffMode = .working
  ) async throws -> [VcsDiffFile] {
    var query = at(directory)
    query["mode"] = mode.rawValue
    return try await data("/vcs/diff", query: query, optional: true)
      .array.compactMap(VcsDiffFile.init(json:))
  }

  /**
   Stage everything and commit it.

   v2's VCS API is read-only, so this is `git` through the shell endpoint. The
   commit stages tracked *and* untracked files first, which is what the Git
   screen's "commit all" affordance has always meant.
   */
  public func commitVcs(_ directory: String, message: String) async throws -> VcsCommitResult {
    let staged = try await runShell(directory, "git add -A", timeout: 60)
    if staged.exit != 0 {
      return VcsCommitResult(
        committed: false, message: firstLine(staged.output) ?? "git add failed")
    }

    let result = try await runShell(
      directory,
      "git commit -m \(quoteShellArgument(message)) && git rev-parse HEAD",
      timeout: 60
    )
    if result.exit != 0 {
      return VcsCommitResult(
        committed: false, message: lastLine(result.output) ?? "git commit failed")
    }
    let hash = lastLine(result.output)
    return VcsCommitResult(
      committed: true,
      hash: hash.flatMap { isCommitHash($0) ? $0 : nil },
      message: firstLine(result.output)
    )
  }

  public func pushVcs(_ directory: String) async throws -> VcsPushResult {
    let result = try await runShell(directory, "git push 2>&1", timeout: 120)
    return VcsPushResult(
      pushed: result.exit == 0,
      message: lastLine(result.output) ?? (result.exit == 0 ? "Pushed" : "git push failed")
    )
  }

  // MARK: - Projects

  public func listProjects() async throws -> [Project] {
    try await cachedData("/project", ttl: 3, optional: true)
      .array
      .compactMap(Project.init(json:))
      // v2 keeps a `global` project for anything outside a known root. It is
      // only noise when it has no real directory behind it — when it does, it
      // is the directory the server was started in and belongs on the screen.
      .filter {
        !$0.worktree.isEmpty && $0.worktree != "/" && !isBenchmarkProjectPath($0.worktree)
      }
  }

  private func isBenchmarkProjectPath(_ path: String) -> Bool {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    return normalized.range(
      of: #"^/(?:(?:private/)?tmp|(?:private/)?var/tmp|(?:private/)?var/folders/[^/]+/[^/]+/T)/ocbench-[^/]+-\d+$"#,
      options: .regularExpression
    ) != nil
  }

  public func getCurrentProject(_ directory: String? = nil) async throws -> Project? {
    let value = try await json("/project/current", query: at(directory), optional: true)
    return Project(json: value)
  }

  // MARK: - Sessions

  /// Subagent sessions are filtered here so no caller can forget.
  public func listSessions(_ directory: String? = nil) async throws -> [Session] {
    var query: Query = [:]
    if let directory { query["directory"] = directory }
    query["limit"] = "200"
    query["order"] = "desc"
    return try await cachedData("/session", query: query, ttl: 3)
      .array.compactMap(Session.init(json:)).filter { !isHiddenSession($0) }
  }

  /// One session, including the agent and model it currently runs under.
  public func getSession(_ sessionID: String) async throws -> Session? {
    Session(json: try await data("/session/\(pathEscape(sessionID))", optional: true))
  }

  /// Which sessions are mid-turn right now, keyed by id.
  public func getSessionStatuses() async throws -> [String: String]? {
    let value = try await cachedData("/session/active", ttl: 3, optional: true)
    guard let members = value.object else { return nil }
    return members.mapValues { $0.string ?? $0["type"].string ?? "busy" }
  }

  /**
   Every session working right now, across every project on this server.

   `/api/session/active` answers with ids and nothing else, so each one is
   resolved to a real session — the screen has to name the project and the
   conversation, not an id. A session that has since gone away is dropped rather
   than shown as a blank row.
   */
  public func listActiveSessions() async throws -> [Session] {
    let ids = (try await getSessionStatuses() ?? [:])
      .filter { $0.value != "idle" }
      .map(\.key)
    if ids.isEmpty { return [] }

    return await withTaskGroup(of: Session?.self) { group in
      for id in ids {
        group.addTask { try? await self.getSession(id) }
      }
      var sessions: [Session] = []
      for await session in group {
        if let session { sessions.append(session) }
      }
      return sessions
    }
  }

  /// Every request waiting on a human, across the sessions this server runs.
  public func listPendingPermissions(
    _ directory: String? = nil
  ) async throws -> [PermissionRequest] {
    try await data("/permission/request", query: at(directory), optional: true)
      .array.compactMap(PermissionRequest.init(json:))
  }

  public func createSession(directory: String? = nil, title: String? = nil) async throws -> Session {
    APICache.shared.invalidateAll()
    var body: [String: JSONValue] = [:]
    if let title { body["title"] = .string(title) }
    if let directory { body["location"] = .object(["directory": .string(directory)]) }
    let value = try await data("/session", method: "POST", body: .object(body))
    guard let session = Session(json: value) else {
      throw ApiError(.server, "The server did not return the new session")
    }
    return session
  }

  public func deleteSession(_ id: String) async throws {
    APICache.shared.invalidateAll()
    try await json("/session/\(pathEscape(id))", method: "DELETE")
  }

  // MARK: - Session mutations & reverts

  public func renameSession(_ id: String, title: String, directory: String? = nil) async throws {
    APICache.shared.invalidateAll()
    try await json(
      "/session/\(pathEscape(id))/rename",
      method: "POST",
      query: at(directory),
      body: .object(["title": .string(title)])
    )
  }

  public func forkSession(_ id: String, boundary: JSONValue? = nil, directory: String? = nil) async throws -> Session {
    APICache.shared.invalidateAll()
    let payloadBoundary = boundary ?? .object(["type": .string("through")])
    let value = try await data(
      "/session/\(pathEscape(id))/fork",
      method: "POST",
      query: at(directory),
      body: .object(["boundary": payloadBoundary])
    )
    guard let session = Session(json: value) else {
      throw ApiError(.server, "The server did not return the forked session")
    }
    return session
  }

  public func compactSession(_ id: String, directory: String? = nil) async throws {
    APICache.shared.invalidateAll()
    try await json(
      "/session/\(pathEscape(id))/compact",
      method: "POST",
      query: at(directory)
    )
  }

  public func exportSession(_ id: String, directory: String? = nil) async throws -> SessionExportInfo {
    let value = try await cachedData(
      "/session/\(pathEscape(id))/export",
      query: at(directory),
      ttl: 30
    )
    return SessionExportInfo(json: value)
  }

  public func stageRevert(
    _ id: String, messageID: String, files: Bool? = nil, directory: String? = nil
  ) async throws -> SessionRevertInfo? {
    APICache.shared.invalidateAll()
    var body: [String: JSONValue] = ["messageID": .string(messageID)]
    if let files { body["files"] = .bool(files) }
    let value = try await data(
      "/session/\(pathEscape(id))/revert/stage",
      method: "POST",
      query: at(directory),
      body: .object(body)
    )
    return SessionRevertInfo(json: value)
  }

  public func commitRevert(_ id: String, directory: String? = nil) async throws {
    APICache.shared.invalidateAll()
    try await json(
      "/session/\(pathEscape(id))/revert/commit",
      method: "POST",
      query: at(directory)
    )
  }

  public func clearRevert(_ id: String, directory: String? = nil) async throws {
    APICache.shared.invalidateAll()
    try await json(
      "/session/\(pathEscape(id))/revert/clear",
      method: "POST",
      query: at(directory)
    )
  }

  public func listMessages(_ sessionID: String) async throws -> [MessageWithParts] {
    // The server caps `limit` at 200 and answers 400 above it.
    let value = try await data(
      "/session/\(pathEscape(sessionID))/message",
      query: ["order": "asc", "limit": "200"]
    )
    return value.array.compactMap { toMessage($0, sessionID: sessionID) }
  }

  public func getMessage(
    _ sessionID: String, _ messageID: String
  ) async throws -> MessageWithParts? {
    let value = try await data(
      "/session/\(pathEscape(sessionID))/message/\(pathEscape(messageID))", optional: true)
    return toMessage(value, sessionID: sessionID)
  }

  /**
   Admit a prompt. The reply is the inbox record, not the answer — assistant
   output arrives on the SSE stream.
   */
  public func sendPrompt(
    _ sessionID: String,
    text: String,
    model: ModelRef? = nil,
    agent: String? = nil,
    attachments: [PromptAttachment] = [],
    delivery: InboxDelivery? = nil
  ) async throws {
    let encoded = pathEscape(sessionID)

    // v2 sets the agent and model on the session, not on the prompt. Skipped
    // for a queued prompt: the running turn owns the session's settings until
    // it ends, and changing them underneath it would apply to the wrong turn.
    if delivery == nil {
      if let agent { try await switchAgent(sessionID, agent) }
      if let model { try await switchModel(sessionID, model) }
    }

    var body: [String: JSONValue] = ["text": .string(text)]
    if let delivery { body["delivery"] = .string(delivery.rawValue) }
    if !attachments.isEmpty {
      // The bytes ride along as a data URL — there is no upload step.
      body["files"] = .array(
        attachments.map {
          .object(["uri": .string($0.url), "name": .string($0.filename)])
        })
    }

    try await json(
      "/session/\(encoded)/prompt", method: "POST", body: .object(body), timeout: 60)
  }

  public func abortSession(_ sessionID: String) async throws {
    try await json("/session/\(pathEscape(sessionID))/interrupt", method: "POST")
  }

  // MARK: - Commands

  /// The saved prompts this project can run, which is what `/` offers.
  public func listCommands(_ directory: String? = nil) async throws -> [CommandInfo] {
    try await cachedData("/command", query: at(directory), ttl: 30, optional: true)
      .array.compactMap(CommandInfo.init(json:))
  }

  /**
   Run one. The server expands the template — `$ARGUMENTS` and all — so the
   client sends the name and the rest of the line, never the expansion.
   */
  public func runCommand(
    _ sessionID: String, command: String, arguments: String = "", delivery: InboxDelivery? = nil
  ) async throws {
    var body: [String: JSONValue] = ["command": .string(command)]
    if !arguments.isEmpty { body["arguments"] = .string(arguments) }
    if let delivery { body["delivery"] = .string(delivery.rawValue) }
    try await json(
      "/session/\(pathEscape(sessionID))/command", method: "POST", body: .object(body), timeout: 60)
  }

  // MARK: - Inbox

  /// Prompts admitted while the agent was busy, still waiting their turn.
  public func listInbox(_ sessionID: String) async throws -> [InboxItem] {
    try await data("/session/\(pathEscape(sessionID))/inbox", optional: true)
      .array.compactMap(toInboxItem)
  }

  /// Drop a queued prompt before it runs.
  public func cancelInbox(_ sessionID: String, _ inboxID: String) async throws {
    try await json(
      "/session/\(pathEscape(sessionID))/inbox/\(pathEscape(inboxID))", method: "DELETE")
  }

  /// Move a waiting prompt between "after this turn" and "cut in now".
  public func setInboxDelivery(
    _ sessionID: String, _ inboxID: String, _ delivery: InboxDelivery
  ) async throws {
    try await json(
      "/session/\(pathEscape(sessionID))/inbox/\(pathEscape(inboxID))/\(delivery.rawValue)",
      method: "POST"
    )
  }

  // MARK: - Files

  /**
   One directory level. The tree screen expands lazily, one level per click.

   v2 speaks in paths relative to the location, and answers a directory that
   holds a single subdirectory with that whole run collapsed
   (`packages/mobile/`). Paths are returned absolute so callers keep working in
   one namespace.
   */
  public func listDirectory(_ path: String, directory: String? = nil) async throws -> [FileNode] {
    let root = directory ?? path
    var query = at(root)
    let relative = relativeTo(root, path)
    query["path"] = relative.isEmpty ? "." : relative
    let value = try await cachedData("/fs/list", query: query, ttl: 3, optional: true)
    return value.array.compactMap { entry -> FileNode? in
      guard let raw = entry["path"].string else { return nil }
      let trimmed = trimTrailingSlashes(raw)
      return FileNode(
        name: trimmed.split(separator: "/").last.map(String.init) ?? trimmed,
        path: absoluteIn(root, trimmed),
        type: entry["type"].string == "directory" ? .directory : .file
      )
    }
  }

  /**
   The body of one file.

   Read as bytes rather than through `json`: v2 answers `application/octet-stream`
   with the file verbatim, and a `.json` file would otherwise parse as an
   envelope and come back empty. Only a real `application/json` answer is
   unwrapped, for the builds that wrap it in `{content}`.
   */
  public func readFile(_ path: String, directory: String? = nil) async throws -> FileContent {
    let root = directory ?? ""
    let relative = relativeTo(root, path)
    let encoded = relative.split(separator: "/").map { pathEscape(String($0)) }.joined(
      separator: "/")
    let value = try await cachedData("/fs/read/\(encoded)", query: at(root), ttl: 2, optional: true)
    if value.isNull { return FileContent(content: "") }
    if case .string(let text) = value { return FileContent(content: text) }
    return FileContent(content: unwrapEnvelope(value)["content"].string ?? "")
  }

  /// Working-tree changes, in the client's `FileStatus` shape (repo-relative).
  public func fileStatus(_ directory: String? = nil) async throws -> [FileStatus] {
    guard let directory else { return [] }
    return try await getVcsStatus(directory).map {
      FileStatus(path: $0.file, status: $0.status, added: $0.additions, removed: $0.deletions)
    }
  }

  /// Fuzzy path search, backing the tree's filter field.
  public func findFiles(_ query: String, directory: String? = nil) async throws -> [String] {
    guard let directory, !query.isEmpty else { return [] }
    var params = at(directory)
    params["query"] = query
    params["type"] = "file"
    params["limit"] = "100"
    let value = try await cachedData("/fs/find", query: params, ttl: 5, optional: true)
    return value.array.compactMap { $0["path"].string }.map { absoluteIn(directory, $0) }
  }

  // MARK: - Agents and models

  /// The agents this server can run a session under.
  public func listAgents(_ directory: String? = nil) async throws -> [AgentInfo] {
    try await cachedData("/agent", query: at(directory), ttl: 30, optional: true)
      .array.compactMap(AgentInfo.init(json:)).filter { !$0.hidden }
  }

  /// The models this server can run.
  public func listModels(_ directory: String? = nil) async throws -> [ModelInfo] {
    try await cachedData("/model", query: at(directory), ttl: 30, optional: true)
      .array
      .filter { !$0["disabled"].isTrue }
      .compactMap(ModelInfo.init(json:))
  }

  /**
   What a prompt runs as when the session has not been told otherwise.

   A fresh v2 session carries no agent or model of its own — the server picks at
   prompt time. The composer has to name something, and "whatever the server
   would pick" is the only honest answer, so it is read rather than guessed.
   */
  public func getDefaults(
    _ directory: String? = nil
  ) async throws -> (model: ModelRef?, agent: String?) {
    async let modelTask = (try? data("/model/default", query: at(directory), optional: true)) ?? .null
    async let agentsTask = (try? listAgents(directory)) ?? []
    let (modelJSON, agents) = await (modelTask, agentsTask)

    let modelID = modelJSON["modelID"].string ?? modelJSON["id"].string
    // Primary agents are the ones a session can actually run under; the server
    // lists them in its own order of preference, so the first is the default.
    let agent = agents.first { $0.mode == "primary" } ?? agents.first
    let providerID = modelJSON["providerID"].string
    let model: ModelRef? =
      (modelID != nil && providerID != nil)
      ? ModelRef(providerID: providerID!, modelID: modelID!, variant: modelJSON["variant"].string)
      : nil
    return (model, agent?.id)
  }

  /// Point a session at a different agent.
  public func switchAgent(_ sessionID: String, _ agent: String) async throws {
    try await json(
      "/session/\(pathEscape(sessionID))/agent",
      method: "POST",
      body: .object(["agent": .string(agent)])
    )
  }

  /// Point a session at a different model (and optional variant).
  public func switchModel(_ sessionID: String, _ model: ModelRef) async throws {
    var payload: [String: JSONValue] = [
      "id": .string(model.modelID), "providerID": .string(model.providerID),
    ]
    if let variant = model.variant { payload["variant"] = .string(variant) }
    try await json(
      "/session/\(pathEscape(sessionID))/model",
      method: "POST",
      body: .object(["model": .object(payload)])
    )
  }

  // MARK: - Permissions

  /**
   What this session is blocked on right now.

   Fetched on load as well as watched on the stream: a request raised before the
   screen opened is exactly the case that leaves an agent stuck, so it has to
   survive a reconnect rather than only arriving as an event.
   */
  public func listPermissions(_ sessionID: String) async throws -> [PermissionRequest] {
    try await data("/session/\(pathEscape(sessionID))/permission", optional: true)
      .array.compactMap(PermissionRequest.init(json:))
  }

  /// Answer one request. `always` saves the decision for the rest of the session.
  public func replyPermission(
    _ sessionID: String, _ requestID: String, _ reply: PermissionReply, message: String? = nil
  ) async throws {
    var body: [String: JSONValue] = ["reply": .string(reply.rawValue)]
    if let message { body["message"] = .string(message) }
    try await json(
      "/session/\(pathEscape(sessionID))/permission/\(pathEscape(requestID))/reply",
      method: "POST",
      body: .object(body)
    )
  }

  // MARK: - Questions

  public func listQuestions(_ sessionID: String) async throws -> [QuestionRequest] {
    try await data("/session/\(pathEscape(sessionID))/question", optional: true)
      .array.compactMap(QuestionRequest.init(json:))
  }

  /// One list of chosen labels per question, in the order they were asked.
  public func replyQuestion(
    _ sessionID: String, _ requestID: String, answers: [[String]]
  ) async throws {
    try await json(
      "/session/\(pathEscape(sessionID))/question/\(pathEscape(requestID))/reply",
      method: "POST",
      body: .object(["answers": .array(answers.map { .array($0.map(JSONValue.string)) })])
    )
  }

  public func rejectQuestion(_ sessionID: String, _ requestID: String) async throws {
    try await json(
      "/session/\(pathEscape(sessionID))/question/\(pathEscape(requestID))/reject", method: "POST")
  }

  // MARK: - Forms

  /**
   The forms this session is waiting on. Like permissions, these have to be
   fetched on load and not only watched: a form raised before the screen opened
   is exactly the case that leaves an agent stuck forever.
   */
  public func listForms(_ sessionID: String) async throws -> [FormRequest] {
    try await data("/session/\(pathEscape(sessionID))/form", optional: true)
      .array.compactMap(toFormRequest)
  }

  /// Submit a form. The answer may only carry keys the server considers active.
  public func replyForm(_ sessionID: String, _ formID: String, answer: FormAnswer) async throws {
    try await json(
      "/session/\(pathEscape(sessionID))/form/\(pathEscape(formID))/reply",
      method: "POST",
      body: .object(["answer": .object(answer.mapValues(\.jsonValue))])
    )
  }

  public func cancelForm(_ sessionID: String, _ formID: String) async throws {
    try await json(
      "/session/\(pathEscape(sessionID))/form/\(pathEscape(formID))/cancel", method: "POST")
  }

  // MARK: - MCP

  /**
   The MCP servers this opencode process knows about, with their live state.

   `nil` — not an empty list — when the endpoint is missing, so the UI can say
   "this build cannot do it" rather than "none configured".
   */
  public func listMcp(_ directory: String? = nil) async throws -> [McpServer]? {
    let value = try await cachedData("/mcp", query: at(directory), ttl: 5, optional: true)
    if value.isNull { return nil }
    return value.array.compactMap(McpServer.init(json:)).sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  /**
   Connect or disconnect one MCP server.

   This is the running process's state, not its config file — a disabled server
   comes back on restart. The UI says so rather than implying it is saved
   somewhere.
   */
  public func setMcpEnabled(_ name: String, _ enabled: Bool, directory: String? = nil) async throws {
    try await json(
      "/mcp/\(pathEscape(name))/\(enabled ? "connect" : "disconnect")",
      method: "POST",
      query: at(directory),
      // Connecting a remote server can take a while to hand-shake.
      timeout: 60
    )
  }

  public func addMcp(
    _ name: String,
    type: String = "local",
    command: [String],
    cwd: String? = nil,
    environment: [String: String] = [:],
    disabled: Bool = false,
    codemode: Bool = false,
    directory: String? = nil
  ) async throws {
    var config: [String: JSONValue] = [
      "type": .string(type),
      "command": .array(command.map { .string($0) }),
      "disabled": .bool(disabled),
      "codemode": .bool(codemode),
    ]
    if let cwd {
      config["cwd"] = .string(cwd)
    }
    if !environment.isEmpty {
      var envObj: [String: JSONValue] = [:]
      for (k, v) in environment {
        envObj[k] = .string(v)
      }
      config["environment"] = .object(envObj)
    }

    let payload: JSONValue = .object([
      "config": .object(config)
    ])

    let req = McpRequestBuilder.addRequest(name: name)
    try await json(
      req.path,
      method: req.method,
      query: at(directory),
      body: payload
    )
    APICache.shared.invalidateAll()
  }

  public func removeMcp(_ name: String, directory: String? = nil) async throws {
    APICache.shared.invalidateAll()
    let req = McpRequestBuilder.removeRequest(name: name)
    try await json(
      req.path,
      method: req.method,
      query: at(directory)
    )
  }

  public func listMcpResources(directory: String? = nil) async throws -> McpResourceCatalog? {
    let value = try await cachedData("/mcp/resource", query: at(directory), ttl: 10, optional: true)
    if value.isNull { return nil }
    return McpResourceCatalog(json: value)
  }

  // MARK: - Saved Permissions

  public func listSavedPermissions(directory: String? = nil) async throws -> [SavedPermission] {
    try await cachedData("/permission/saved", query: at(directory), ttl: 10, optional: true)
      .array.compactMap(SavedPermission.init(json:))
  }

  public func removeSavedPermission(_ id: String, directory: String? = nil) async throws {
    APICache.shared.invalidateAll()
    try await json(
      "/permission/saved/\(pathEscape(id))",
      method: "DELETE",
      query: at(directory)
    )
  }

  // MARK: - Skills

  public func listSkills(directory: String? = nil) async throws -> [SkillInfo] {
    try await cachedData("/skill", query: at(directory), ttl: 30, optional: true)
      .array.compactMap(SkillInfo.init(json:))
  }

  public func activateSkill(sessionID: String, skillID: String, directory: String? = nil) async throws {
    APICache.shared.invalidateAll()
    try await json(
      "/session/\(pathEscape(sessionID))/skill",
      method: "POST",
      query: at(directory),
      body: .object(["skill": .string(skillID)])
    )
  }

  // MARK: - References

  public func listReferences(directory: String? = nil) async throws -> [ReferenceInfo] {
    try await cachedData("/reference", query: at(directory), ttl: 30, optional: true)
      .array.compactMap(ReferenceInfo.init(json:))
  }

  // MARK: - Providers

  public func listProviders(directory: String? = nil) async throws -> [ProviderInfo] {
    try await cachedData("/provider", query: at(directory), ttl: 60, optional: true)
      .array.compactMap(ProviderInfo.init(json:))
  }

  public func getProvider(_ id: String, directory: String? = nil) async throws -> ProviderInfo? {
    let value = try await cachedData(
      "/provider/\(pathEscape(id))", query: at(directory), ttl: 60, optional: true)
    if value.isNull { return nil }
    return ProviderInfo(json: value)
  }

  // MARK: - Plugins, Integrations, PTY, Worktrees

  public func listPlugins(_ directory: String? = nil) async throws -> [PluginInfo]? {
    let value = try await cachedData("/plugin", query: at(directory), ttl: 10, optional: true)
    if value.isNull { return nil }
    return value.array.compactMap(PluginInfo.init(json:))
  }

  public func listIntegrations(_ directory: String? = nil) async throws -> [IntegrationInfo]? {
    let value = try await cachedData("/integration", query: at(directory), ttl: 30, optional: true)
    if value.isNull { return nil }
    return value.array.compactMap(IntegrationInfo.init(json:))
  }

  public func listPtySessions(_ directory: String? = nil) async throws -> [PtySession] {
    let value = try await cachedData("/pty", query: at(directory), ttl: 5, optional: true)
    if value.isNull { return [] }
    return value.array.compactMap(PtySession.init(json:))
  }

  public func listWorktrees(projectID: String) async throws -> [Worktree]? {
    let value = try await json(WorktreeRequestBuilder.listPath(projectID: projectID), optional: true)
    return WorktreeRequestBuilder.parseListResponse(value)
  }

  public func createWorktree(
    projectID: String,
    strategy: String = "copy",
    from: String? = nil,
    directory: String,
    name: String? = nil
  ) async throws {
    let path = WorktreeRequestBuilder.createPath(projectID: projectID)
    let body = WorktreeRequestBuilder.createBody(strategy: strategy, from: from, directory: directory, name: name)

    do {
      let value = try await json(
        path,
        method: "POST",
        body: body
      )

      if let error = WorktreeRequestBuilder.error(from: value) {
        throw error
      }
    } catch let error as ApiError {
      if error.kind == .server, let status = error.status, status >= 400 {
        throw ApiError(.server, error.message, status: status, url: error.url)
      }
      throw error
    }
  }
}

enum WorktreeRequestBuilder {
  static func listPath(projectID: String) -> String {
    "/worktree/\(pathEscape(projectID))"
  }

  static func parseListResponse(_ value: JSONValue) -> [Worktree]? {
    if value.isNull { return nil }
    guard case .array(let items) = value else { return nil }
    return items.compactMap(Worktree.init(json:))
  }

  static func createPath(projectID: String) -> String {
    "/worktree/\(pathEscape(projectID))"
  }

  static func createBody(
    strategy: String = "copy",
    from: String? = nil,
    directory: String,
    name: String? = nil
  ) -> JSONValue {
    var bodyObj: [String: JSONValue] = [
      "strategy": .string(strategy),
      "directory": .string(directory)
    ]
    if let from, !from.isEmpty {
      bodyObj["from"] = .string(from)
    }
    if let name, !name.isEmpty {
      bodyObj["name"] = .string(name)
    }
    return .object(bodyObj)
  }

  static func error(from value: JSONValue) -> ApiError? {
    guard value["name"].string == "WorktreeError" else { return nil }
    let message = value["data"]["message"].string ?? value["message"].string ?? "Worktree creation failed"
    return ApiError(.server, message)
  }
}

enum McpRequestBuilder {
  static func addRequest(name: String) -> (path: String, method: String) {
    (path: "/mcp/\(pathEscape(name))", method: "PUT")
  }

  static func removeRequest(name: String) -> (path: String, method: String) {
    (path: "/mcp/\(pathEscape(name))", method: "DELETE")
  }
}

// MARK: - Query

/// Query parameters, in the order-insensitive form v2 expects.
typealias Query = [String: String]

extension Query {
  /// v2 scopes most routes with `location[directory]`; the brackets have to be
  /// percent-encoded or the router never sees the parameter.
  func encoded() -> String {
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    return
      self
      .filter { !$0.value.isEmpty }
      .sorted { $0.key < $1.key }
      .map { key, value in
        let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
        let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return "\(k)=\(v)"
      }
      .joined(separator: "&")
  }
}

/**
 Strip v2's `{data}` / `{location, data}` envelope.

 A body that is not an envelope passes straight through, which is how
 `/api/project` — a bare array — works with the same helper. An envelope whose
 `data` is itself an object with a `data` key is left alone: only the outer one
 is ours.
 */
func unwrapEnvelope(_ value: JSONValue) -> JSONValue {
  if case .object(let members) = value, let inner = members["data"] { return inner }
  return value
}

/// The `location[directory]=…` scoping v2 puts on most routes.
func at(_ directory: String?) -> Query {
  guard let directory, !directory.isEmpty else { return [:] }
  return ["location[directory]": directory]
}

func pathEscape(_ value: String) -> String {
  let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
  return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

// MARK: - URLs

/**
 Accept what a user would actually type. `192.168.1.24:4096` is a host and port,
 not a path, so a missing scheme is filled in before parsing. Trailing paths are
 kept, since the server may sit behind a reverse proxy on a sub-path.
 */
public func normaliseBaseUrl(_ input: String) -> String {
  var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
  if value.isEmpty { return value }
  let lower = value.lowercased()
  if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") { value = "http://" + value }
  return trimTrailingSlashes(value)
}

/// True when the string could address a server. Drives the Connect button.
public func isValidServerUrl(_ input: String) -> Bool {
  let value = normaliseBaseUrl(input)
  guard !value.isEmpty, let components = URLComponents(string: value) else { return false }
  return !(components.host ?? "").isEmpty
}

/// `192.168.1.24:4096` — the address without scheme, for display.
public func hostOf(_ rawURL: String) -> String {
  guard let components = URLComponents(string: rawURL), let host = components.host else {
    return rawURL
  }
  return components.port.map { "\(host):\($0)" } ?? host
}

// MARK: - Paths

func trimTrailingSlashes(_ value: String) -> String {
  var value = value
  while value.count > 1 && value.hasSuffix("/") { value.removeLast() }
  if value == "/" { return value }
  return value
}

/// v2 speaks in paths relative to the location; the app speaks in absolute ones.
public func relativeTo(_ root: String, _ path: String) -> String {
  let base = root.hasSuffix("/") ? trimTrailingSlashes(root) : root
  let value = path.hasSuffix("/") ? trimTrailingSlashes(path) : path
  if base.isEmpty || base == "/" || value == base { return base == value ? "" : dropLeadingSlashes(value) }
  if value.hasPrefix(base + "/") { return String(value.dropFirst(base.count + 1)) }
  return dropLeadingSlashes(value)
}

public func absoluteIn(_ root: String, _ path: String) -> String {
  if path.hasPrefix("/") { return path }
  let base = root.hasSuffix("/") ? trimTrailingSlashes(root) : root
  if base.isEmpty { return path }
  if base == "/" { return "/" + path }
  return base + "/" + path
}

private func dropLeadingSlashes(_ value: String) -> String {
  var value = value
  while value.hasPrefix("/") { value.removeFirst() }
  return value
}

// MARK: - Text helpers

private func errorBody(_ data: Data, status: Int) -> String {
  let text = String(decoding: data, as: UTF8.self)
  if text.isEmpty { return "HTTP \(status)" }
  if let json = try? JSONValue.parse(data) {
    if let message = json["data"]["message"].string ?? json["message"].string
      ?? json["error"].string
    {
      return message
    }
  }
  return String(text.prefix(300))
}

func firstLine(_ value: String) -> String? {
  value.split(separator: "\n")
    .map { $0.trimmingCharacters(in: .whitespaces) }
    .first { !$0.isEmpty }
}

func lastLine(_ value: String) -> String? {
  value.split(separator: "\n")
    .map { $0.trimmingCharacters(in: .whitespaces) }
    .last { !$0.isEmpty }
}

/// Single-quote for `sh`, which only has to survive an embedded quote.
public func quoteShellArgument(_ value: String) -> String {
  "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

public func isCommitHash(_ value: String) -> Bool {
  let count = value.count
  guard count >= 4, count <= 40 else { return false }
  return value.allSatisfy(\.isHexDigit)
}

/**
 The server user's home, mined from the config document paths so absolute paths
 can be shown as `~/dev/x`. v2 has no endpoint that reports it.
 */
func homeFromConfig(_ entries: [ConfigEntry], cwd: String?) -> String? {
  let markers = ["/.claude", "/.agents", "/.config/opencode"]
  for entry in entries {
    guard let path = entry.path else { continue }
    for marker in markers {
      guard let range = path.range(of: marker) else { continue }
      let after = path[range.upperBound...]
      guard after.isEmpty || after.hasPrefix("/") else { continue }
      let home = String(path[path.startIndex..<range.lowerBound])
      if !home.isEmpty { return home }
    }
  }
  // Last resort: the first two segments of the working directory.
  guard let cwd else { return nil }
  let parts = cwd.split(separator: "/", omittingEmptySubsequences: true)
  if parts.count >= 2, parts[0] == "Users" || parts[0] == "home" {
    return "/\(parts[0])/\(parts[1])"
  }
  return nil
}

// MARK: - git log parsing

private let unitSeparator = "\u{1f}"
private let recordSeparator = "\u{1e}"

private func commitFromLogLine(_ line: String) -> GitCommit? {
  let fields = line.components(separatedBy: unitSeparator)
  guard fields.count >= 4 else { return nil }
  let hash = fields[0]
  guard hash.count >= 7, hash.count <= 40, hash.allSatisfy(\.isHexDigit) else { return nil }
  return GitCommit(
    hash: hash,
    shortHash: String(hash.prefix(7)),
    subject: fields[3],
    author: fields[1],
    date: (Int(fields[2]) ?? 0) * 1000,
    refs: fields.count > 4
      ? fields[4].components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty } : []
  )
}

private let statusLetters: [Character: FileChangeStatus] = [
  "A": .added, "D": .deleted, "M": .modified, "R": .modified, "C": .modified, "T": .modified,
]

/**
 `git show --name-status` and `--numstat` cannot be asked for together — the
 last flag wins — so the command runs both and separates them with a record
 separator. The first section carries the header and each file's status, the
 second the line counts for the same paths.
 */
func parseCommitDetail(_ output: String) -> GitCommitDetail? {
  let sections = output.components(separatedBy: recordSeparator)
  let statusSection = sections.first ?? ""
  let numstatSection = sections.count > 1 ? sections[1] : ""

  let lines = statusSection.components(separatedBy: "\n")
  guard let header = lines.first(where: { $0.contains(unitSeparator) }),
    let commit = commitFromLogLine(header)
  else { return nil }

  var counts: [String: (added: Int, removed: Int)] = [:]
  for line in numstatSection.components(separatedBy: "\n") {
    let fields = line.components(separatedBy: "\t")
    guard fields.count >= 3 else { continue }
    let path = fields[2].trimmingCharacters(in: .whitespaces)
    if path.isEmpty { continue }
    // `-` is what numstat prints for a binary file.
    counts[path] = (Int(fields[0]) ?? 0, Int(fields[1]) ?? 0)
  }

  var files: [GitCommitFile] = []
  for line in lines where !line.contains(unitSeparator) {
    let fields = line.components(separatedBy: "\t")
    guard fields.count >= 2 else { continue }
    // A rename reports the old path and the new one; the new one is the file.
    let path = (fields.count > 2 && !fields[2].isEmpty ? fields[2] : fields[1])
      .trimmingCharacters(in: .whitespaces)
    guard !path.isEmpty, let letter = fields[0].trimmingCharacters(in: .whitespaces).first,
      let status = statusLetters[Character(letter.uppercased())]
    else { continue }
    let count = counts[path] ?? (0, 0)
    files.append(
      GitCommitFile(path: path, status: status, added: count.added, removed: count.removed))
  }

  return GitCommitDetail(commit: commit, files: files)
}
