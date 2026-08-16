import Foundation
import Observation
import OceanKit

/**
 The shell drawer store.

 A singleton mirroring `ConnectionStore`: outlives any screen so scrollback is kept
 when switching views.
 */
@Observable
@MainActor
public final class TerminalStore {
  public static let shared = TerminalStore()

  public private(set) var open: Bool = false
  /// The location the API calls are scoped to — the project root, not cwd.
  public private(set) var root: String = ""
  /// Where the next command runs; moved by `cd`.
  public private(set) var cwd: String = ""
  public private(set) var entries: [TerminalEntry] = []
  public private(set) var history: [String] = []
  public private(set) var busy: Bool = false

  @ObservationIgnored private weak var connectionStore: ConnectionStore?
  @ObservationIgnored private var currentTask: Task<Void, Never>?
  @ObservationIgnored private var runningShellID: String?
  @ObservationIgnored private var runningScope: String?
  @ObservationIgnored private var nextId: Int = 1

  public static let timeoutMs: Double = 600_000
  public static let pollMs: UInt64 = 120
  public static let maxOutput = 200_000
  public static let maxEntries = 80
  public static let maxHistory = 50

  @MainActor
  public init(connectionStore: ConnectionStore? = nil) {
    self.connectionStore = connectionStore ?? .shared
  }

  /// The tail of the path for prompt display: `…/parts` if longer than 2.
  public var promptPath: String {
    let path = cwd.isEmpty ? (root.isEmpty ? (connectionStore?.workingDirectory ?? "") : root) : cwd
    if path.isEmpty { return "~" }
    let parts = path.split(separator: "/").filter { !$0.isEmpty }
    if parts.count > 2 {
      return "…/" + parts.suffix(2).joined(separator: "/")
    }
    return path
  }

  /**
   Open the drawer, rooted at a directory. Switching project resets prompt
   but keeps scrollback.
   */
  public func openTerminal(directory: String? = nil) {
    let connection = connectionStore ?? ConnectionStore.shared
    let next = directory ?? (root.isEmpty ? (connection.workingDirectory ?? "") : root)
    if !next.isEmpty && next != root {
      root = next
      cwd = next
    }
    open = true
  }

  public func closeTerminal() {
    open = false
  }

  public func toggleTerminal(directory: String? = nil) {
    let connection = connectionStore ?? ConnectionStore.shared
    if open {
      closeTerminal()
    } else if connection.isConnected {
      openTerminal(directory: directory)
    }
  }

  public func clearTerminal() {
    entries = []
  }

  /// Stop the running command — removing the record kills the process.
  public func cancelTerminalCommand() {
    currentTask?.cancel()
    currentTask = nil
    if let runningShellID, let runningScope {
      let client = try? (connectionStore ?? ConnectionStore.shared).requireClient()
      let shellID = runningShellID
      let scope = runningScope
      Task {
        await client?.removeShell(scope, shellID)
      }
    }
    self.runningShellID = nil
    self.runningScope = nil
    self.busy = false
  }

  public func runTerminalCommand(_ input: String) {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !busy else { return }

    history = ([text] + history.filter { $0 != text }).prefix(Self.maxHistory).map { $0 }

    if text == "clear" || text == "cls" {
      clearTerminal()
      return
    }

    let isCd = text.range(of: #"^cd(\s|$)"#, options: .regularExpression) != nil
    let command = isCd ? "\(text) && pwd" : text

    let connection = connectionStore ?? ConnectionStore.shared
    let initialCwd = cwd.isEmpty ? (root.isEmpty ? (connection.workingDirectory ?? "") : root) : cwd

    let entryID = nextId
    nextId += 1

    let newEntry = TerminalEntry(
      id: entryID,
      command: text,
      cwd: initialCwd,
      output: "",
      status: .running,
      exit: nil
    )

    let clampedEntries = Array(entries.suffix(Self.maxEntries - 1))
    entries = clampedEntries + [newEntry]

    busy = true
    let scope = root.isEmpty ? (connection.workingDirectory ?? "") : root

    currentTask = Task { @MainActor [weak self] in
      guard let self else { return }
      var startedCommand: ShellCommand? = nil

      do {
        let client = try connection.requireClient()
        let started = try await client.startShell(scope, command, cwd: initialCwd, timeout: Self.timeoutMs / 1000)
        startedCommand = started
        self.runningShellID = started.id
        self.runningScope = scope

        var info = started
        var cursor = 0

        while !Task.isCancelled {
          let page = try await client.readShellOutput(scope, started.id, cursor: cursor)
          cursor = page.cursor
          if !page.output.isEmpty {
            if let idx = self.entries.firstIndex(where: { $0.id == entryID }) {
              self.entries[idx].output = self.clampOutput(self.entries[idx].output + page.output)
            }
          }

          if info.status != .running { break }

          do {
            try await Task.sleep(nanoseconds: Self.pollMs * 1_000_000)
          } catch {
            break
          }

          if Task.isCancelled { break }

          if let updated = try await client.getShell(scope, started.id) {
            info = updated
          }
        }

        if Task.isCancelled {
          if let idx = self.entries.firstIndex(where: { $0.id == entryID }) {
            self.entries[idx].status = .killed
            self.entries[idx].output = self.clampOutput(self.entries[idx].output + "\n^C")
          }
        } else {
          if let idx = self.entries.firstIndex(where: { $0.id == entryID }) {
            self.entries[idx].status = TerminalEntryStatus(shellStatus: info.status)
            self.entries[idx].exit = info.exit

            if isCd && info.exit == 0 {
              let trimmed = self.entries[idx].output.trimmingCharacters(in: .whitespacesAndNewlines)
              let lines = trimmed.components(separatedBy: .newlines)
              if let landed = lines.last?.trimmingCharacters(in: .whitespaces), !landed.isEmpty {
                self.cwd = landed
                if let range = self.entries[idx].output.range(of: landed, options: .backwards) {
                  self.entries[idx].output = String(self.entries[idx].output[..<range.lowerBound])
                }
              }
            }
          }
        }
      } catch {
        if Task.isCancelled {
          if let idx = self.entries.firstIndex(where: { $0.id == entryID }) {
            self.entries[idx].status = .killed
            self.entries[idx].output = self.clampOutput(self.entries[idx].output + "\n^C")
          }
        } else {
          if let idx = self.entries.firstIndex(where: { $0.id == entryID }) {
            self.entries[idx].status = .failed
            self.entries[idx].output = self.clampOutput(self.entries[idx].output + "\n" + toUserMessage(error))
          }
        }
      }

      if let started = startedCommand {
        if let client = try? connection.requireClient() {
          await client.removeShell(scope, started.id)
        }
      }

      self.runningShellID = nil
      self.runningScope = nil
      self.busy = false
      self.currentTask = nil
    }
  }

  private func clampOutput(_ output: String) -> String {
    if output.count > Self.maxOutput {
      return String(output.suffix(Self.maxOutput))
    }
    return output
  }
}
