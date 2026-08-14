import SwiftUI

/**
 The Modernist token set, ported from `../mobile/src/styles/tokens.css`.

 The CSS ships one dark base plus three override blocks that cascade onto it.
 Cascades do not exist here, so the four combinations are written out flat —
 each value below is the one the browser would have resolved. Ramp steps keep
 their upstream names, so `accent500` is the same `#ff563c` in the dark base and
 in its high-contrast variant.
 */
public struct Palette: Sendable, Equatable, Identifiable {
  public let scheme: ResolvedTheme
  public let contrast: ContrastMode

  public let bg: Color
  public let surface: Color
  public let surfaceRaised: Color
  public let surfaceSunken: Color

  public let rule: Color
  public let ruleHair: Color

  public let text: Color
  public let textSecondary: Color
  public let textMuted: Color
  public let textDim: Color
  public let textFaint: Color

  public let accent: Color
  public let accent300: Color
  public let accent400: Color
  public let accent500: Color
  public let accent600: Color
  public let accent700: Color
  public let onAccent: Color

  public let ok: Color
  public let scrim: Color

  public let diffAddBg: Color
  public let diffDelBg: Color
  public let diffDelText: Color

  public var id: String { name }

  /// `dark`, `dark-high`, `light`, `light-high` — the same pair the Vue client
  /// writes onto `data-theme` / `data-contrast`.
  public var name: String {
    contrast == .high ? "\(scheme.rawValue)-high" : scheme.rawValue
  }

  public var isDark: Bool { scheme == .dark }

  public var colorScheme: ColorScheme { scheme == .dark ? .dark : .light }
}

extension Palette {
  init(
    scheme: ResolvedTheme,
    contrast: ContrastMode,
    bg: UInt32,
    surface: UInt32,
    surfaceRaised: UInt32,
    surfaceSunken: UInt32,
    rule: UInt32,
    ruleHair: UInt32,
    text: UInt32,
    textSecondary: UInt32,
    textMuted: UInt32,
    textDim: UInt32,
    textFaint: UInt32,
    accent: UInt32,
    accent300: UInt32,
    accent400: UInt32,
    accent500: UInt32,
    accent600: UInt32,
    accent700: UInt32,
    onAccent: UInt32,
    ok: UInt32,
    scrim: Double,
    diffAddBg: UInt32,
    diffDelBg: UInt32,
    diffDelText: UInt32
  ) {
    self.scheme = scheme
    self.contrast = contrast
    self.bg = Color(hex: bg)
    self.surface = Color(hex: surface)
    self.surfaceRaised = Color(hex: surfaceRaised)
    self.surfaceSunken = Color(hex: surfaceSunken)
    self.rule = Color(hex: rule)
    self.ruleHair = Color(hex: ruleHair)
    self.text = Color(hex: text)
    self.textSecondary = Color(hex: textSecondary)
    self.textMuted = Color(hex: textMuted)
    self.textDim = Color(hex: textDim)
    self.textFaint = Color(hex: textFaint)
    self.accent = Color(hex: accent)
    self.accent300 = Color(hex: accent300)
    self.accent400 = Color(hex: accent400)
    self.accent500 = Color(hex: accent500)
    self.accent600 = Color(hex: accent600)
    self.accent700 = Color(hex: accent700)
    self.onAccent = Color(hex: onAccent)
    self.ok = Color(hex: ok)
    // `color-mix(in srgb, #000 N%, transparent)` — black at N% alpha.
    self.scrim = Color.black.opacity(scrim)
    self.diffAddBg = Color(hex: diffAddBg)
    self.diffDelBg = Color(hex: diffDelBg)
    self.diffDelText = Color(hex: diffDelText)
  }
}

extension Palette {
  public static let dark = Palette(
    scheme: .dark,
    contrast: .normal,
    bg: 0x0b0a0a,
    surface: 0x141312,
    surfaceRaised: 0x1c1a19,
    surfaceSunken: 0x232120,
    rule: 0x322f2e,
    ruleHair: 0x232120,
    text: 0xf3f2f2,
    textSecondary: 0xbab6b6,
    textMuted: 0x8c8888,
    textDim: 0x605d5d,
    textFaint: 0x4d4a4a,
    accent: 0xec3013,
    accent300: 0xffc4b8,
    accent400: 0xff9783,
    accent500: 0xff563c,
    accent600: 0xdd2b0f,
    accent700: 0xae1800,
    onAccent: 0xffffff,
    ok: 0x52b788,
    scrim: 0.62,
    diffAddBg: 0x1c1a19,
    diffDelBg: 0x181716,
    diffDelText: 0x7d7979
  )

  public static let darkHighContrast = Palette(
    scheme: .dark,
    contrast: .high,
    bg: 0x0b0a0a,
    surface: 0x141312,
    surfaceRaised: 0x1c1a19,
    surfaceSunken: 0x232120,
    rule: 0x696969,
    ruleHair: 0x4d4d4d,
    text: 0xffffff,
    textSecondary: 0xeeeeee,
    textMuted: 0xd0d0d0,
    textDim: 0xadadad,
    textFaint: 0x909090,
    accent: 0xff593d,
    accent300: 0xffd0c7,
    accent400: 0xff9b89,
    accent500: 0xff735b,
    accent600: 0xdd2b0f,
    accent700: 0xae1800,
    onAccent: 0xffffff,
    ok: 0x6fd6a3,
    scrim: 0.62,
    diffAddBg: 0x1c1a19,
    diffDelBg: 0x181716,
    diffDelText: 0x7d7979
  )

  public static let light = Palette(
    scheme: .light,
    contrast: .normal,
    bg: 0xf3f1ef,
    surface: 0xffffff,
    surfaceRaised: 0xf5f2ef,
    surfaceSunken: 0xe8e4df,
    rule: 0xcbc4be,
    ruleHair: 0xe4dfdb,
    text: 0x1b1918,
    textSecondary: 0x514b47,
    textMuted: 0x6b645f,
    textDim: 0x877e77,
    textFaint: 0x9c9188,
    accent: 0xc52b12,
    accent300: 0x9e1e0b,
    accent400: 0xb52510,
    accent500: 0xd33a20,
    accent600: 0xa9200d,
    accent700: 0x851705,
    onAccent: 0xffffff,
    ok: 0x1f7a52,
    scrim: 0.42,
    diffAddBg: 0xe9f0e8,
    diffDelBg: 0xf3e9e7,
    diffDelText: 0x7d6964
  )

  /// Both high-contrast blocks apply to a light+high document; the
  /// `[data-theme="light"][data-contrast="high"]` one is more specific and wins
  /// wherever the two overlap. What is left from the plain light theme is the
  /// 600/700 ramp steps, `on-accent` and the 42% scrim.
  public static let lightHighContrast = Palette(
    scheme: .light,
    contrast: .high,
    bg: 0xffffff,
    surface: 0xffffff,
    surfaceRaised: 0xf0f0f0,
    surfaceSunken: 0xe4e4e4,
    rule: 0x555555,
    ruleHair: 0x999999,
    text: 0x000000,
    textSecondary: 0x1a1a1a,
    textMuted: 0x3d3d3d,
    textDim: 0x666666,
    textFaint: 0x777777,
    accent: 0xa9210d,
    accent300: 0x7f1708,
    accent400: 0x941c0b,
    accent500: 0xb42a14,
    accent600: 0xa9200d,
    accent700: 0x851705,
    onAccent: 0xffffff,
    ok: 0x10603c,
    scrim: 0.42,
    diffAddBg: 0xe3f0e2,
    diffDelBg: 0xf5e5e2,
    diffDelText: 0x5f4b46
  )

  public static let all: [Palette] = [dark, darkHighContrast, light, lightHighContrast]

  public static func resolve(_ scheme: ResolvedTheme, _ contrast: ContrastMode) -> Palette {
    switch (scheme, contrast) {
    case (.dark, .normal): return .dark
    case (.dark, .high): return .darkHighContrast
    case (.light, .normal): return .light
    case (.light, .high): return .lightHighContrast
    }
  }
}

/// `--space-1` … `--space-6`, density 1.00x.
public enum Space {
  public static let s1: CGFloat = 4
  public static let s2: CGFloat = 8
  public static let s3: CGFloat = 12
  public static let s4: CGFloat = 16
  public static let s5: CGFloat = 20
  public static let s6: CGFloat = 24
}

/// 2px separates sections, 1px separates rows. Never guess which.
public enum RuleWidth {
  public static let section: CGFloat = 2
  public static let row: CGFloat = 1
}

/// `--radius: 0px`. Here so the intent is greppable, not so anyone reads it.
public enum Radius {
  public static let all: CGFloat = 0
}

extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xff) / 255,
      green: Double((hex >> 8) & 0xff) / 255,
      blue: Double(hex & 0xff) / 255,
      opacity: 1
    )
  }
}
