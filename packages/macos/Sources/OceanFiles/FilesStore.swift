import Foundation
import Observation
import OceanKit
import OceanUI

public struct TreeRow: Identifiable, Hashable, Sendable {
  public let path: String
  public let name: String
  public let type: FileNode.Kind
  public let depth: Int
  public let expanded: Bool
  public let loading: Bool
  public let status: FileChangeStatus?
  public let changed: Int

  public var id: String { path }

  public init(
    path: String,
    name: String,
    type: FileNode.Kind,
    depth: Int,
    expanded: Bool,
    loading: Bool,
    status: FileChangeStatus?,
    changed: Int
  ) {
    self.path = path
    self.name = name
    self.type = type
    self.depth = depth
    self.expanded = expanded
    self.loading = loading
    self.status = status
    self.changed = changed
  }
}

@Observable
@MainActor
public final class FilesStore {
  public let client: OpenCodeClient
  public let directory: String

  public private(set) var levels: [String: [FileNode]] = [:]
  public private(set) var expanded: Set<String> = []
  public private(set) var pending: Set<String> = []
  public private(set) var statuses: [String: FileChangeStatus] = [:]
  public private(set) var rows: [TreeRow] = []
  public private(set) var changedCounts: [String: Int] = [:]
  @ObservationIgnored private var cachedDiff: (timestamp: Date, diff: [VcsDiffFile])? = nil

  public private(set) var loading: Bool = false
  public private(set) var error: String? = nil
  public var query: String = "" {
    didSet {
      scheduleFilter()
    }
  }
  public private(set) var filtering: Bool = false
  public private(set) var matches: [String]? = nil

  public var currentPath: String
  public var selectedPath: String? = nil
  public private(set) var selectedContent: String = ""
  public private(set) var selectedLoading: Bool = false
  public private(set) var selectedError: String? = nil
  public private(set) var gitStatus: FileChangeStatus? = nil
  public private(set) var changedLines: Set<Int> = []
  public var selectedLine: Int? = 1

  public private(set) var isRepo: Bool = false
  public private(set) var filterOpen: Bool = false

  private var filterTask: Task<Void, Never>? = nil

  public init(client: OpenCodeClient, directory: String) {
    self.client = client
    self.directory = directory
    self.currentPath = directory
  }

  // MARK: - Computed Properties

  public var filterActive: Bool {
    matches != nil
  }

  public var expandedCount: Int {
    expanded.count
  }

  public var projectName: String {
    Formatters.basename(directory)
  }

  public var fileCount: Int {
    var total = 0
    for nodes in levels.values {
      for node in nodes where node.type == .file {
        total += 1
      }
    }
    return total
  }

  public func recomputeTree() {
    var counts: [String: Int] = [:]
    for path in statuses.keys {
      var parent = parentOf(path)
      while parent.count >= directory.count && parent.hasPrefix(directory) {
        counts[parent, default: 0] += 1
        if parent == directory { break }
        parent = parentOf(parent)
      }
    }
    self.changedCounts = counts

    if let matches = matches {
      self.rows = matches.map { path in
        TreeRow(
          path: path,
          name: relative(path),
          type: .file,
          depth: 0,
          expanded: false,
          loading: false,
          status: statuses[path],
          changed: 0
        )
      }
      return
    }

    var out: [TreeRow] = []
    func walk(_ path: String, depth: Int) {
      guard let nodes = levels[path] else { return }
      for node in nodes {
        if node.name.hasPrefix(".") && node.name != ".gitignore" && node.name != ".env" {
          continue
        }
        let isDir = node.type == .directory
        let isOpen = isDir && expanded.contains(node.path)
        out.append(
          TreeRow(
            path: node.path,
            name: node.name,
            type: node.type,
            depth: depth,
            expanded: isOpen,
            loading: pending.contains(node.path),
            status: isDir ? nil : (statuses[node.path] ?? node.status),
            changed: isDir ? (counts[node.path] ?? 0) : 0
          )
        )
        if isOpen {
          walk(node.path, depth: depth + 1)
        }
      }
    }

    walk(directory, depth: 0)
    self.rows = out
  }

  public var crumbs: [Crumb] {
    let relativeStr = relative(currentPath)
    let parts = relativeStr.split(separator: "/").map(String.init)
    var result: [Crumb] = [Crumb(projectName, id: directory)]
    var path = directory
    for part in parts {
      path = absolute(part, in: path)
      result.append(Crumb(part, id: path))
    }
    return result
  }

  // MARK: - Actions

  public func loadLevel(_ path: String, force: Bool = false) async {
    if !force && levels[path] != nil { return }
    pending.insert(path)
    recomputeTree()
    do {
      let nodes = try await client.listDirectory(path, directory: directory)
      levels[path] = sortNodes(nodes)
    } catch {
      expanded.remove(path)
      self.error = error.localizedDescription
    }
    pending.remove(path)
    recomputeTree()
  }

  public func loadStatus() async {
    do {
      let entries = try await client.fileStatus(directory)
      var next: [String: FileChangeStatus] = [:]
      for entry in entries {
        next[absolute(entry.path)] = entry.status
      }
      statuses = next
      cachedDiff = nil
      isRepo = true
      recomputeTree()
    } catch {
      // Git status decoration; failing here is acceptable
    }
  }

  public func refresh() async {
    error = nil
    loading = true
    let openPaths = Array(expanded).sorted { $0.count < $1.count }
    levels.removeAll()
    await loadLevel(directory, force: true)
    await loadStatus()
    for path in openPaths {
      await loadLevel(path, force: true)
    }
    loading = false
  }

  public func toggle(_ path: String) async {
    if expanded.contains(path) {
      expanded.remove(path)
      recomputeTree()
    } else {
      expanded.insert(path)
      recomputeTree()
      await loadLevel(path)
    }
  }

  public func collapseAll() {
    expanded.removeAll()
    recomputeTree()
  }

  public func reveal(_ path: String) async {
    guard path.hasPrefix(directory) else { return }
    let rel = relative(path)
    var segments = rel.split(separator: "/").map(String.init)
    if !segments.isEmpty { segments.removeLast() }
    var current = directory
    for segment in segments {
      current = absolute(segment, in: current)
      expanded.insert(current)
      await loadLevel(current)
    }
    recomputeTree()
  }

  public func setFilterOpen(_ open: Bool) {
    filterOpen = open
    if !open {
      query = ""
    }
  }

  private func scheduleFilter() {
    filterTask?.cancel()
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if term.isEmpty {
      filtering = false
      matches = nil
      recomputeTree()
      return
    }

    filterTask = Task {
      try? await Task.sleep(nanoseconds: 220_000_000)
      if Task.isCancelled { return }
      await runFilter(term)
    }
  }

  public func runFilter(_ term: String) async {
    filtering = true
    do {
      let found = try await client.findFiles(term, directory: directory)
      if Task.isCancelled { return }
      matches = found.isEmpty ? localMatches(term) : Array(found.prefix(200))
    } catch {
      matches = localMatches(term)
    }
    filtering = false
    recomputeTree()
  }

  private func localMatches(_ term: String) -> [String] {
    let needle = term.lowercased()
    var found: [String] = []
    for nodes in levels.values {
      for node in nodes where node.type == .file {
        if relative(node.path).lowercased().contains(needle) {
          found.append(node.path)
          if found.count >= 200 { return found }
        }
      }
    }
    return found
  }

  public func selectFile(_ path: String) async {
    selectedPath = path
    selectedLoading = true
    selectedError = nil
    selectedContent = ""
    changedLines.removeAll()

    do {
      let contentRes = try await client.readFile(path, directory: directory)
      selectedContent = contentRes.content
      selectedLine = 1
    } catch {
      selectedError = error.localizedDescription
    }

    selectedLoading = false
    await loadGitState(path: path)
  }

  public func loadGitState(path: String) async {
    gitStatus = statuses[path]
    if gitStatus == .modified {
      await loadChangedLines(path: path)
    }
  }

  public func loadChangedLines(path: String) async {
    do {
      let now = Date()
      let changes: [VcsDiffFile]
      if let cached = cachedDiff, now.timeIntervalSince(cached.timestamp) < 5 {
        changes = cached.diff
      } else {
        changes = try await client.getVcsDiff(directory, mode: .working)
        cachedDiff = (now, changes)
      }
      let rel = relative(path)
      if let match = changes.first(where: { relative($0.file) == rel }), !match.patch.isEmpty {
        changedLines = parseHunkLines(match.patch)
      }
    } catch {}
  }

  private func parseHunkLines(_ patch: String) -> Set<Int> {
    var lines = Set<Int>()
    for line in patch.components(separatedBy: .newlines) {
      guard line.hasPrefix("@@") else { continue }
      let parts = line.split(separator: " ")
      for part in parts where part.hasPrefix("+") {
        let numStr = part.dropFirst()
        let components = numStr.split(separator: ",")
        if let start = Int(components[0]) {
          let count = components.count > 1 ? (Int(components[1]) ?? 1) : 1
          for i in 0..<count {
            lines.insert(start + i)
          }
        }
      }
    }
    return lines
  }

  // MARK: - Helpers

  public func absolute(_ path: String, in root: String? = nil) -> String {
    let base = root ?? directory
    if path.hasPrefix("/") { return path }
    return base.hasSuffix("/") ? base + path : base + "/" + path
  }

  public func relative(_ path: String) -> String {
    let prefix = directory.hasSuffix("/") ? directory : directory + "/"
    if path.hasPrefix(prefix) {
      return String(path.dropFirst(prefix.count))
    }
    return path
  }

  public func parentOf(_ path: String) -> String {
    guard let cut = path.lastIndex(of: "/") else { return "" }
    if cut == path.startIndex { return "/" }
    return String(path[..<cut])
  }

  private func sortNodes(_ nodes: [FileNode]) -> [FileNode] {
    nodes.sorted { a, b in
      if a.type != b.type {
        return a.type == .directory
      }
      return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
  }
}
