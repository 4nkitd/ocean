import Foundation
import Observation
import OceanKit

@Observable
@MainActor
public final class McpStore {
  public private(set) var servers: [McpServer]?
  public private(set) var loading = false
  public private(set) var error: String?
  public private(set) var actionError: String?
  public private(set) var pending: Set<String> = []

  @ObservationIgnored private let connection: ConnectionStore

  public init(connection: ConnectionStore? = nil) {
    self.connection = connection ?? ConnectionStore.shared
  }

  public func load(directory: String?) {
    loading = true
    error = nil

    Task {
      do {
        let client = try connection.requireClient()
        let result = try await client.listMcp(directory)
        self.servers = result
      } catch {
        self.error = toUserMessage(error)
      }
      self.loading = false
    }
  }

  public func toggle(_ server: McpServer, enabled: Bool, directory: String?) {
    guard !pending.contains(server.name) else { return }
    pending.insert(server.name)
    actionError = nil

    if let idx = servers?.firstIndex(where: { $0.name == server.name }) {
      servers?[idx].status = enabled ? .connected : .disabled
    }

    Task {
      do {
        let client = try connection.requireClient()
        try await client.setMcpEnabled(server.name, enabled, directory: directory)
        self.load(directory: directory)
      } catch {
        self.actionError = "\(server.name): \(toUserMessage(error))"
        if let idx = self.servers?.firstIndex(where: { $0.name == server.name }) {
          self.servers?[idx].status = server.status
        }
      }
      self.pending.remove(server.name)
    }
  }

  public func add(name: String, command: [String], environment: [String: String] = [:], directory: String?) {
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    guard !trimmedName.isEmpty, !command.isEmpty else { return }
    actionError = nil

    Task {
      do {
        let client = try connection.requireClient()
        try await client.addMcp(trimmedName, command: command, environment: environment, directory: directory)
        self.load(directory: directory)
      } catch {
        self.actionError = "\(trimmedName): \(toUserMessage(error))"
      }
    }
  }

  public func remove(_ server: McpServer, directory: String?) {
    guard !pending.contains(server.name) else { return }
    pending.insert(server.name)
    actionError = nil

    Task {
      do {
        let client = try connection.requireClient()
        try await client.removeMcp(server.name, directory: directory)
        self.load(directory: directory)
      } catch {
        self.actionError = "\(server.name): \(toUserMessage(error))"
      }
      self.pending.remove(server.name)
    }
  }
}
