import OceanKit
import OceanUI
import SwiftUI

/**
 Saved servers list with active indicator, one-click switch, and forget buttons.

 Ported from `ServerView.vue` and `ConnectView.vue`.
 */
public struct ServerSwitcher: View {
  private let onNeedCredentials: ((String) -> Void)?
  private let onSelectServer: ((RecentServer) -> Void)?

  @State private var connectionStore = ConnectionStore.shared
  @State private var switchingURL: String? = nil
  @State private var switchError: String? = nil
  @Environment(\.palette) private var palette

  public init(
    onNeedCredentials: ((String) -> Void)? = nil,
    onSelectServer: ((RecentServer) -> Void)? = nil
  ) {
    self.onNeedCredentials = onNeedCredentials
    self.onSelectServer = onSelectServer
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Space.s3) {
      SectionLabel("SAVED SERVERS")

      if let switchError {
        Text(switchError)
          .bodyText(12)
          .foregroundStyle(palette.accent500)
          .padding(Space.s3)
          .background(palette.surfaceRaised)
          .overlay(alignment: .leading) {
            RuleLine(.section, axis: .vertical, color: palette.accent)
          }
      }

      if connectionStore.recents.isEmpty {
        StateBlock(
          .empty,
          message: "No servers saved yet. Anything you connect to is listed here for one-tap switching."
        )
      } else {
        VStack(spacing: 0) {
          ForEach(connectionStore.recents, id: \.url) { entry in
            serverRow(entry)
          }
        }
        .background(palette.surface)
        .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section))
      }
    }
  }

  @ViewBuilder
  private func serverRow(_ entry: RecentServer) -> some View {
    let isActive = isCurrentServer(entry.url)
    let isSwitching = switchingURL == entry.url

    HStack(spacing: Space.s3) {
      StatusDot(isActive ? .accent : .faint)

      VStack(alignment: .leading, spacing: 2) {
        Text(hostOf(entry.url))
          .mono(13.5)
          .foregroundStyle(palette.text)
          .lineLimit(1)

        Text(metaText(entry))
          .mono(11)
          .foregroundStyle(palette.textMuted)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if isActive {
        Chip("CURRENT", tone: .on, uppercased: false)
      } else if isSwitching {
        Spinner(size: 15)
      } else {
        IconButton(.arrowRight, label: "Switch to server", size: 16) {
          switchTo(entry)
        }
      }

      IconButton(.close, label: "Forget server", size: 14) {
        connectionStore.forgetServer(entry.url)
      }
      .foregroundStyle(palette.textFaint)
    }
    .padding(.horizontal, Space.s4)
    .padding(.vertical, Space.s3)
    .background(isActive ? palette.surfaceRaised : Color.clear)
    .overlay(alignment: .bottom) { RuleLine(.row) }
  }

  private func isCurrentServer(_ url: String) -> Bool {
    guard let client = connectionStore.client else { return false }
    return normaliseBaseUrl(url) == normaliseBaseUrl(client.baseURL)
  }

  private func metaText(_ entry: RecentServer) -> String {
    var parts: [String] = []
    if let dir = entry.lastDirectory, !dir.isEmpty {
      parts.append(Formatters.displayPath(dir, home: connectionStore.appInfo?.home))
    }
    parts.append(Formatters.relativeTime(entry.lastConnected))
    parts.append(entry.useBasicAuth ? "auth on" : "auth off")
    return parts.joined(separator: " · ")
  }

  private func switchTo(_ entry: RecentServer) {
    if let onSelectServer {
      onSelectServer(entry)
      return
    }

    if connectionStore.savedServer(entry.url) == nil, let onNeedCredentials {
      onNeedCredentials(entry.url)
      return
    }

    Task {
      switchingURL = entry.url
      switchError = nil
      let success = await connectionStore.switchServer(entry.url)
      switchingURL = nil
      if !success {
        if connectionStore.authFailed {
          if let onNeedCredentials {
            onNeedCredentials(entry.url)
          } else {
            switchError = "Credentials rejected. Please connect with password."
          }
        } else {
          switchError = connectionStore.error ?? "Could not switch to that server."
        }
      }
    }
  }
}
