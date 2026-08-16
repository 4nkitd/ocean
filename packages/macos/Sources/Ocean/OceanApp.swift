import OceanKit
import OceanUI
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  private static let frameKey = "ocean.window.frame"

  func applicationDidFinishLaunching(_ notification: Notification) {
    SessionNotifier.shared.start()

    if let savedFrame = UserDefaults.standard.string(forKey: Self.frameKey) {
      DispatchQueue.main.async {
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) ?? NSApp.windows.first {
          window.setFrame(from: savedFrame)
        }
      }
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidMoveOrResize(_:)),
      name: NSWindow.didMoveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidMoveOrResize(_:)),
      name: NSWindow.didResizeNotification,
      object: nil
    )
  }

  func applicationWillTerminate(_ notification: Notification) {
    saveWindowFrame()
  }

  @objc private func windowDidMoveOrResize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window.canBecomeMain else { return }
    UserDefaults.standard.set(window.frameDescriptor, forKey: Self.frameKey)
  }

  private func saveWindowFrame() {
    if let window = NSApp.windows.first(where: { $0.canBecomeMain }) ?? NSApp.windows.first {
      UserDefaults.standard.set(window.frameDescriptor, forKey: Self.frameKey)
    }
  }
}

/**
 Ocean for macOS — Main Native Application Entry.

 Provides the top-level window group hosting `DesktopLayout`, wires up the global
 `Appearance` store, initialises `ConnectionStore`, and configures native macOS
 menu bar commands and keyboard shortcuts.
 */
@main
struct OceanApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var appearance = Appearance.shared
  @State private var connectionStore = ConnectionStore.shared

  var body: some Scene {
    WindowGroup("Ocean") {
      DesktopLayout()
        .oceanAppearance(appearance)
        .environment(connectionStore)
        .environmentObject(DeepLinkHandler.shared)
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
          SessionNotifier.shared.start()
        }
        .task {
          _ = await connectionStore.restoreSession()
        }
        .onOpenURL { url in
          DeepLinkHandler.shared.handle(url)
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

      CommandGroup(replacing: .appSettings) {
        Button("Settings…") {
          NotificationCenter.default.post(name: Notification.Name("ocean.openSettings"), object: nil)
        }
        .keyboardShortcut(",", modifiers: .command)
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

      CommandMenu("Window") {
        Button("Show Chat") {
          NotificationCenter.default.post(name: Notification.Name("ocean.openChat"), object: nil)
        }
        .keyboardShortcut("1", modifiers: .command)
      }
    }
  }
}
