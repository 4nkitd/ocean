import Foundation
import OceanKit
import OceanUI
import SwiftUI

public struct McpList: View {
  private let servers: [McpServer]?
  private let loading: Bool
  private let error: String?
  private let actionError: String?
  private let pending: Set<String>
  private let onToggle: (McpServer, Bool) -> Void

  @Environment(\.palette) private var palette

  public init(
    servers: [McpServer]?,
    loading: Bool,
    error: String?,
    actionError: String? = nil,
    pending: Set<String> = [],
    onToggle: @escaping (McpServer, Bool) -> Void
  ) {
    self.servers = servers
    self.loading = loading
    self.error = error
    self.actionError = actionError
    self.pending = pending
    self.onToggle = onToggle
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if loading {
        HStack(spacing: Space.s2) {
          Spinner(size: 14).foregroundStyle(palette.textDim)
          Text("Reading the server's MCP list…")
            .bodyText(13)
            .foregroundStyle(palette.textMuted)
        }
        .padding(Space.s4)
      } else if let error {
        Text(error)
          .bodyText(13)
          .foregroundStyle(palette.accent500)
          .padding(Space.s4)
      } else if servers == nil {
        Text("This opencode build does not expose MCP controls.")
          .bodyText(13)
          .foregroundStyle(palette.textMuted)
          .padding(Space.s4)
      } else if let serverList = servers, serverList.isEmpty {
        Text("No MCP servers are configured.")
          .bodyText(13)
          .foregroundStyle(palette.textMuted)
          .padding(Space.s4)
      } else if let serverList = servers {
        if let actionError {
          Text(actionError)
            .bodyText(12)
            .foregroundStyle(palette.accent500)
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s2)
        }

        VStack(alignment: .leading, spacing: 0) {
          ForEach(serverList) { server in
            let isConnected = server.status == .connected
            let isPending = pending.contains(server.name)

            AppToggle(
              server.name,
              isOn: Binding(
                get: { isConnected },
                set: { newValue in onToggle(server, newValue) }
              ),
              description: statusLabel(server)
            )
            .disabled(isPending)
            .padding(.horizontal, Space.s4)
          }
        }

        Text("Applies to the running server, not its config file — a disabled server returns when opencode restarts.")
          .bodyText(11)
          .foregroundStyle(palette.textDim)
          .padding(Space.s4)
      }
    }
  }

  private func statusLabel(_ server: McpServer) -> String {
    if server.status == .failed {
      return server.error != nil ? "Failed — \(server.error!)" : "Failed"
    }
    return server.status == .connected ? "Connected" : "Disabled"
  }
}

public struct McpSheet: View {
  private let store: SessionStore
  private let onClose: () -> Void

  public init(store: SessionStore, onClose: @escaping () -> Void) {
    self.store = store
    self.onClose = onClose
  }

  public var body: some View {
    SheetCard(
      title: "MCP Servers",
      kicker: "MODEL CONTEXT PROTOCOL",
      width: 500,
      maxHeight: 520,
      onClose: onClose
    ) {
      McpList(
        servers: store.mcpServers,
        loading: store.mcpLoading,
        error: store.mcpError,
        actionError: store.mcpActionError,
        pending: store.mcpPending,
        onToggle: { server, enabled in
          store.toggleMcp(server: server, enabled: enabled)
        }
      )
      .onAppear {
        store.loadMcp()
      }
    }
  }
}
