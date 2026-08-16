import AppKit
import OceanKit
import OceanUI
import SwiftUI

public struct ProjectsView: View {
  @State private var store: ProjectsStore

  private let onSelectProject: (String) -> Void
  private let onOpenServerSettings: () -> Void

  @Environment(\.palette) private var palette

  public init(
    store: ProjectsStore? = nil,
    onSelectProject: @escaping (String) -> Void,
    onOpenServerSettings: @escaping () -> Void = {}
  ) {
    _store = State(initialValue: store ?? ProjectsStore())
    self.onSelectProject = onSelectProject
    self.onOpenServerSettings = onOpenServerSettings
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      headerView

      ScrollView {
        VStack(alignment: .leading, spacing: Space.s4) {
          if store.loading {
            StateBlock(.loading, label: "Projects", message: "Asking the server what it has open…")
          } else if let err = store.error {
            StateBlock(.error, label: "Could not load projects", message: err) {
              Task { await store.refresh() }
            }
          } else if store.projects.isEmpty {
            StateBlock(
              .empty,
              label: "Nothing open",
              message: "This server has not opened a project directory yet. Add one below to browse it."
            )
          } else if store.filteredProjects.isEmpty {
            StateBlock(
              .empty,
              label: "No matches",
              message: "Nothing here matches “\(store.query)”."
            )
          } else {
            LazyVStack(spacing: 0) {
              ForEach(Array(store.filteredProjects.enumerated()), id: \.element.id) { index, project in
                VStack(spacing: 0) {
                  ProjectCard(
                    project: project,
                    active: project.id == store.activeProjectId,
                    reordering: store.reordering,
                    canMoveUp: index > 0,
                    canMoveDown: index < store.filteredProjects.count - 1,
                    onSelect: { onSelectProject(project.worktree) },
                    onMove: { delta in store.move(project.id, delta: delta) },
                    onFavourite: { store.toggleFavourite(project.id) }
                  )
                  RuleLine(.row)
                }
              }
            }
            .background(palette.surface)
            .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section))
          }
        }
        .padding(Space.s6)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(palette.bg)
    .task {
      if store.projects.isEmpty {
        await store.refresh()
      }
    }
  }

  private var headerView: some View {
    VStack(alignment: .leading, spacing: Space.s3) {
      HStack {
        HStack(spacing: Space.s2) {
          Rectangle()
            .fill(palette.accent)
            .frame(width: 7, height: 7)
          Text(ConnectionStore.shared.serverLabel.uppercased())
            .mono(11)
            .tracking(0.12 * 11)
            .foregroundStyle(palette.textMuted)
        }
        Spacer()
        HStack(spacing: Space.s2) {
          IconButton(.refresh, label: "Refresh projects", size: 18) {
            Task { await store.refresh() }
          }
          IconButton(.gear, label: "Server settings", size: 18) {
            onOpenServerSettings()
          }
        }
      }

      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Projects")
            .font(OceanFont.body(30, weight: .bold))
            .foregroundStyle(palette.text)

          Text(store.loading ? "Asking the server…" : store.summary)
            .mono(11)
            .foregroundStyle(palette.textMuted)
        }

        Spacer()

        Button {
          store.reordering.toggle()
        } label: {
          Text(store.reordering ? "Done" : "Reorder")
            .mono(11)
            .foregroundStyle(store.projects.count < 2 ? palette.textDim : palette.accent500)
        }
        .buttonStyle(.plain)
        .disabled(store.projects.count < 2)
      }

      HStack(spacing: Space.s2) {
        HStack(spacing: Space.s2) {
          AppIcon(.search, size: 14)
            .foregroundStyle(palette.textDim)
          TextField("Filter projects", text: $store.query)
            .textFieldStyle(.plain)
            .font(OceanFont.mono(12.5))
            .foregroundStyle(palette.text)
            .disabled(store.loading)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 8)
        .background(palette.surfaceRaised)
        .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section))

        AppButton(
           "Add project",
           variant: .secondary,
           icon: .plus,
           action: openAddProjectPanel
         )
         .disabled(store.loading)
      }
    }
    .padding(Space.s6)
    .background(palette.surface)
    .overlay(alignment: .bottom) { RuleLine(.section) }
  }

  private func openAddProjectPanel() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Open Project"

    if let startPath = ConnectionStore.shared.workingDirectory, startPath != "/" {
      panel.directoryURL = URL(fileURLWithPath: startPath)
    }

    guard panel.runModal() == .OK, let url = panel.url else { return }
    onSelectProject(url.path)
  }
}
