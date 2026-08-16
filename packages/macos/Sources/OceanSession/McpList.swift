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
  private let onAdd: ((String, String) -> Void)?
  private let onRemove: ((McpServer) -> Void)?

  @State private var isAdding = false
  @State private var newName = ""
  @State private var newCommand = ""

  @Environment(\.palette) private var palette

  public init(
    servers: [McpServer]?,
    loading: Bool,
    error: String?,
    actionError: String? = nil,
    pending: Set<String> = [],
    onToggle: @escaping (McpServer, Bool) -> Void,
    onAdd: ((String, String) -> Void)? = nil,
    onRemove: ((McpServer) -> Void)? = nil
  ) {
    self.servers = servers
    self.loading = loading
    self.error = error
    self.actionError = actionError
    self.pending = pending
    self.onToggle = onToggle
    self.onAdd = onAdd
    self.onRemove = onRemove
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if onAdd != nil {
        addServerRow
      }

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

            VStack(spacing: 0) {
              HStack(spacing: Space.s2) {
                AppToggle(
                  server.name,
                  isOn: Binding(
                    get: { isConnected },
                    set: { newValue in onToggle(server, newValue) }
                  ),
                  description: statusLabel(server),
                  monoDescription: server.status == .failed
                )
                .disabled(isPending)

                if let onRemove {
                  IconButton(.close, label: "Remove server", size: 14) {
                    onRemove(server)
                  }
                  .foregroundStyle(palette.textMuted)
                  .disabled(isPending)
                }
              }
              .padding(.horizontal, Space.s4)

              RuleLine(.row)
            }
          }
        }

        Text("Applies to the running server, not its config file — a disabled server returns when opencode restarts.")
          .bodyText(11)
          .foregroundStyle(palette.textDim)
          .padding(Space.s4)
      }
    }
  }

  @ViewBuilder
  private var addServerRow: some View {
    if !isAdding {
      Button {
        isAdding = true
      } label: {
        HStack(spacing: Space.s2) {
          AppIcon(.plus, size: 12)
            .foregroundStyle(palette.accent)
          Text("Add server")
            .mono(12, weight: .semibold)
            .foregroundStyle(palette.text)
          Spacer()
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(palette.surface)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .overlay(alignment: .bottom) { RuleLine(.row) }
    } else {
      VStack(alignment: .leading, spacing: Space.s3) {
        HStack {
          SectionLabel("ADD MCP SERVER")
          Spacer()
          IconButton(.close, label: "Cancel", size: 12) {
            isAdding = false
            newName = ""
            newCommand = ""
          }
        }

        AppTextField(
          "NAME",
          text: $newName,
          placeholder: "server-name"
        )

        AppTextField(
          "COMMAND",
          text: $newCommand,
          placeholder: "npx -y @modelcontextprotocol/server-..."
        )

        HStack {
          Spacer()
          AppButton("Add", variant: .primary, icon: .plus) {
            let name = newName.trimmingCharacters(in: .whitespaces)
            let cmd = newCommand.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !cmd.isEmpty else { return }
            onAdd?(name, cmd)
            newName = ""
            newCommand = ""
            isAdding = false
          }
          .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .padding(Space.s4)
      .background(palette.surfaceRaised)
      .overlay(alignment: .bottom) { RuleLine(.row) }
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
