import Foundation
import OceanKit

public enum TerminalEntryStatus: String, Codable, Hashable, Sendable {
  case running
  case exited
  case timeout
  case killed
  case failed

  public init(shellStatus: ShellStatus) {
    switch shellStatus {
    case .running: self = .running
    case .exited: self = .exited
    case .timeout: self = .timeout
    case .killed: self = .killed
    }
  }
}

public struct TerminalEntry: Identifiable, Codable, Hashable, Sendable {
  public let id: Int
  public var command: String
  /// Where it ran — entries keep their own, since `cd` moves the prompt.
  public var cwd: String
  public var output: String
  public var status: TerminalEntryStatus
  public var exit: Int?

  public init(
    id: Int,
    command: String,
    cwd: String,
    output: String = "",
    status: TerminalEntryStatus = .running,
    exit: Int? = nil
  ) {
    self.id = id
    self.command = command
    self.cwd = cwd
    self.output = output
    self.status = status
    self.exit = exit
  }
}
