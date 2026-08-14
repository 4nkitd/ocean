import AppKit
import Observation
import SwiftUI

public enum ThemeMode: String, CaseIterable, Sendable, Codable {
  case system, dark, light

  public var title: String {
    switch self {
    case .system: return "System"
    case .dark: return "Dark"
    case .light: return "Light"
    }
  }
}

public enum ContrastMode: String, CaseIterable, Sendable, Codable {
  case normal, high

  public var title: String {
    switch self {
    case .normal: return "Normal"
    case .high: return "High"
    }
  }
}

/// What `themeMode` collapses to once `system` has been asked what it wants.
public enum ResolvedTheme: String, Sendable, Codable {
  case dark, light
}

/**
 Theme and contrast state, ported from `../mobile/src/stores/appearance.ts`.

 Same shape as the Vue store: a mode of system/dark/light crossed with
 normal/high contrast, both persisted, with `system` following the OS live. The
 Vue version is a module singleton, so this one is too — `Appearance.shared` is
 the app's, and a fresh instance is only useful to previews.
 */
@Observable
@MainActor
public final class Appearance {
  public static let shared = Appearance()

  private static let themeKey = "opencode.theme"
  private static let contrastKey = "opencode.contrast"

  public private(set) var themeMode: ThemeMode
  public private(set) var contrastMode: ContrastMode
  private var systemDark: Bool

  @ObservationIgnored private var systemObserver: NSObjectProtocol?
  @ObservationIgnored private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    themeMode = ThemeMode(rawValue: defaults.string(forKey: Self.themeKey) ?? "") ?? .system
    contrastMode = ContrastMode(rawValue: defaults.string(forKey: Self.contrastKey) ?? "") ?? .normal
    systemDark = Self.systemPrefersDark()

    systemObserver = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.systemDark = Self.systemPrefersDark()
        self.applyToAppKit()
      }
    }

    applyToAppKit()
  }

  deinit {
    if let systemObserver {
      DistributedNotificationCenter.default().removeObserver(systemObserver)
    }
  }

  public var resolvedTheme: ResolvedTheme {
    guard themeMode == .system else {
      return themeMode == .dark ? .dark : .light
    }
    return systemDark ? .dark : .light
  }

  /// Every token, already resolved. Views read this and nothing else.
  public var palette: Palette {
    Palette.resolve(resolvedTheme, contrastMode)
  }

  public func setThemeMode(_ next: ThemeMode) {
    themeMode = next
    defaults.set(next.rawValue, forKey: Self.themeKey)
    applyToAppKit()
  }

  public func setContrastMode(_ next: ContrastMode) {
    contrastMode = next
    defaults.set(next.rawValue, forKey: Self.contrastKey)
  }

  public var themeBinding: Binding<ThemeMode> {
    Binding(get: { self.themeMode }, set: { self.setThemeMode($0) })
  }

  public var contrastBinding: Binding<ContrastMode> {
    Binding(get: { self.contrastMode }, set: { self.setContrastMode($0) })
  }

  /// SwiftUI only themes what SwiftUI draws. Menus, sheets, the title bar and
  /// scrollers come from AppKit and need the override pinned on `NSApp`, or a
  /// light app on a dark system keeps a dark menu bar dropdown.
  private func applyToAppKit() {
    guard NSApp != nil else { return }
    switch themeMode {
    case .system: NSApp.appearance = nil
    case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
    case .light: NSApp.appearance = NSAppearance(named: .aqua)
    }
  }

  /// Read the defaults key rather than `NSApp.effectiveAppearance`: the
  /// distributed notification lands before AppKit refreshes the app's
  /// appearance, so at the moment we are told it changed, NSApp still reports
  /// the value we already had.
  private static func systemPrefersDark() -> Bool {
    let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? ""
    return style.lowercased().contains("dark")
  }
}

private struct PaletteKey: EnvironmentKey {
  static let defaultValue = Palette.dark
}

extension EnvironmentValues {
  /// `@Environment(\.palette) private var palette` — the only legitimate source
  /// of colour in a view.
  public var palette: Palette {
    get { self[PaletteKey.self] }
    set { self[PaletteKey.self] = newValue }
  }
}

extension View {
  /// Root of the app: publishes the store, its resolved palette, and the
  /// scheme SwiftUI's own controls should adopt.
  public func oceanAppearance(_ appearance: Appearance) -> some View {
    self
      .environment(appearance)
      .oceanPalette(appearance.palette)
      .preferredColorScheme(appearance.palette.colorScheme)
  }

  /// Publishes a palette without a store behind it — previews, the gallery, and
  /// any subtree that has to be drawn in a fixed theme.
  public func oceanPalette(_ palette: Palette) -> some View {
    self
      .environment(\.palette, palette)
      .environment(\.colorScheme, palette.colorScheme)
      .tint(palette.accent)
      .foregroundStyle(palette.text)
      .font(OceanFont.body())
  }
}
