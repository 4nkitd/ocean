import OceanKit
import SwiftUI

/// A divider, so nobody has to remember whether this one is 2px or 1px.
/// 2px between sections, 1px between rows — and the two take different colours.
public struct RuleLine: View {
  public enum Weight: Sendable {
    case section
    case row
  }

  @Environment(\.palette) private var palette

  private let weight: Weight
  private let axis: Axis
  private let color: Color?

  public init(_ weight: Weight = .row, axis: Axis = .horizontal, color: Color? = nil) {
    self.weight = weight
    self.axis = axis
    self.color = color
  }

  /// Note: vertical RuleLine requires a bounded height parent container (e.g. .frame(height: ...)).
  public var body: some View {
    Rectangle()
      .fill(color ?? defaultColor)
      .frame(
        width: axis == .horizontal ? nil : thickness,
        height: axis == .horizontal ? thickness : nil
      )
  }

  private var thickness: CGFloat {
    weight == .section ? RuleWidth.section : RuleWidth.row
  }

  private var defaultColor: Color {
    weight == .section ? palette.rule : palette.ruleHair
  }
}
