import OceanKit
import SwiftUI

/// The `.label` role from `base.css`: small, uppercase, wide-tracked mono, muted.
/// Used as a kicker above a field, a section heading, a state block's title.
public struct SectionLabel: View {
  @Environment(\.palette) private var palette

  private let text: String
  private let color: Color?

  public init(_ text: String, color: Color? = nil) {
    self.text = text
    self.color = color
  }

  public var body: some View {
    Text(text.uppercased())
      .label()
      .foregroundStyle(color ?? palette.textMuted)
  }
}

/// Mono, for a path, a count, a timestamp, an id or a model name.
public struct MonoText: View {
  @Environment(\.palette) private var palette

  private let text: String
  private let size: CGFloat
  private let weight: Font.Weight
  private let color: Color?

  public init(
    _ text: String,
    size: CGFloat = 13,
    weight: Font.Weight = .regular,
    color: Color? = nil
  ) {
    self.text = text
    self.size = size
    self.weight = weight
    self.color = color
  }

  public var body: some View {
    Text(text)
      .mono(size, weight: weight)
      .foregroundStyle(color ?? palette.text)
  }
}
