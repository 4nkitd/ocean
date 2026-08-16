import OceanKit
import SwiftUI

/// The small square file-type chip that precedes a filename everywhere.
public struct TypeBadge: View {
  private let filename: String
  private let size: CGFloat

  @Environment(\.palette) private var palette

  public init(_ filename: String, size: CGFloat = 18) {
    self.filename = filename
    self.size = size
  }

  public var body: some View {
    let badge = FileType.badge(for: filename)
    Text(badge.code)
      .font(OceanFont.mono(9, weight: .bold))
      .foregroundStyle(foreground(badge.tone))
      .lineLimit(1)
      .minimumScaleFactor(0.75)
      .frame(width: size, height: size)
      .background(background(badge.tone))
      .accessibilityHidden(true)
  }

  /// Three-character codes need a step down to stay inside the square.
  private func fontSize(_ code: String) -> CGFloat {
    code.count > 2 ? size * 0.4 : size * 0.45
  }

  private func background(_ tone: FileTypeTone) -> Color {
    switch tone {
    case .accent: return palette.accent500
    case .accentSoft: return palette.accent400
    case .neutral, .dim: return palette.surfaceSunken
    }
  }

  private func foreground(_ tone: FileTypeTone) -> Color {
    switch tone {
    case .accent, .accentSoft: return palette.surface
    case .neutral: return palette.textSecondary
    case .dim: return palette.textDim
    }
  }
}
