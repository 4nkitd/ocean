import OceanKit
import SwiftUI

/**
 A determinate bar: context used, upload progress, a handshake's steps.

 The Vue client has none — a phone shows a percentage in mono text and leaves it
 there — but a desktop pane has the width to show the shape of it. Square ends,
 obviously, and the fill only turns accent once it is worth worrying about;
 below that it is the muted step, so a half-full bar is not an alarm.
 */
public struct ProgressBar: View {
  private let value: Double
  private let height: CGFloat
  private let warnAbove: Double
  private let tint: Color?

  @Environment(\.palette) private var palette

  public init(
    value: Double,
    height: CGFloat = 4,
    warnAbove: Double = 0.8,
    tint: Color? = nil
  ) {
    self.value = value
    self.height = height
    self.warnAbove = warnAbove
    self.tint = tint
  }

  public var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Rectangle().fill(palette.surfaceSunken)
        Rectangle()
          .fill(tint ?? (clamped >= warnAbove ? palette.accent : palette.textMuted))
          .frame(width: geometry.size.width * clamped)
      }
    }
    .frame(height: height)
    .accessibilityElement()
    .accessibilityValue("\(Int(clamped * 100)) percent")
  }

  private var clamped: Double { min(max(value, 0), 1) }
}
