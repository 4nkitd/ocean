import Foundation
import Observation
import OceanKit

public struct ProjectRow: Identifiable, Hashable, Sendable {
  public var id: String
  public var worktree: String
  public var name: String
  public var displayPath: String
  public var initials: String
  public var isGit: Bool
  public var branch: String?
  public var sessionCount: Int
  public var lastActivity: Int?
  public var sessionIds: [String]
  public var running: Bool
  public var favourite: Bool

  public init(
    id: String,
    worktree: String,
    name: String,
    displayPath: String,
    initials: String,
    isGit: Bool,
    branch: String? = nil,
    sessionCount: Int = 0,
    lastActivity: Int? = nil,
    sessionIds: [String] = [],
    running: Bool = false,
    favourite: Bool = false
  ) {
    self.id = id
    self.worktree = worktree
    self.name = name
    self.displayPath = displayPath
    self.initials = initials
    self.isGit = isGit
    self.branch = branch
    self.sessionCount = sessionCount
    self.lastActivity = lastActivity
    self.sessionIds = sessionIds
    self.running = running
    self.favourite = favourite
  }
}

private struct LoadedProject: Sendable {
  var project: Project
  var name: String
  var displayPath: String
  var initials: String
  var isGit: Bool
  var branch: String?
  var sessionCount: Int
  var lastActivity: Int?
  var sessionIds: [String]
}

@Observable
@MainActor
public final class ProjectsStore {
  public private(set) var loading: Bool = true
  public private(set) var error: String? = nil
  public var query: String = ""
  public var reordering: Bool = false

  private var rawLoaded: [LoadedProject] = []
  private var favourites: Set<String> = []
  private var order: [String] = []
  private var runningSessions: Set<String> = []

  private static let favouritesKey = "opencode.macos.projectFavourites"
  private static let orderKey = "opencode.macos.projectOrder"

  @ObservationIgnored private let connectionStore: ConnectionStore
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var eventSubscription: EventSubscription?

  public init(connectionStore: ConnectionStore? = nil, defaults: UserDefaults = .standard) {
    let conn = connectionStore ?? ConnectionStore.shared
    self.connectionStore = conn
    self.defaults = defaults
    self.favourites = Set(loadFavourites())
    self.order = loadOrder()

    self.eventSubscription = conn.onServerEvent { [weak self] event in
      Task { @MainActor in
        self?.handleEvent(event)
      }
    }
  }

  public var projects: [ProjectRow] {
    let rows = rawLoaded.map { item -> ProjectRow in
      let isRunning = item.sessionIds.contains(where: { self.runningSessions.contains($0) })
      let isFav = self.favourites.contains(item.project.id)
      return ProjectRow(
        id: item.project.id,
        worktree: item.project.worktree,
        name: item.name,
        displayPath: item.displayPath,
        initials: item.initials,
        isGit: item.isGit,
        branch: item.branch,
        sessionCount: item.sessionCount,
        lastActivity: item.lastActivity,
        sessionIds: item.sessionIds,
        running: isRunning,
        favourite: isFav
      )
    }

    let ordered = Self.sortByOrder(rows, order: order)
    return ordered.filter(\.favourite) + ordered.filter { !$0.favourite }
  }

  public var filteredProjects: [ProjectRow] {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    if q.isEmpty { return projects }
    return projects.filter {
      $0.name.lowercased().contains(q) || $0.displayPath.lowercased().contains(q)
    }
  }

  public var runningCount: Int {
    projects.filter(\.running).count
  }

  public var summary: String {
    let total = projects.count
    var parts = ["\(total) \(total == 1 ? "project" : "projects")"]
    if runningCount > 0 { parts.append("\(runningCount) running") }
    return parts.joined(separator: " · ")
  }

  public var activeProjectId: String? {
    var best: (id: String, at: Int)? = nil
    for project in projects {
      if let at = project.lastActivity, at > 0 {
        if best == nil || at > best!.at {
          best = (project.id, at)
        }
      }
    }
    return best?.id
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
      let list = try await client.listProjects()
      let statuses = (try? await client.getSessionStatuses()) ?? [:]

      let home = connectionStore.appInfo?.home
      var decorated = [LoadedProject?](repeating: nil, count: list.count)
      let chunkSize = 6
      for chunkStart in stride(from: 0, to: list.count, by: chunkSize) {
        let chunkEnd = min(chunkStart + chunkSize, list.count)
        let tasks = (chunkStart..<chunkEnd).map { index in
          let project = list[index]
          return Task {
            await Self.decorate(client: client, project: project, home: home)
          }
        }
        for (offset, task) in tasks.enumerated() {
          decorated[chunkStart + offset] = await task.value
        }
      }

      self.rawLoaded = decorated.compactMap { $0 }
      self.runningSessions = Set(statuses.filter { $0.value != "idle" }.map(\.key))
      self.loading = false
    } catch {
      self.error = toUserMessage(error)
      self.loading = false
    }
  }

  public func toggleFavourite(_ id: String) {
    if favourites.contains(id) {
      favourites.remove(id)
    } else {
      favourites.insert(id)
    }
    persistFavourites()
  }

  public func move(_ id: String, delta: Int) {
    var currentIds = projects.map(\.id)
    guard let fromIndex = currentIds.firstIndex(of: id) else { return }
    let toIndex = fromIndex + delta
    guard toIndex >= 0 && toIndex < currentIds.count else { return }

    let moved = currentIds.remove(at: fromIndex)
    currentIds.insert(moved, at: toIndex)
    order = currentIds
    persistOrder()
  }

  private func handleEvent(_ event: ServerEvent) {
    guard let sessionID = event.sessionID ?? event["sessionID"].string else { return }

    if event.type == "session.created" {
      if event["parentID"].string != nil { return }
      let dir = event.directory ?? event["location"]["directory"].string
      if let index = rawLoaded.firstIndex(where: { $0.project.worktree == dir || $0.project.directories.contains(dir ?? "") }) {
        if !rawLoaded[index].sessionIds.contains(sessionID) {
          rawLoaded[index].sessionIds.append(sessionID)
          rawLoaded[index].sessionCount += 1
          rawLoaded[index].lastActivity = Int(Date().timeIntervalSince1970 * 1000)
        }
      }
      return
    }

    if event.type == "session.deleted" {
      for i in rawLoaded.indices {
        if rawLoaded[i].sessionIds.contains(sessionID) {
          rawLoaded[i].sessionIds.removeAll { $0 == sessionID }
          rawLoaded[i].sessionCount = max(0, rawLoaded[i].sessionCount - 1)
        }
      }
      return
    }

    if event.type == "session.execution.started" || event.type == "session.step.started" {
      runningSessions.insert(sessionID)
    } else if event.type == "session.idle" || event.type == "session.execution.succeeded" || event.type == "session.execution.failed" || event.type == "session.execution.interrupted" {
      runningSessions.remove(sessionID)
    } else if event.type == "session.status" {
      let st = event["status"]["type"].string ?? event["status"].string
      if st == "busy" || st == "retry" {
        runningSessions.insert(sessionID)
      } else if st == "idle" {
        runningSessions.remove(sessionID)
      }
    }
  }

  private static func decorate(client: OpenCodeClient, project: Project, home: String?) async -> LoadedProject {
    let sessions = (try? await client.listSessions(project.worktree)) ?? []
    let branch: String?
    if project.isGit {
      branch = (try? await client.getVcsBranch(project.worktree))
    } else {
      branch = nil
    }

    let name = Formatters.basename(project.worktree)
    let lastActivity = sessions.reduce(nil as Int?) { latest, session in
      let stamp = session.timeUpdated > 0 ? session.timeUpdated : session.timeCreated
      return max(latest ?? 0, stamp)
    }

    return LoadedProject(
      project: project,
      name: name,
      displayPath: Formatters.displayPath(project.worktree, home: home),
      initials: Formatters.initials(name),
      isGit: project.isGit,
      branch: branch,
      sessionCount: sessions.count,
      lastActivity: lastActivity,
      sessionIds: sessions.map(\.id)
    )
  }

  private func loadFavourites() -> [String] {
    defaults.stringArray(forKey: Self.favouritesKey) ?? []
  }

  private func persistFavourites() {
    defaults.set(Array(favourites), forKey: Self.favouritesKey)
  }

  private func loadOrder() -> [String] {
    defaults.stringArray(forKey: Self.orderKey) ?? []
  }

  private func persistOrder() {
    defaults.set(order, forKey: Self.orderKey)
  }

  public static func sortByOrder(_ rows: [ProjectRow], order: [String]) -> [ProjectRow] {
    let pinnedMap = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
    return rows.sorted { a, b in
      let left = pinnedMap[a.id]
      let right = pinnedMap[b.id]
      if let left, let right { return left < right }
      if left != nil { return true }
      if right != nil { return false }
      return (b.lastActivity ?? 0) < (a.lastActivity ?? 0)
    }
  }
}
