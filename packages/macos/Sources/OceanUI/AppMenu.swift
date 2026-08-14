import OceanKit
import SwiftUI

/**
 The overflow menu, ported from `FileViewerView`'s `.menu`.

 Drawn rather than handed to SwiftUI's `Menu`, because an AppKit menu is a
 rounded, vibrant, system-tinted panel and none of those three things belong
 here. The cost is that a click outside the app's own bounds will not close it;
 selecting an item, pressing Escape, or clicking the trigger again all do.
 */
public struct AppMenu<Content: View>: View {
  private let icon: IconName
  private let label: String
  private let alignment: Alignment
  private let minWidth: CGFloat
  private let content: () -> Content

  @State private var open = false

  public init(
    icon: IconName = .more,
    label: String = "More",
    alignment: Alignment = .topTrailing,
    minWidth: CGFloat = 168,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.icon = icon
    self.label = label
    self.alignment = alignment
    self.minWidth = minWidth
    self.content = content
  }

  public var body: some View {
    IconButton(icon, label: label, size: 18, hit: 32) { open.toggle() }
      .overlay(alignment: alignment) {
        if open {
          MenuPanel(minWidth: minWidth, content: content)
            .environment(\.dismissMenu, DismissMenuAction { open = false })
            .fixedSize()
            // Clear the trigger: down from a top anchor, up from a bottom one.
            .offset(y: alignment.vertical == .top ? 32 + Space.s2 : -(32 + Space.s2))
            .zIndex(20)
          EscapeCatcher { open = false }
        }
      }
  }
}

/// The panel on its own, for callers that anchor it themselves — a command
/// palette above a composer, a server switcher under a title bar.
public struct MenuPanel<Content: View>: View {
  private let minWidth: CGFloat
  private let content: () -> Content

  @Environment(\.palette) private var palette

  public init(minWidth: CGFloat = 168, @ViewBuilder content: @escaping () -> Content) {
    self.minWidth = minWidth
    self.content = content
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      content()
    }
    .frame(minWidth: minWidth, alignment: .leading)
    .padding(.vertical, 4)
    .background(palette.surfaceRaised)
    .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section))
  }
}

/// One line in a menu. Flush left, mono, with the shortcut hint pushed to the
/// far edge. Destructive items are the accent — the only colour a menu carries.
public struct MenuRow: View {
  private let title: String
  private let icon: IconName?
  private let shortcut: String?
  private let destructive: Bool
  private let selected: Bool
  private let action: () -> Void

  @Environment(\.palette) private var palette
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.dismissMenu) private var dismissMenu
  @State private var hovering = false

  public init(
    _ title: String,
    icon: IconName? = nil,
    shortcut: String? = nil,
    destructive: Bool = false,
    selected: Bool = false,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.icon = icon
    self.shortcut = shortcut
    self.destructive = destructive
    self.selected = selected
    self.action = action
  }

  public var body: some View {
    Button {
      action()
      dismissMenu()
    } label: {
      HStack(spacing: Space.s2) {
        if let icon {
          AppIcon(icon, size: 14)
        }
        Text(title)
          .mono(12)
          .lineLimit(1)
        Spacer(minLength: Space.s3)
        if let shortcut {
          Text(shortcut)
            .mono(10)
            .foregroundStyle(palette.textDim)
        }
        if selected {
          AppIcon(.check, size: 12).foregroundStyle(palette.accent500)
        }
      }
      .foregroundStyle(foreground)
      .padding(.horizontal, Space.s3)
      .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
      .background(hovering && isEnabled ? palette.surfaceSunken : .clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .opacity(isEnabled ? 1 : 0.45)
    .onHover { hovering = $0 }
    .accessibilityAddTraits(selected ? [.isSelected] : [])
  }

  private var foreground: Color {
    if !isEnabled { return palette.textFaint }
    if destructive { return palette.accent500 }
    return hovering ? palette.text : palette.textSecondary
  }
}

public struct DismissMenuAction {
  private let close: () -> Void

  public init(_ close: @escaping () -> Void) {
    self.close = close
  }

  public func callAsFunction() {
    close()
  }
}

private struct DismissMenuKey: EnvironmentKey {
  static let defaultValue = DismissMenuAction {}
}

extension EnvironmentValues {
  /// Closes the menu a row belongs to. A row that stands outside one gets a
  /// no-op, so `MenuRow` is usable anywhere a small mono row is wanted.
  public var dismissMenu: DismissMenuAction {
    get { self[DismissMenuKey.self] }
    set { self[DismissMenuKey.self] = newValue }
  }
}
