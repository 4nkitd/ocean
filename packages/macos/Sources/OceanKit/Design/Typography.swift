import SwiftUI

/**
 The type roles from `base.css`.

 Archivo is not installed and shipping a webfont into a native app to match a
 browser is the wrong trade, so body and heading are SF. Archivo's headings are
 heavy and tightly tracked; SF Display at `.bold` with -0.02em gets close enough
 that the two clients read as the same design. Monospace stays what the CSS asks
 for — `ui-monospace`, which on this platform is SF Mono.
 */
public enum OceanFont {
  /// `--font-body`, 15px/1.55 in the CSS.
  public static func body(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .default)
  }

  /// `--font-heading`: bold and tight. Pair with `Tracking.heading(size)`.
  public static func heading(_ size: CGFloat = 20, weight: Font.Weight = .bold) -> Font {
    .system(size: size, weight: weight, design: .default)
  }

  /// `--font-mono`. Every path, count, timestamp, id and model name.
  public static func mono(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
  }

  /// The `.label` role: 11px mono, uppercase, wide-tracked, muted.
  public static let label = mono(11)

  public static let labelSize: CGFloat = 11
}

public enum Tracking {
  /// -0.02em.
  public static func heading(_ size: CGFloat) -> CGFloat { -0.02 * size }
  /// 0.14em.
  public static func label(_ size: CGFloat = OceanFont.labelSize) -> CGFloat { 0.14 * size }
}

public enum LineHeight {
  /// `line-height: 1.55` on 15px body, expressed as SwiftUI's extra leading.
  public static func body(_ size: CGFloat = 15) -> CGFloat { max(0, size * 1.55 - size * 1.2) }
  /// `line-height: 1.05` — headings sit almost solid.
  public static func heading(_ size: CGFloat) -> CGFloat { 0 }
}

extension Text {
  public func heading(_ size: CGFloat = 20, weight: Font.Weight = .bold) -> Text {
    font(OceanFont.heading(size, weight: weight)).tracking(Tracking.heading(size))
  }

  public func bodyText(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Text {
    font(OceanFont.body(size, weight: weight))
  }

  public func mono(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Text {
    font(OceanFont.mono(size, weight: weight))
  }

  /// Does not uppercase the string — `SectionLabel` does that, so a label built
  /// from a path or an id keeps its own casing when it has to.
  public func label(_ size: CGFloat = OceanFont.labelSize) -> Text {
    font(OceanFont.mono(size)).tracking(Tracking.label(size))
  }
}
