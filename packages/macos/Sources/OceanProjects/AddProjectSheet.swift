import AppKit
import OceanKit
import OceanUI
import SwiftUI

public struct AddProjectSheet: View {
  private let startPath: String
  private let onSelect: (String?) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.palette) private var palette

  public init(startPath: String = "/", onSelect: @escaping (String?) -> Void) {
    self.startPath = startPath
    self.onSelect = onSelect
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Space.s5) {
      HStack {
        SectionLabel("ADD PROJECT")
        Spacer()
        IconButton(.close, label: "Close", size: 18) {
          onSelect(nil)
          dismiss()
        }
      }

      VStack(alignment: .leading, spacing: Space.s2) {
        Text("Select a Project Directory")
          .font(OceanFont.body(20, weight: .bold))
          .foregroundStyle(palette.text)

        Text("Choose a folder on this Mac to open as a project.")
          .bodyText(13.5)
          .foregroundStyle(palette.textMuted)
      }

      AppButton("Browse with Finder…", variant: .primary, icon: .folder) {
        openNativePanel()
      }

      RuleLine(.section)

      AppButton("Cancel", variant: .secondary, icon: .close) {
        onSelect(nil)
        dismiss()
      }
    }
    .padding(Space.s6)
    .frame(width: 420)
    .background(palette.surface)
    .onAppear {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        openNativePanel()
      }
    }
  }

  private func openNativePanel() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Open Project"

    if !startPath.isEmpty && startPath != "/" {
      panel.directoryURL = URL(fileURLWithPath: startPath)
    }

    if panel.runModal() == .OK, let url = panel.url {
      let path = url.path
      onSelect(path)
      dismiss()
    }
  }
}
