import OceanKit
import SwiftUI

/// The bar that names a section of a list, ported from `GitView`'s
/// `.section__head`: raised surface, the kicker flush left, whatever the caller
/// puts at the far edge, and a rule underneath.
public struct SectionHeader<Trailing: View>: View {
  private let title: String
  private let accent: Bool
  private let trailing: () -> Trailing

  @Environment(\.palette) private var palette

  public init(
    _ title: String,
    accent: Bool = false,
    @ViewBuilder trailing: @escaping () -> Trailing
  ) {
    self.title = title
    self.accent = accent
    self.trailing = trailing
  }

  public var body: some View {
    HStack(spacing: Space.s3) {
      SectionLabel(title, color: accent ? palette.accent : nil)
      Spacer(minLength: Space.s3)
      trailing()
    }
    .padding(.horizontal, Space.s5)
    .padding(.vertical, Space.s3)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(palette.surfaceRaised)
    .overlay(alignment: .bottom) { RuleLine(.section) }
  }
}

extension SectionHeader where Trailing == EmptyView {
  public init(_ title: String, accent: Bool = false) {
    self.init(title, accent: accent, trailing: { EmptyView() })
  }
}
