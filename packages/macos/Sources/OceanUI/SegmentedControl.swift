import OceanKit
import SwiftUI

public struct SegmentItem<Value: Hashable>: Identifiable {
  public let value: Value
  public let label: String
  public let icon: IconName?
  /// A count beside the label — "12 changed files", "3 servers".
  public let badge: String?
  public let disabled: Bool
  /// Explains the disabled state rather than leaving it mysterious. Becomes
  /// the tooltip and the accessibility name.
  public let disabledReason: String?

  public var id: Value { value }

  public init(
    _ value: Value,
    label: String,
    icon: IconName? = nil,
    badge: String? = nil,
    disabled: Bool = false,
    disabledReason: String? = nil
  ) {
    self.value = value
    self.label = label
    self.icon = icon
    self.badge = badge
    self.disabled = disabled
    self.disabledReason = disabledReason
  }
}

/**
 One control for every tab strip in the design: the Git view's two-way switch,
 the workspace panel's Files/Git/Plan/MCP tabs, the mobile client's bottom rail.

 They are the same thing in three places — equal-width segments, mono uppercase,
 and a 2px accent rule on one edge of the active one that replaces the strip's
 own rule. `edge` picks which side that is: `.bottom` for a strip above its
 content, `.top` for a rail below it.
 */
public struct SegmentedControl<Value: Hashable>: View {
  public enum Edge: Sendable {
    case top
    case bottom
  }

  private let items: [SegmentItem<Value>]
  private let selection: Binding<Value>
  private let edge: Edge
  private let minHeight: CGFloat

  public init(
    _ items: [SegmentItem<Value>],
    selection: Binding<Value>,
    edge: Edge = .bottom,
    minHeight: CGFloat = 46
  ) {
    self.items = items
    self.selection = selection
    self.edge = edge
    self.minHeight = minHeight
  }

  public var body: some View {
    HStack(spacing: 0) {
      ForEach(items) { item in
        Segment(
          item: item,
          active: item.value == selection.wrappedValue,
          edge: edge,
          minHeight: minHeight
        ) {
          selection.wrappedValue = item.value
        }
      }
    }
    .accessibilityElement(children: .contain)
  }

  private struct Segment: View {
    let item: SegmentItem<Value>
    let active: Bool
    let edge: Edge
    let minHeight: CGFloat
    let select: () -> Void

    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
      Button {
        guard !item.disabled, !active else { return }
        select()
      } label: {
        HStack(spacing: 6) {
          if let icon = item.icon {
            AppIcon(icon, size: 14)
              .foregroundStyle(active && !item.disabled ? palette.accent : foreground)
          }
          Text(item.label.uppercased())
            .font(OceanFont.mono(11))
            .tracking(0.08 * 11)
            .lineLimit(1)
            .truncationMode(.tail)
          if let badge = item.badge {
            Text(badge)
              .font(OceanFont.mono(10))
              .foregroundStyle(palette.textDim)
          }
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background(hovering && !item.disabled ? palette.surfaceRaised : .clear)
        .overlay(alignment: edge == .bottom ? .bottom : .top) {
          RuleLine(.section, color: active ? palette.accent : palette.rule)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(item.disabled)
      .onHover { hovering = $0 }
      .help(item.disabled ? (item.disabledReason ?? item.label) : item.label)
      .accessibilityLabel(accessibilityLabel)
      .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    private var foreground: Color {
      if item.disabled { return palette.textFaint }
      if active { return palette.text }
      return hovering ? palette.text : palette.textMuted
    }

    private var accessibilityLabel: String {
      guard item.disabled, let reason = item.disabledReason else { return item.label }
      return "\(item.label) — \(reason)"
    }
  }
}
