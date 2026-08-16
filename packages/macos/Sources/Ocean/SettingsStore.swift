import Foundation
import OceanKit
import Observation

@Observable
@MainActor
public final class SettingsStore {
  public private(set) var plugins: [PluginInfo]?
  public private(set) var pluginsLoading = false
  public private(set) var pluginsError: String?

  public private(set) var integrations: [IntegrationInfo]?
  public private(set) var integrationsLoading = false
  public private(set) var integrationsError: String?

  public private(set) var ptySessions: [PtySession] = []
  public private(set) var ptyLoading = false
  public private(set) var ptyError: String?

  public private(set) var worktrees: [Worktree]?
  public private(set) var worktreesLoading = false
  public private(set) var worktreesError: String?
  public private(set) var worktreeCreateError: String?

  private let connection: ConnectionStore

  public init(connection: ConnectionStore? = nil) {
    self.connection = connection ?? .shared
  }

  private var currentDirectory: String? {
    connection.workingDirectory
  }

  public func loadPlugins(directory: String? = nil) async {
    guard let client = connection.client else { return }
    let dir = directory ?? currentDirectory
    pluginsLoading = true
    pluginsError = nil
    do {
      plugins = try await client.listPlugins(dir)
    } catch {
      pluginsError = error.localizedDescription
    }
    pluginsLoading = false
  }

  public func loadIntegrations(directory: String? = nil) async {
    guard let client = connection.client else { return }
    let dir = directory ?? currentDirectory
    integrationsLoading = true
    integrationsError = nil
    do {
      integrations = try await client.listIntegrations(dir)
    } catch {
      integrationsError = error.localizedDescription
    }
    integrationsLoading = false
  }

  public func loadPty(directory: String? = nil) async {
    guard let client = connection.client else { return }
    let dir = directory ?? currentDirectory
    ptyLoading = true
    ptyError = nil
    do {
      ptySessions = try await client.listPtySessions(dir)
    } catch {
      ptyError = error.localizedDescription
    }
    ptyLoading = false
  }

  public func loadWorktrees(directory: String? = nil) async {
    guard let client = connection.client else { return }
    let dir = directory ?? currentDirectory
    worktreesLoading = true
    worktreesError = nil
    do {
      let projects = (try? await client.listProjects()) ?? []
      if let dir, let project = projects.first(where: { $0.worktree == dir || $0.directories.contains(dir) }) {
        worktrees = try await client.listWorktrees(projectID: project.id)
      } else {
        worktrees = nil
      }
    } catch {
      worktreesError = error.localizedDescription
    }
    worktreesLoading = false
  }

  public func createWorktree(path: String, branch: String? = nil, directory: String? = nil) async {
    guard let client = connection.client else { return }
    let dir = directory ?? currentDirectory
    worktreeCreateError = nil
    do {
      let projects = (try? await client.listProjects()) ?? []
      guard let dir, let project = projects.first(where: { $0.worktree == dir || $0.directories.contains(dir) }) else {
        worktreeCreateError = "Project not found"
        return
      }
      let name = (path as NSString).lastPathComponent
      try await client.createWorktree(
        projectID: project.id,
        strategy: "copy",
        from: branch,
        directory: path,
        name: name.isEmpty ? nil : name
      )
      await loadWorktrees(directory: dir)
    } catch {
      worktreeCreateError = error.localizedDescription
    }
  }

  public func loadAll(directory: String? = nil) async {
    let dir = directory ?? currentDirectory
    await loadPlugins(directory: dir)
    await loadIntegrations(directory: dir)
    await loadPty(directory: dir)
    await loadWorktrees(directory: dir)
  }
}
