import OceanKit
import SwiftUI

/**
 The small bordered mono tag: "RELAY", "READ ONLY", a branch name, a count.

 `uppercased` is off for the cases where the string is data rather than a word —
 a branch is `feat/sse-retry`, not `FEAT/SSE-RETRY`.
 */
public struct Chip: View {
  public enum Tone: Sendable {
    /// Bordered, muted. The default.
    case neutral
    /// Filled with the sunken surface, accent ink. A chip that is switched on.
    case on
    /// Filled with the accent. Reserve it for one thing per screen.
    case accent
  }

  private let text: String
  private let tone: Tone
  private let icon: IconName?
  private let uppercased: Bool

  @Environment(\.palette) private var palette

  public init(
    _ text: String,
    tone: Tone = .neutral,
    icon: IconName? = nil,
    uppercased: Bool = true
  ) {
    self.text = text
    self.tone = tone
    self.icon = icon
    self.uppercased = uppercased
  }

  public var body: some View {
    HStack(spacing: 5) {
      if let icon {
        AppIcon(icon, size: 11)
      }
      Text(uppercased ? text.uppercased() : text)
        .font(OceanFont.mono(10))
        .tracking(uppercased ? 0.1 * 10 : 0)
        .lineLimit(1)
    }
    .foregroundStyle(foreground)
    .padding(.horizontal, Space.s2)
    .padding(.vertical, 4)
    .background(background)
    .overlay(Rectangle().strokeBorder(border, lineWidth: RuleWidth.row))
    .accessibilityElement(children: .combine)
  }

  private var foreground: Color {
    switch tone {
    case .neutral: return palette.textMuted
    case .on: return palette.accent500
    case .accent: return palette.onAccent
    }
  }

  private var background: Color {
    switch tone {
    case .neutral: return .clear
    case .on: return palette.surfaceSunken
    case .accent: return palette.accent
    }
  }

  private var border: Color {
    switch tone {
    case .neutral: return palette.rule
    case .on: return palette.surfaceSunken
    case .accent: return palette.accent
    }
  }
}

/// The 7px square that stands in for a status light. No round dot exists in
/// this design, and a grey one reads as disabled rather than idle — hence
/// `ok` for connected, `accent` for live, `dim` for stopped.
public struct StatusDot: View {
  public enum Tone: Sendable {
    case accent
    case ok
    case muted
    case dim
    case faint
  }

  private let tone: Tone
  private let size: CGFloat

  @Environment(\.palette) private var palette

  public init(_ tone: Tone = .accent, size: CGFloat = 7) {
    self.tone = tone
    self.size = size
  }

  public var body: some View {
    Rectangle()
      .fill(color)
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }

  private var color: Color {
    switch tone {
    case .accent: return palette.accent
    case .ok: return palette.ok
    case .muted: return palette.textMuted
    case .dim: return palette.textDim
    case .faint: return palette.textFaint
    }
  }
}
