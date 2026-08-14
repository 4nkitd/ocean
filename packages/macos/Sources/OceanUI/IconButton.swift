import OceanKit
import SwiftUI

/**
 An icon-only button: the header action, the sheet's close, the row's overflow.

 `label` is not optional because this control has no visible text — it is the
 accessibility name and the tooltip both, and a nameless icon button is a bug.
 */
public struct IconButton: View {
  public enum Tone: Sendable {
    case muted
    case dim
    case plain
    case accent
  }

  private let name: IconName
  private let label: String
  private let size: CGFloat
  private let hit: CGFloat
  private let tone: Tone
  private let bordered: Bool
  private let action: () -> Void

  @Environment(\.palette) private var palette
  @Environment(\.isEnabled) private var isEnabled
  @State private var hovering = false

  public init(
    _ name: IconName,
    label: String,
    size: CGFloat = 18,
    hit: CGFloat = 32,
    tone: Tone = .muted,
    bordered: Bool = false,
    action: @escaping () -> Void
  ) {
    self.name = name
    self.label = label
    self.size = size
    self.hit = hit
    self.tone = tone
    self.bordered = bordered
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      AppIcon(name, size: size)
        .foregroundStyle(foreground)
        .frame(width: hit, height: hit)
        .background(hovering && isEnabled ? palette.surfaceRaised : .clear)
        .overlay {
          if bordered {
            Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.row)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .opacity(isEnabled ? 1 : 0.45)
    .onHover { hovering = $0 }
    .accessibilityLabel(label)
    .help(label)
  }

  private var foreground: Color {
    guard isEnabled else { return palette.textFaint }
    if hovering { return tone == .accent ? palette.accent300 : palette.text }
    switch tone {
    case .muted: return palette.textMuted
    case .dim: return palette.textDim
    case .plain: return palette.text
    case .accent: return palette.accent500
    }
  }
}
