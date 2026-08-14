import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/**
 Cuts an SSE byte stream into `data:` payloads.

 Pure and incremental so it can be tested without a socket. Frames end at the
 blank line between them, `\r\n` and a lone `\r` fold to `\n` even when the pair
 is split across two chunks, and comment lines — the server's `: heartbeat` —
 fall away because only `data:` lines are collected.
 */
public struct SSEParser: Sendable {
  private var buffer: [UInt8] = []
  /// Set when a chunk ended on `\r`, so the `\n` that opens the next one is not
  /// counted as a second line break.
  private var pendingCR = false

  public init() {}

  /// The payloads completed by this chunk, in order.
  public mutating func consume(_ chunk: some Sequence<UInt8>) -> [String] {
    var payloads: [String] = []
    for raw in chunk {
      var byte = raw
      if pendingCR {
        pendingCR = false
        if byte == 0x0A { continue }
      }
      if byte == 0x0D {
        pendingCR = true
        byte = 0x0A
      }
      buffer.append(byte)
      guard byte == 0x0A, buffer.count >= 2, buffer[buffer.count - 2] == 0x0A else { continue }
      buffer.removeLast(2)
      if let payload = Self.payload(of: buffer) { payloads.append(payload) }
      buffer.removeAll(keepingCapacity: true)
    }
    return payloads
  }

  /// Whatever is left when the connection ends without a closing blank line.
  public mutating func flush() -> String? {
    defer {
      buffer.removeAll(keepingCapacity: false)
      pendingCR = false
    }
    return Self.payload(of: buffer)
  }

  private static func payload(of frame: [UInt8]) -> String? {
    guard !frame.isEmpty else { return nil }
    let lines = String(decoding: frame, as: UTF8.self).split(
      separator: "\n", omittingEmptySubsequences: false)
    let data = lines
      .filter { $0.hasPrefix("data:") }
      .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
      .joined(separator: "\n")
    return data.isEmpty ? nil : data
  }
}

/**
 The server's one SSE stream.

 v2 emits a single `/api/event` stream carrying every location and every
 session, so exactly one of these exists for the life of the app and screens
 filter what they care about. `events()` hands out an independent `AsyncStream`
 per consumer — the Swift shape of the Vue client's `onServerEvent` fan-out — so
 opening a second connection is never necessary.

 `URLSession.bytes` rather than any ready-made `EventSource`: basic auth is
 mandatory on every v2 server, and the header has to go out with the request.
 */
public actor EventStream {
  public enum Status: String, Sendable, Hashable {
    case disconnected
    case connecting
    case connected
    /// Credentials were rejected. Retrying with the same ones cannot help, so
    /// the stream stays down until the store connects again.
    case unauthorised
  }

  private let client: OpenCodeClient
  private let session: URLSession

  private var runner: Task<Void, Never>?
  private var consumers: [UUID: AsyncStream<ServerEvent>.Continuation] = [:]
  private var watchers: [UUID: AsyncStream<Status>.Continuation] = [:]
  /// Whether the current attempt got as far as an open stream, which is what
  /// earns a reset of the backoff.
  private var didOpen = false

  public private(set) var status: Status = .disconnected
  /// Why the last attempt failed, for a "reconnecting" strip.
  public private(set) var lastError: ApiError?

  public var isConnected: Bool { status == .connected }

  public init(client: OpenCodeClient) {
    self.client = client
    let configuration = URLSessionConfiguration.default
    // A stream that is quiet between heartbeats must not be reaped.
    configuration.timeoutIntervalForRequest = 3600
    configuration.timeoutIntervalForResource = 86_400
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    session = URLSession(configuration: configuration)
  }

  deinit {
    runner?.cancel()
    for continuation in consumers.values { continuation.finish() }
    for continuation in watchers.values { continuation.finish() }
  }

  // MARK: - Consumers

  /// One independent stream per caller; dropping it unsubscribes.
  public func events() -> AsyncStream<ServerEvent> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<ServerEvent>.makeStream(
      bufferingPolicy: .bufferingNewest(1024))
    consumers[id] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { await self?.drop(consumer: id) }
    }
    return stream
  }

  /// Connection state, starting with whatever it is right now.
  public func statuses() -> AsyncStream<Status> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<Status>.makeStream(bufferingPolicy: .bufferingNewest(8))
    watchers[id] = continuation
    continuation.yield(status)
    continuation.onTermination = { [weak self] _ in
      Task { await self?.drop(watcher: id) }
    }
    return stream
  }

  private func drop(consumer id: UUID) {
    consumers.removeValue(forKey: id)
  }

  private func drop(watcher id: UUID) {
    watchers.removeValue(forKey: id)
  }

  // MARK: - Lifecycle

  public func start() {
    guard runner == nil else { return }
    runner = Task { await self.run() }
  }

  public func stop() {
    runner?.cancel()
    runner = nil
    session.invalidateAndCancel()
    set(status: .disconnected)
    for continuation in consumers.values { continuation.finish() }
    consumers.removeAll()
    for continuation in watchers.values { continuation.finish() }
    watchers.removeAll()
  }

  private func set(status newStatus: Status) {
    guard status != newStatus else { return }
    status = newStatus
    for continuation in watchers.values { continuation.yield(newStatus) }
  }

  private func emit(_ event: ServerEvent) {
    for continuation in consumers.values { continuation.yield(event) }
  }

  private func run() async {
    var delay: UInt64 = 1_000_000_000
    while !Task.isCancelled {
      didOpen = false
      do {
        try await connect()
      } catch is CancellationError {
        set(status: .disconnected)
        return
      } catch {
        let failure = error as? ApiError ?? ApiError(.network, toUserMessage(error))
        lastError = failure
        // Retrying with credentials the server has already refused only burns
        // attempts; the store has to connect again with new ones.
        if failure.kind == .auth {
          set(status: .unauthorised)
          return
        }
      }
      set(status: .disconnected)
      if Task.isCancelled { return }

      // A successful open resets the backoff — a laptop changing networks is
      // routine and should not creep towards the cap.
      if didOpen { delay = 1_000_000_000 }
      do { try await Task.sleep(nanoseconds: delay) } catch { return }
      delay = min(delay * 2, 15_000_000_000)
    }
  }

  private func connect() async throws {
    set(status: .connecting)
    let request = try client.eventRequest()

    let bytes: URLSession.AsyncBytes
    let response: URLResponse
    do {
      (bytes, response) = try await session.bytes(for: request)
    } catch let error as URLError {
      if Task.isCancelled { throw CancellationError() }
      throw apiError(from: error, url: request.url?.absoluteString)
    }

    guard let http = response as? HTTPURLResponse else {
      throw ApiError(.network, "The event stream did not answer with HTTP")
    }
    if http.statusCode == 401 || http.statusCode == 403 {
      throw ApiError(.auth, "Event stream failed (\(http.statusCode))", status: http.statusCode)
    }
    let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
    guard http.statusCode < 400, contentType.contains("text/event-stream") else {
      throw ApiError(.network, "The server has no v2 event stream at /api/event")
    }

    didOpen = true
    lastError = nil
    set(status: .connected)

    var parser = SSEParser()
    for try await byte in bytes {
      for payload in parser.consume(CollectionOfOne(byte)) { deliver(payload) }
      if Task.isCancelled { throw CancellationError() }
    }
    if let tail = parser.flush() { deliver(tail) }
    throw ApiError(.network, "Event stream closed")
  }

  private func deliver(_ payload: String) {
    guard let json = try? JSONValue.parse(Data(payload.utf8)),
      let event = normaliseServerEvent(json)
    else { return }  // a malformed frame is not worth tearing the stream down for
    emit(event)
  }
}
