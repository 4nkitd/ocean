import OceanKit
import OceanUI
import SwiftUI

/**
 Ocean for macOS — Main Native Application Entry.

 Provides the top-level window group hosting `DesktopLayout`, wires up the global
 `Appearance` store, initialises `ConnectionStore`, and configures native macOS
 menu bar commands and keyboard shortcuts.
 */
@main
struct OceanApp: App {
  @State private var appearance = Appearance.shared
  @State private var connectionStore = ConnectionStore.shared

  var body: some Scene {
    WindowGroup("Ocean") {
      DesktopLayout()
        .oceanAppearance(appearance)
        .environment(connectionStore)
        .frame(minWidth: 900, minHeight: 600)
        .task {
          _ = await connectionStore.restoreSession()
        }
    }
    .defaultSize(width: 1280, height: 850)
    .commands {
      SidebarCommands()

      CommandGroup(replacing: .appInfo) {
        Button("About Ocean") {
          NSApp.orderFrontStandardAboutPanel()
        }
      }

      CommandMenu("View") {
        Picker("Theme Mode", selection: appearance.themeBinding) {
          ForEach(ThemeMode.allCases, id: \.self) { mode in
            Text(mode.title).tag(mode)
          }
        }

        Picker("Contrast Mode", selection: appearance.contrastBinding) {
          ForEach(ContrastMode.allCases, id: \.self) { mode in
            Text(mode.title).tag(mode)
          }
        }
      }
    }
  }
}
