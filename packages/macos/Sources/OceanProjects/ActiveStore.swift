import Foundation
import Observation
import OceanKit

public struct ActiveRow: Identifiable, Sendable, Hashable {
  public var session: Session
  public var directory: String
  public var project: String
  public var request: PermissionRequest?
  public var started: Int?

  public var id: String { session.id }

  public init(
    session: Session,
    directory: String,
    project: String,
    request: PermissionRequest? = nil,
    started: Int? = nil
  ) {
    self.session = session
    self.directory = directory
    self.project = project
    self.request = request
    self.started = started
  }
}

@Observable
@MainActor
public final class ActiveStore {
  public private(set) var loading: Bool = true
  public private(set) var error: String? = nil
  public private(set) var activeSessions: [Session] = []
  public private(set) var blockedRequests: [String: PermissionRequest] = [:]
  public private(set) var sinceTimestamps: [String: Int] = [:]
  public private(set) var now: Date = Date()

  @ObservationIgnored private let connectionStore: ConnectionStore
  @ObservationIgnored private var eventSubscription: EventSubscription?
  @ObservationIgnored private var timer: Timer?

  public init(connectionStore: ConnectionStore? = nil) {
    let conn = connectionStore ?? ConnectionStore.shared
    self.connectionStore = conn
    self.eventSubscription = conn.onServerEvent { [weak self] event in
      Task { @MainActor in
        self?.handleEvent(event)
      }
    }
  }

  public func setActive(_ active: Bool) {
    if active {
      startTimer()
    } else {
      stopTimer()
    }
  }

  public func startTimer() {
    stopTimer()
    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.now = Date()
      }
    }
  }

  public func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  public var rows: [ActiveRow] {
    let list = activeSessions.map { session -> ActiveRow in
      let dir = session.directory ?? ""
      let projName = dir.isEmpty ? "unknown project" : Formatters.basename(dir)
      let req = blockedRequests[session.id]
      let start = sinceTimestamps[session.id] ?? (session.timeUpdated > 0 ? session.timeUpdated : nil)
      return ActiveRow(
        session: session,
        directory: dir,
        project: projName,
        request: req,
        started: start
      )
    }

    return list.sorted { left, right in
      if (left.request != nil) != (right.request != nil) {
        return left.request != nil
      }
      return (right.started ?? 0) < (left.started ?? 0)
    }
  }

  public var blockedCount: Int {
    rows.filter { $0.request != nil }.count
  }

  public var runningCount: Int {
    rows.count
  }

  public func elapsed(for row: ActiveRow) -> String {
    guard let started = row.started, started > 0 else { return "" }
    let seconds = max(0, Int((now.timeIntervalSince1970 * 1000 - Double(started)) / 1000))
    if seconds < 60 {
      return "\(seconds)s"
    }
    let minutes = seconds / 60
    if minutes < 60 {
      return "\(minutes)m \(seconds % 60)s"
    }
    let hours = minutes / 60
    return "\(hours)h \(minutes % 60)m"
  }

  public func refresh() async {
    guard let client = connectionStore.client else {
      error = "Not connected to server"
      loading = false
      return
    }

    loading = true
    error = nil

    do {
      let active = try await client.listActiveSessions()
      let pending = (try? await client.listPendingPermissions()) ?? []

      self.activeSessions = active
      var reqMap: [String: PermissionRequest] = [:]
      for req in pending {
        reqMap[req.sessionID] = req
      }
      self.blockedRequests = reqMap

      var stamps = self.sinceTimestamps
      for s in active {
        if stamps[s.id] == nil {
          stamps[s.id] = s.timeUpdated > 0 ? s.timeUpdated : Int(Date().timeIntervalSince1970 * 1000)
        }
      }
      self.sinceTimestamps = stamps
      self.loading = false
    } catch {
      self.error = toUserMessage(error)
      self.loading = false
    }
  }

  private func handleEvent(_ event: ServerEvent) {
    guard let id = event.sessionID ?? event["sessionID"].string else { return }

    if event.type == "permission.asked" {
      let req = PermissionRequest(
        id: event["id"].string ?? id,
        sessionID: id,
        action: event["action"].string ?? "run",
        resources: event["resources"].stringArray
      )
      blockedRequests[id] = req
      if !activeSessions.contains(where: { $0.id == id }) {
        Task { await refresh() }
      }
      return
    }

    if event.type == "permission.replied" {
      blockedRequests.removeValue(forKey: id)
      return
    }

    if event.type == "session.execution.started" || event.type == "session.step.started" {
      if sinceTimestamps[id] == nil {
        sinceTimestamps[id] = Int(Date().timeIntervalSince1970 * 1000)
      }
      if !activeSessions.contains(where: { $0.id == id }) {
        Task { await refresh() }
      }
      return
    }

    if event.type == "session.idle" || event.type == "session.execution.succeeded" ||
       event.type == "session.execution.failed" || event.type == "session.execution.interrupted" ||
       event.type == "session.deleted" {
      activeSessions.removeAll { $0.id == id }
      sinceTimestamps.removeValue(forKey: id)
      blockedRequests.removeValue(forKey: id)
    }
  }
}
