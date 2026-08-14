import OceanKit
import SwiftUI

/**
 A block of explanation set apart from the flow, ported from the `callout` in
 `ConnectView`, `HandshakeView` and `FilesView`.

 Two shapes: `.accent` is the raised surface with a 2px accent rule down its
 leading edge — the one that says "read this"; `.outlined` is a plain 2px box
 for something merely informational. `StateBlock(.error:)` is the third cousin
 and stays where it is, because an error needs a retry and this does not.
 */
public struct Callout<Content: View>: View {
  public enum Variant: Sendable {
    case accent
    case outlined
  }

  private let kicker: String?
  private let variant: Variant
  private let content: () -> Content

  @Environment(\.palette) private var palette

  public init(
    _ kicker: String? = nil,
    variant: Variant = .accent,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.kicker = kicker
    self.variant = variant
    self.content = content
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Space.s2) {
      if let kicker {
        SectionLabel(kicker, color: variant == .accent ? palette.accent : nil)
      }
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 18)
    .padding(.vertical, Space.s4)
    .background(variant == .accent ? palette.surfaceRaised : .clear)
    .overlay(alignment: .leading) {
      if variant == .accent {
        RuleLine(.section, axis: .vertical, color: palette.accent)
      }
    }
    .overlay {
      if variant == .outlined {
        Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section)
      }
    }
  }
}

extension Callout where Content == CalloutText {
  public init(_ kicker: String? = nil, message: String, variant: Variant = .accent) {
    self.init(kicker, variant: variant) { CalloutText(message) }
  }
}

public struct CalloutText: View {
  private let message: String

  @Environment(\.palette) private var palette

  public init(_ message: String) {
    self.message = message
  }

  public var body: some View {
    Text(message)
      .bodyText(13.5)
      .foregroundStyle(palette.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
