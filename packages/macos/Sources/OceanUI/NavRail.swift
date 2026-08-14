import OceanKit
import SwiftUI

/**
 The tab rail from `BottomNav.vue`, without the router.

 Tabs are passed in rather than hard-coded because the design has two rails
 (Projects / Recent / Add server, and Files / Git / Chat). The active tab is
 marked by a 2px accent rule pulled over the rail's own rule, not by a fill.

 A disabled tab is the Git tab on a directory that isn't a repository: it stays
 visible and dimmed so its absence is explained rather than mysterious.
 */
public struct NavTab: Identifiable, Sendable {
  public let id: String
  public let label: String
  public let icon: IconName
  public let disabled: Bool
  /// Explains the disabled state to assistive tech and as a tooltip.
  public let disabledReason: String?

  public init(
    id: String,
    label: String,
    icon: IconName,
    disabled: Bool = false,
    disabledReason: String? = nil
  ) {
    self.id = id
    self.label = label
    self.icon = icon
    self.disabled = disabled
    self.disabledReason = disabledReason
  }
}

public struct NavRail: View {
  private let tabs: [NavTab]
  private let active: String
  private let onSelect: (String) -> Void
  /// Which edge carries the rule — bottom rail on a window, top rail in a pane.
  private let rulePosition: Edge

  @Environment(\.palette) private var palette

  public init(
    tabs: [NavTab],
    active: String,
    rulePosition: Edge = .top,
    onSelect: @escaping (String) -> Void
  ) {
    self.tabs = tabs
    self.active = active
    self.rulePosition = rulePosition
    self.onSelect = onSelect
  }

  public var body: some View {
    HStack(spacing: 0) {
      ForEach(tabs) { tab in
        Tab(
          tab: tab,
          active: tab.id == active,
          rulePosition: rulePosition,
          onSelect: onSelect
        )
      }
    }
    .background(palette.surface)
    .overlay(alignment: rulePosition == .top ? .top : .bottom) { RuleLine(.section) }
  }

  private struct Tab: View {
    let tab: NavTab
    let active: Bool
    let rulePosition: Edge
    let onSelect: (String) -> Void

    @Environment(\.palette) private var palette

    var body: some View {
      Button {
        guard !tab.disabled, !active else { return }
        onSelect(tab.id)
      } label: {
        HStack(spacing: Space.s2) {
          AppIcon(tab.icon, size: 16)
            .foregroundStyle(active ? palette.accent : foreground)
          Text(tab.label)
            .mono(12)
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, Space.s3)
        .contentShape(Rectangle())
        .overlay(alignment: rulePosition == .top ? .top : .bottom) {
          if active {
            RuleLine(.section, color: palette.accent)
          }
        }
      }
      .buttonStyle(.plain)
      .disabled(tab.disabled)
      .help(tab.disabled ? (tab.disabledReason ?? "") : "")
      .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
      guard tab.disabled, let reason = tab.disabledReason else { return tab.label }
      return "\(tab.label) — \(reason)"
    }

    private var foreground: Color {
      if tab.disabled { return palette.textFaint }
      return active ? palette.text : palette.textMuted
    }
  }
}
