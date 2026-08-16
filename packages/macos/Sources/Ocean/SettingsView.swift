import OceanConnect
import OceanKit
import OceanSession
import OceanUI
import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable {
  case server = "Server"
  case mcp = "MCP"
  case plugins = "Plugins"
  case integrations = "Integrations"
  case pty = "PTY"

  public var id: String { rawValue }
}

public struct SettingsView: View {
  private let directory: String?
  private let onAttachDifferent: (() -> Void)?
  private let onDetach: (() -> Void)?
  private let onNeedCredentials: ((String) -> Void)?

  @State private var selectedTab: SettingsTab = .server
  @State private var store = SettingsStore()
  @State private var mcpStore = McpStore()
  @State private var connectionStore = ConnectionStore.shared
  @State private var integrationsFilter = ""

  @Environment(\.palette) private var palette

  public init(
    directory: String? = nil,
    onAttachDifferent: (() -> Void)? = nil,
    onDetach: (() -> Void)? = nil,
    onNeedCredentials: ((String) -> Void)? = nil
  ) {
    self.directory = directory
    self.onAttachDifferent = onAttachDifferent
    self.onDetach = onDetach
    self.onNeedCredentials = onNeedCredentials
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      headerView

      tabStrip

      tabContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(palette.bg)
    .task {
      await store.loadAll(directory: directory)
    }
  }

  private var headerView: some View {
    VStack(alignment: .leading, spacing: Space.s2) {
      HStack(spacing: Space.s2) {
        StatusDot(connectionStore.streamConnected ? .accent : .dim, size: 7)
        Text(connectionStore.streamConnected ? "LIVE" : "OFFLINE")
          .mono(11)
          .tracking(0.12 * 11)
          .foregroundStyle(palette.textMuted)
      }

      Text("Settings")
        .font(OceanFont.body(30, weight: .bold))
        .foregroundStyle(palette.text)
    }
    .padding(.horizontal, Space.s6)
    .padding(.vertical, Space.s4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(palette.surface)
    .overlay(alignment: .bottom) { RuleLine(.section) }
  }

  private var tabStrip: some View {
    HStack(spacing: 0) {
      ForEach(Array(SettingsTab.allCases.enumerated()), id: \.element.id) { index, tab in
        let isActive = selectedTab == tab
        Button {
          selectedTab = tab
        } label: {
          Text(tab.rawValue)
            .mono(12, weight: isActive ? .bold : .medium)
            .foregroundStyle(isActive ? palette.text : palette.textMuted)
            .padding(.horizontal, Space.s4)
            .frame(maxHeight: .infinity)
            .background(isActive ? palette.surface : palette.surfaceSunken)
            .overlay(alignment: .bottom) {
              Rectangle()
                .fill(isActive ? palette.accent : Color.clear)
                .frame(height: 2)
            }
        }
        .buttonStyle(.plain)

        if index < SettingsTab.allCases.count - 1 {
          RuleLine(.row, axis: .vertical)
        }
      }
      Spacer()
    }
    .frame(height: 38)
    .background(palette.surfaceSunken)
    .overlay(alignment: .bottom) { RuleLine(.section) }
  }

  @ViewBuilder
  private var tabContent: some View {
    switch selectedTab {
    case .server:
      ServerView(
        onAttachDifferent: onAttachDifferent,
        onDetach: onDetach,
        onNeedCredentials: onNeedCredentials
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

    case .mcp:
      VStack(alignment: .leading, spacing: Space.s4) {
        SectionHeader("MCP SERVERS", count: "\(mcpStore.servers?.count ?? 0)")
        StateBlock(
          .empty,
          label: "MANAGED IN RIGHT PANEL",
          message: "MCP servers are managed in the MCP tab of the right panel."
        )
      }
      .padding(Space.s6)
      .frame(maxWidth: 1100, alignment: .leading)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .onAppear {
        mcpStore.load(directory: directory)
      }
      .onChange(of: directory) { _, nextDir in
        mcpStore.load(directory: nextDir)
      }

    case .plugins:
      pluginsSection
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

    case .integrations:
      integrationsSection
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

    case .pty:
      ptySection
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private var pluginsSection: some View {
    let countText = store.plugins.map { "\($0.count)" }
    return ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        SectionHeader("PLUGINS", count: countText)

        VStack(alignment: .leading, spacing: 0) {
          if store.pluginsLoading {
            HStack(spacing: Space.s2) {
              ProgressView()
                .controlSize(.small)
              Text("Loading plugins…")
                .mono(12)
                .foregroundStyle(palette.textMuted)
            }
            .padding(Space.s4)
          } else if let plugins = store.plugins {
            if plugins.isEmpty {
              Text("No plugins installed.")
                .mono(12)
                .foregroundStyle(palette.textMuted)
                .padding(Space.s4)
            } else {
              ForEach(plugins) { plugin in
                VStack(alignment: .leading, spacing: 0) {
                  HStack {
                    MonoText(plugin.id, size: 12, weight: .regular)
                    Spacer()
                    if let enabled = plugin.enabled {
                      Text(enabled ? "enabled" : "disabled")
                        .mono(11)
                        .foregroundStyle(enabled ? palette.accent : palette.textMuted)
                    }
                  }
                  .padding(.horizontal, Space.s4)
                  .padding(.vertical, Space.s3)

                  RuleLine(.row)
                }
              }
            }
          } else {
            Text("This server does not expose plugin controls.")
              .mono(12)
              .foregroundStyle(palette.textMuted)
              .padding(Space.s4)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
        .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section))
      }
      .padding(Space.s6)
      .frame(maxWidth: 1100, alignment: .leading)
    }
  }

  private var integrationsSection: some View {
    let allIntegrations = store.integrations ?? []
    let filtered = integrationsFilter.isEmpty ? allIntegrations : allIntegrations.filter {
      $0.name.localizedCaseInsensitiveContains(integrationsFilter) ||
      $0.id.localizedCaseInsensitiveContains(integrationsFilter)
    }
    let countText = "\(filtered.count)"
    return ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        SectionHeader("INTEGRATIONS", count: countText) {
          HStack(spacing: Space.s2) {
            AppIcon(.search, size: 13)
              .foregroundStyle(palette.textDim)
            TextField("Filter integrations…", text: $integrationsFilter)
              .textFieldStyle(.plain)
              .font(OceanFont.mono(12))
              .foregroundStyle(palette.text)
            if !integrationsFilter.isEmpty {
              Button {
                integrationsFilter = ""
              } label: {
                AppIcon(.close, size: 12)
                  .foregroundStyle(palette.textMuted)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, Space.s3)
          .padding(.vertical, 4)
          .background(palette.surfaceSunken)
          .frame(width: 220)
        }

        VStack(alignment: .leading, spacing: 0) {
          if store.integrationsLoading {
            HStack(spacing: Space.s2) {
              ProgressView()
                .controlSize(.small)
              Text("Loading integrations…")
                .mono(12)
                .foregroundStyle(palette.textMuted)
            }
            .padding(Space.s4)
          } else if store.integrations != nil {
            if filtered.isEmpty {
              Text(integrationsFilter.isEmpty ? "No integrations available." : "No integrations match \"\(integrationsFilter)\".")
                .mono(12)
                .foregroundStyle(palette.textMuted)
                .padding(Space.s4)
            } else {
              ForEach(filtered) { integration in
                let methodTypes = integration.methods.map(\.type).joined(separator: " · ")
                let connCount = integration.connections.count
                let connText = connCount > 0 ? "\(connCount) connection\(connCount == 1 ? "" : "s")" : "not connected"

                VStack(alignment: .leading, spacing: 0) {
                  VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Space.s2) {
                      Text(integration.name)
                        .font(OceanFont.body(13, weight: .bold))
                        .foregroundStyle(palette.text)
                      Text(integration.id)
                        .mono(11)
                        .foregroundStyle(palette.textMuted)
                      Spacer()
                    }

                    HStack(spacing: Space.s2) {
                      Text(methodTypes.isEmpty ? "no methods" : methodTypes)
                        .mono(11)
                        .foregroundStyle(palette.textMuted)
                      Text("·")
                        .mono(11)
                        .foregroundStyle(palette.textDim)
                      Text(connText)
                        .mono(11)
                        .foregroundStyle(connCount > 0 ? palette.accent : palette.textMuted)
                    }
                  }
                  .padding(.horizontal, Space.s4)
                  .padding(.vertical, Space.s3)

                  RuleLine(.row)
                }
              }
            }
          } else {
            Text("This server does not expose integration controls.")
              .mono(12)
              .foregroundStyle(palette.textMuted)
              .padding(Space.s4)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
        .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section))
      }
      .padding(Space.s6)
      .frame(maxWidth: 1100, alignment: .leading)
    }
  }

  private var ptySection: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        SectionHeader("PTY SESSIONS", count: "\(store.ptySessions.count)")

        if store.ptyLoading {
          HStack(spacing: Space.s2) {
            ProgressView()
              .controlSize(.small)
            Text("Loading PTY sessions…")
              .mono(12)
              .foregroundStyle(palette.textMuted)
          }
          .padding(Space.s4)
        } else if store.ptySessions.isEmpty {
          StateBlock(
            .empty,
            label: "No PTY sessions",
            message: "No terminal sessions are currently running on this server."
          )
        } else {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(store.ptySessions) { pty in
              VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s2) {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(pty.title ?? pty.command ?? pty.id)
                      .mono(12, weight: .bold)
                      .foregroundStyle(palette.text)
                    if let command = pty.command {
                      Text(command)
                        .mono(11)
                        .foregroundStyle(palette.textMuted)
                    }
                  }

                  Spacer()

                  if let pid = pty.pid {
                    Text("PID \(pid)")
                      .mono(11)
                      .foregroundStyle(palette.textMuted)
                  }
                  if let status = pty.status {
                    StatusDot(status == "running" ? .ok : .dim, size: 6)
                    Text(status)
                      .mono(11)
                      .foregroundStyle(palette.textMuted)
                  }
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)

                RuleLine(.row)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(palette.surface)
          .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section))
        }
      }
      .padding(Space.s6)
      .frame(maxWidth: 1100, alignment: .leading)
    }
  }

  private func shellSplit(_ input: String) -> [String] {
    var results: [String] = []
    var current = ""
    var inSingleQuote = false
    var inDoubleQuote = false
    var escaped = false

    for char in input {
      if escaped {
        current.append(char)
        escaped = false
      } else if char == "\\" && !inSingleQuote {
        escaped = true
      } else if char == "'" && !inDoubleQuote {
        inSingleQuote.toggle()
      } else if char == "\"" && !inSingleQuote {
        inDoubleQuote.toggle()
      } else if char.isWhitespace && !inSingleQuote && !inDoubleQuote {
        if !current.isEmpty {
          results.append(current)
          current = ""
        }
      } else {
        current.append(char)
      }
    }
    if !current.isEmpty {
      results.append(current)
    }
    return results.isEmpty && !input.trimmingCharacters(in: .whitespaces).isEmpty
      ? input.split(separator: " ").map(String.init)
      : (results.isEmpty ? [input] : results)
  }
}