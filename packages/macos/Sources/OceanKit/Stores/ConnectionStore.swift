import Foundation
import Observation

/// Steps the handshake screen renders, in the order it performs them.
public enum HandshakeStepID: String, Codable, Hashable, Sendable, CaseIterable {
  case reach
  case auth
  case version
  case repo
}

public struct HandshakeStep: Identifiable, Hashable, Sendable {
  public enum State: String, Hashable, Sendable {
    case pending
    case running
    case ok
    case failed
    case skipped
  }

  public var id: HandshakeStepID
  public var label: String
  public var state: State
  /// Right-aligned detail: latency, status code, "ok".
  public var detail: String?

  public init(id: HandshakeStepID, label: String, state: State = .pending, detail: String? = nil) {
    self.id = id
    self.label = label
    self.state = state
    self.detail = detail
  }
}

public enum ConnectionStatus: String, Hashable, Sendable {
  case disconnected
  case connecting
  case connected
  case error
}

/**
 Hands back the slot a listener occupies when it goes away.

 Dropping it is enough — a screen can hold one in a `@State` and never think
 about it again — but `cancel()` is there for anything that unsubscribes early.
 */
public final class EventSubscription: @unchecked Sendable {
  private let id: UUID
  private weak var store: ConnectionStore?

  init(id: UUID, store: ConnectionStore) {
    self.id = id
    self.store = store
  }

  @MainActor
  public func cancel() {
    store?.removeListener(id)
    store = nil
  }

  deinit {
    guard let store else { return }
    let id = self.id
    Task { @MainActor in store.removeListener(id) }
  }
}

/**
 The one connected server, and how we got there.

 A singleton rather than something injected per screen: there is exactly one
 connection for the life of the app, navigation reads it before any view
 appears, and the event stream has to outlive every screen that subscribes to
 it. Everything else in the app is handed `client` by this store.
 */
@Observable
@MainActor
public final class ConnectionStore {
  public static let shared = ConnectionStore()

  private static let recentsKey = "ocean.macos.recents"
  /// Address of the remembered server to re-attach to on launch.
  private static let lastServerKey = "ocean.macos.lastServer"
  private static let maxRecents = 6

  public private(set) var client: OpenCodeClient?
  public private(set) var status: ConnectionStatus = .disconnected
  public private(set) var error: String?
  /// Set when the failure was specifically a credential rejection.
  public private(set) var authFailed = false
  public private(set) var appInfo: AppInfo?
  public private(set) var serverVersion: String?
  public private(set) var username: String?
  public private(set) var recents: [RecentServer] = []
  public private(set) var steps: [HandshakeStep] = ConnectionStore.freshSteps()
  /// Live status of the SSE stream, shown as the dot in screen headers.
  public private(set) var streamConnected = false
  /// The one stream, for callers that would rather have an `AsyncStream` than
  /// a callback. Never construct a second one.
  public private(set) var stream: EventStream?

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let keychain: Keychain
  @ObservationIgnored private var handshake: Task<Bool, Never>?
  @ObservationIgnored private var eventsTask: Task<Void, Never>?
  @ObservationIgnored private var statusTask: Task<Void, Never>?
  /// Fan-out for server events. Screens add a listener on appear, drop the
  /// subscription on disappear.
  @ObservationIgnored private var listeners: [UUID: (ServerEvent) -> Void] = [:]
  /// The stream has been open at least once, so the next open is a reconnect.
  @ObservationIgnored private var streamOpenedOnce = false

  public init(defaults: UserDefaults = .standard, keychain: Keychain = .shared) {
    self.defaults = defaults
    self.keychain = keychain
    recents = loadRecents()
  }

  // MARK: - Derived

  public var isConnected: Bool { status == .connected && client != nil }

  /// Directory the server is rooted at — the worktree if there is one, else cwd.
  public var workingDirectory: String? { appInfo?.path?.root ?? appInfo?.path?.cwd }

  public var isGitRepo: Bool { appInfo?.git == true }

  /// `192.168.1.24:4096 · opencode`, the header's server context line.
  public var serverLabel: String {
    guard let client else { return "" }
    guard let username, !username.isEmpty else { return client.displayHost }
    return "\(client.displayHost) · \(username)"
  }

  /**
   Is *this* directory a git repository?

   `appInfo.git` answers for the server's current project, which is not
   necessarily the directory being viewed — on a multi-project server the
   current project can be the global root while every listed project is a repo.
   The authoritative answer for a directory is `GET /vcs`, so screens that gate
   the Git tab on it resolve it per-directory.
   */
  public func isDirectoryGitRepo(_ directory: String) async -> Bool {
    guard let client else { return false }
    guard let info = try? await client.getVcsInfo(directory) else { return false }
    return info.branch != nil || info.defaultBranch != nil
  }

  /**
   The connected client, for code that has already established there is one.
   Throws rather than returning nil so callers aren't forced into a null check
   behind navigation that already guarantees a connection.
   */
  public func requireClient() throws -> OpenCodeClient {
    guard let client else { throw ApiError(.network, "Not connected to a server") }
    return client
  }

  // MARK: - Connect

  /**
   Run the handshake against `credentials`.

   Resolves true once the server has answered and identified itself. The repo
   check is deliberately not fatal — a non-repo directory is a supported state,
   it just disables the Git tab.
   */
  @discardableResult
  public func connect(_ credentials: ServerCredentials) async -> Bool {
    cancelHandshake()
    teardownStream()

    status = .connecting
    error = nil
    authFailed = false
    appInfo = nil
    serverVersion = nil
    steps = Self.freshSteps()
    username = credentials.useBasicAuth ? credentials.username : nil

    let task = Task { @MainActor in await self.runHandshake(credentials) }
    handshake = task
    let connected = await task.value
    if handshake == task { handshake = nil }
    return connected
  }

  private func runHandshake(_ credentials: ServerCredentials) async -> Bool {
    let next = OpenCodeClient(credentials: credentials)
    let startedAt = Date()

    // 1 + 2: reaching the server and being accepted by it are the same request.
    // A 401 means we reached it but the credentials were wrong, so the first
    // step still succeeded — the UI shows exactly where the failure was.
    set(.reach, .running)
    set(.auth, .running)

    let info: AppInfo
    do {
      info = try await next.getAppInfo()
    } catch is CancellationError {
      status = .disconnected
      return false
    } catch let failure as ApiError {
      switch failure.kind {
      case .aborted:
        status = .disconnected
        return false
      case .auth:
        set(.reach, .ok, latency(since: startedAt))
        set(.auth, .failed, String(failure.status ?? 401))
        authFailed = true
      case .notfound:
        // Something answered, it just wasn't the v2 API — a v1 server, a web UI,
        // or a proxy in front of neither.
        set(.reach, .ok, latency(since: startedAt))
        set(.auth, .failed, "no v2 API")
      default:
        set(.reach, .failed)
        set(.auth, .pending)
      }
      status = .error
      error = failure.userMessage
      return false
    } catch {
      set(.reach, .failed)
      set(.auth, .pending)
      status = .error
      self.error = toUserMessage(error)
      return false
    }

    set(.reach, .ok, latency(since: startedAt))
    set(.auth, .ok, "200")
    appInfo = info

    // 3: version — `GET /api/health` reports it, so this is a real answer.
    set(.version, .running)
    serverVersion = info.version
    set(.version, info.version == nil ? .skipped : .ok, info.version ?? "not reported")

    // 4: repository detection decides whether the Git tab is live.
    set(.repo, .running)
    set(.repo, .ok, info.git == true ? "repository" : "no repository")

    if Task.isCancelled {
      status = .disconnected
      return false
    }

    client = next
    status = .connected
    rememberServer(credentials, info)
    saveServer(credentials)
    connectStream(next)
    return true
  }

  /// Abandon an in-flight handshake — the Cancel button on the handshake screen.
  public func cancelHandshake() {
    handshake?.cancel()
    handshake = nil
    if status == .connecting { status = .disconnected }
  }

  public func disconnect() {
    cancelHandshake()
    teardownStream()
    client = nil
    status = .disconnected
    appInfo = nil
    serverVersion = nil
    username = nil
    error = nil
    authFailed = false
    steps = Self.freshSteps()
    // Detaching is deliberate, so the next launch must not silently reconnect.
    // The saved credentials stay, so re-attaching from the recents list is one
    // click.
    defaults.removeObject(forKey: Self.lastServerKey)
  }

  /**
   Re-attach to the server the user asked this Mac to remember.

   The Vue client also restores a per-tab session; there are no tabs here, so a
   cold launch either has a remembered server or shows the connect screen.
   */
  @discardableResult
  public func restoreSession() async -> Bool {
    guard let url = defaults.string(forKey: Self.lastServerKey),
      let credentials = keychain.load(url)
    else { return false }
    return await connect(credentials)
  }

  // MARK: - Remembered servers

  /// The stored credentials for an address, password included.
  public func savedServer(_ url: String) -> ServerCredentials? {
    keychain.load(url)
  }

  /**
   Connect straight to a server in the recents list — the "switch server" path.

   False when the address is only a recent: recents carry no password, so the
   caller has to route through the connect form. A server the user asked to be
   remembered reconnects outright.
   */
  @discardableResult
  public func switchServer(_ url: String) async -> Bool {
    guard let stored = keychain.load(url) else { return false }
    return await connect(stored)
  }

  public func forgetServer(_ url: String) {
    let url = normaliseBaseUrl(url)
    recents.removeAll { normaliseBaseUrl($0.url) == url }
    persistRecents()
    // Forgetting an address has to take its saved password with it.
    keychain.forget(url)
    if normaliseBaseUrl(defaults.string(forKey: Self.lastServerKey) ?? "") == url {
      defaults.removeObject(forKey: Self.lastServerKey)
    }
  }

  /**
   Store or drop this address depending on `remember`. Opting out has to erase
   what a previous opt-in wrote, or the toggle would only ever add.
   */
  private func saveServer(_ credentials: ServerCredentials) {
    let url = normaliseBaseUrl(credentials.url)
    guard !url.isEmpty else { return }
    if credentials.remember {
      var stored = credentials
      stored.remember = true
      try? keychain.save(stored)
      defaults.set(url, forKey: Self.lastServerKey)
    } else {
      keychain.forget(url)
      if normaliseBaseUrl(defaults.string(forKey: Self.lastServerKey) ?? "") == url {
        defaults.removeObject(forKey: Self.lastServerKey)
      }
    }
  }

  // MARK: - Recents

  /// Records the address and username only — never the password.
  private func rememberServer(_ credentials: ServerCredentials, _ info: AppInfo) {
    let url = normaliseBaseUrl(credentials.url)
    let entry = RecentServer(
      url: url,
      username: credentials.useBasicAuth ? credentials.username : nil,
      useBasicAuth: credentials.useBasicAuth,
      lastConnected: Int(Date().timeIntervalSince1970 * 1000),
      lastDirectory: info.path?.root ?? info.path?.cwd
    )
    recents = ([entry] + recents.filter { normaliseBaseUrl($0.url) != url }).prefix(Self.maxRecents)
      .map { $0 }
    persistRecents()
  }

  private func loadRecents() -> [RecentServer] {
    guard let body = defaults.data(forKey: Self.recentsKey),
      let parsed = try? JSONDecoder().decode([RecentServer].self, from: body)
    else { return [] }
    return Array(parsed.prefix(Self.maxRecents))
  }

  private func persistRecents() {
    guard let body = try? JSONEncoder().encode(recents) else { return }
    defaults.set(body, forKey: Self.recentsKey)
  }

  // MARK: - Event stream

  /**
   Listen to server events.

   The stream is global — every location and every session on the server — so a
   screen filters on `directory` and `sessionID` rather than opening one of its
   own.
   */
  public func onServerEvent(_ listener: @escaping (ServerEvent) -> Void) -> EventSubscription {
    let id = UUID()
    listeners[id] = listener
    return EventSubscription(id: id, store: self)
  }

  func removeListener(_ id: UUID) {
    listeners.removeValue(forKey: id)
  }

  private func connectStream(_ client: OpenCodeClient) {
    let stream = EventStream(client: client)
    self.stream = stream
    streamOpenedOnce = false

    eventsTask = Task { [weak self] in
      for await event in await stream.events() { self?.deliver(event) }
    }
    statusTask = Task { [weak self] in
      for await status in await stream.statuses() { self?.streamChanged(to: status) }
    }
    Task { await stream.start() }
  }

  private func teardownStream() {
    eventsTask?.cancel()
    eventsTask = nil
    statusTask?.cancel()
    statusTask = nil
    if let stream {
      Task { await stream.stop() }
    }
    stream = nil
    streamConnected = false
    streamOpenedOnce = false
  }

  /// Internal rather than private so the tests can fan an event out without a
  /// socket; nothing outside `OceanKit` can inject one.
  func deliver(_ event: ServerEvent) {
    for listener in listeners.values {
      // One screen's handler throwing must not stop the others; Swift closures
      // cannot throw here, so this is only about not short-circuiting.
      listener(event)
    }
  }

  private func streamChanged(to next: EventStream.Status) {
    streamConnected = next == .connected

    if next == .connected {
      if streamOpenedOnce {
        // Screens reload their own state on this: everything that happened
        // while the stream was down was never delivered.
        deliver(ServerEvent(type: "stream.reconnected"))
      }
      streamOpenedOnce = true
    }

    if next == .unauthorised {
      authFailed = true
      status = .error
      error = ApiError(.auth, "Authentication failed", status: 401).userMessage
    }
  }

  // MARK: - Handshake bookkeeping

  private static func freshSteps() -> [HandshakeStep] {
    [
      HandshakeStep(id: .reach, label: "Reach server"),
      HandshakeStep(id: .auth, label: "Authenticate"),
      HandshakeStep(id: .version, label: "Version"),
      HandshakeStep(id: .repo, label: "Detect repository"),
    ]
  }

  private func set(_ id: HandshakeStepID, _ state: HandshakeStep.State, _ detail: String? = nil) {
    guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
    steps[index].state = state
    if let detail { steps[index].detail = detail }
  }

  private func latency(since start: Date) -> String {
    "\(Int((Date().timeIntervalSince(start) * 1000).rounded()))ms"
  }
}
