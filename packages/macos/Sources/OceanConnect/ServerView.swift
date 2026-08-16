import OceanKit
import OceanUI
import SwiftUI

/**
 Server specs, settings, appearance, and saved servers list.

 Ported from `ServerView.vue`.
 */
public struct ServerView: View {
  private let onAttachDifferent: (() -> Void)?
  private let onDetach: (() -> Void)?
  private let onNeedCredentials: ((String) -> Void)?

  @State private var connectionStore = ConnectionStore.shared
  @State private var appearance = Appearance.shared

  @Environment(\.palette) private var palette

  public init(
    onAttachDifferent: (() -> Void)? = nil,
    onDetach: (() -> Void)? = nil,
    onNeedCredentials: ((String) -> Void)? = nil
  ) {
    self.onAttachDifferent = onAttachDifferent
    self.onDetach = onDetach
    self.onNeedCredentials = onNeedCredentials
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: Space.s6) {
          if connectionStore.isConnected {
            HStack(alignment: .top, spacing: Space.s4) {
              specSection
                .frame(maxWidth: .infinity, alignment: .topLeading)

              VStack(alignment: .leading, spacing: Space.s4) {
                appearanceSection
                RuleLine(.section)
                connectionActions
              }
              .frame(maxWidth: .infinity, alignment: .topLeading)
            }
          } else {
            StateBlock(
              .empty,
              label: "Detached",
              message: "No server is attached. Enter an address to connect."
            )
            AppButton("Attach to a server", variant: .primary, icon: .arrowRight) {
              onAttachDifferent?()
            }

            RuleLine(.section)
            appearanceSection
          }

          RuleLine(.section)

          ServerSwitcher(onNeedCredentials: onNeedCredentials, onSelectServer: { entry in
            if connectionStore.savedServer(entry.url) != nil {
              Task {
                await connectionStore.switchServer(entry.url)
              }
            } else if let onNeedCredentials {
              onNeedCredentials(entry.url)
            } else {
              Task {
                await connectionStore.switchServer(entry.url)
              }
            }
          })
        }
        .padding(Space.s6)
        .frame(maxWidth: 1100, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(palette.bg)
  }

  private var specSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      SectionHeader("SERVER SPECIFICATIONS")

      VStack(spacing: 0) {
        specRow("Address", value: connectionStore.client?.baseURL ?? "")
        specRow("Host", value: connectionStore.client?.displayHost ?? "")
        specRow("User", value: connectionStore.username ?? "no authentication")
        specRow("Version", value: connectionStore.serverVersion ?? "not reported")
        specRow(
          "Working directory",
          value: Formatters.displayPath(
            connectionStore.workingDirectory ?? "unknown",
            home: connectionStore.appInfo?.home
          )
        )
        specRow("Repository", value: connectionStore.isGitRepo ? "yes" : "no — Git screens are off")
        specRow("Event stream", value: connectionStore.streamConnected ? "connected" : "reconnecting…")
      }
      .background(palette.surface)
      .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section))
    }
  }

  private func specRow(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      SectionLabel(label)
      Text(value)
        .mono(13.5)
        .foregroundStyle(palette.text)
        .lineLimit(1)
    }
    .padding(.horizontal, Space.s4)
    .padding(.vertical, Space.s3)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .bottom) { RuleLine(.row) }
  }

  private var connectionActions: some View {
    VStack(spacing: Space.s3) {
      AppButton("Attach a different server", variant: .secondary, icon: .arrowRight) {
        onAttachDifferent?()
      }

      AppButton("Detach", variant: .secondary, icon: .close) {
        connectionStore.disconnect()
        onDetach?()
      }
    }
  }

  private var appearanceSection: some View {
    VStack(alignment: .leading, spacing: Space.s4) {
      VStack(alignment: .leading, spacing: 2) {
        SectionLabel("APPEARANCE")
        Text("\(appearance.resolvedTheme.rawValue) theme · \(appearance.contrastMode == .high ? "high" : "normal") contrast")
          .mono(11)
          .foregroundStyle(palette.textMuted)
      }

      VStack(alignment: .leading, spacing: Space.s2) {
        Text("THEME")
          .mono(10)
          .tracking(0.12 * 10)
          .foregroundStyle(palette.textMuted)

        SegmentedControl(
          ThemeMode.allCases.map { SegmentItem<ThemeMode>($0, label: $0.title) },
          selection: appearance.themeBinding
        )
      }

      VStack(alignment: .leading, spacing: Space.s2) {
        Text("CONTRAST")
          .mono(10)
          .tracking(0.12 * 10)
          .foregroundStyle(palette.textMuted)

        SegmentedControl(
          ContrastMode.allCases.map { SegmentItem<ContrastMode>($0, label: $0.title) },
          selection: appearance.contrastBinding
        )
      }
    }
  }
}
