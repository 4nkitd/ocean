import OceanKit
import OceanUI
import SwiftUI

public struct FilesView: View {
  @Bindable public var store: FilesStore
  public var onOpenFile: ((String) -> Void)?
  public var onOpenProjects: (() -> Void)?

  @Environment(\.palette) private var palette
  @State private var hoverPath: String? = nil

  public init(
    store: FilesStore,
    onOpenFile: ((String) -> Void)? = nil,
    onOpenProjects: (() -> Void)? = nil
  ) {
    self.store = store
    self.onOpenFile = onOpenFile
    self.onOpenProjects = onOpenProjects
  }

  private var drilledIn: Bool {
    store.filterOpen || store.currentPath != store.directory
  }

  private var contextLine: String {
    var parts = [Formatters.displayPath(store.directory), "\(store.fileCount) files loaded"]
    if !store.isRepo { parts.append("not a repository") }
    return parts.joined(separator: " · ")
  }

  public var body: some View {
    VStack(spacing: 0) {
      // Header
      VStack(alignment: .leading, spacing: Space.s2) {
        if !drilledIn {
          HStack(spacing: Space.s2) {
            SectionLabel("FILES")

            Text("·")
              .mono(11)
              .foregroundStyle(palette.textDim)

            Text("\(store.fileCount) files loaded")
              .mono(11)
              .foregroundStyle(palette.textMuted)

            Spacer()

            if let onOpenProjects {
              IconButton(.grid, label: "All projects", size: 16) {
                onOpenProjects()
              }
            }

            IconButton(.search, label: "Filter files", size: 16) {
              store.setFilterOpen(true)
            }
          }
        } else {
          // Drilled in breadcrumbs + Filter bar
          Breadcrumbs(store.crumbs) { crumb in
            if crumb.id == store.directory {
              store.setFilterOpen(false)
            }
            store.currentPath = crumb.id
          }

          HStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
              AppIcon(.search, size: 15)
                .foregroundStyle(palette.textDim)

              TextField("Filter files", text: $store.query)
                .textFieldStyle(.plain)
                .font(OceanFont.mono(13))
                .foregroundStyle(palette.text)

              if !store.query.isEmpty {
                Button {
                  store.query = ""
                } label: {
                  AppIcon(.close, size: 14)
                    .foregroundStyle(palette.textMuted)
                }
                .buttonStyle(.plain)
              }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 10)
            .background(palette.surfaceRaised)
            .overlay(
              Rectangle()
                .stroke(palette.rule, lineWidth: 2)
            )

            Button {
              store.collapseAll()
            } label: {
              AppIcon(.filter, size: 18)
                .foregroundStyle(palette.textMuted)
                .frame(width: 40, height: 40)
                .overlay(
                  Rectangle()
                    .stroke(palette.rule, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
            .disabled(store.expandedCount == 0)
            .opacity(store.expandedCount == 0 ? 0.4 : 1.0)
          }
          .padding(.top, Space.s2)
        }
      }
      .padding([.horizontal, .bottom], Space.s4)
      .padding(.top, Space.s3)
      .background(palette.surface)
      .overlay(alignment: .bottom) {
        RuleLine(.section, axis: .horizontal)
      }

      // Body list
      ScrollView {
        LazyVStack(spacing: 0) {
          if let err = store.error {
            StateBlock(.error, label: "Tree", message: err) {
              Task { await store.refresh() }
            }
          } else if store.loading && store.rows.isEmpty {
            StateBlock(.loading, message: "Listing the working directory…")
          } else if store.rows.isEmpty && store.filterActive {
            StateBlock(.empty, label: "No matches", message: "Nothing in this project matches \"\(store.query)\".")
          } else if store.rows.isEmpty {
            StateBlock(.empty, label: "Empty", message: "This directory has no files in it.")
          } else {
            let rows = store.rows
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
              if showSeparator(index: index, rows: rows) {
                RuleLine(.row, axis: .horizontal)
                  .padding(.horizontal, Space.s5)
                  .padding(.vertical, 3)
              }

              FileTreeRowView(
                row: row,
                isSelected: store.selectedPath == row.path,
                isHovered: hoverPath == row.path
              ) {
                Task {
                  if row.type == .directory {
                    let wasExpanded = row.expanded
                    await store.toggle(row.path)
                    store.currentPath = wasExpanded ? store.parentOf(row.path) : row.path
                  } else {
                    store.selectedPath = row.path
                    onOpenFile?(row.path)
                  }
                }
              }
              .onHover { isHovered in
                if isHovered { hoverPath = row.path }
                else if hoverPath == row.path { hoverPath = nil }
              }
            }
          }

          if !store.isRepo {
            VStack(alignment: .leading, spacing: Space.s2) {
              SectionLabel("Git unavailable")
              Text("No .git directory was found at the working directory. The Git tab stays disabled until one exists.")
                .bodyText(13.5)
                .foregroundStyle(palette.textSecondary)

              Text("Run git init on the server")
                .mono(12)
                .foregroundStyle(palette.textMuted)
                .padding(.top, Space.s2)
            }
            .padding(Space.s4)
            .background(palette.surface)
            .overlay(
              Rectangle()
                .stroke(palette.rule, lineWidth: 2)
            )
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s6)
          }
        }
        .padding(.vertical, Space.s2)
      }
      .background(palette.surface)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task {
      if store.levels[store.directory] == nil {
        await store.refresh()
      }
    }
  }

  private func showSeparator(index: Int, rows: [TreeRow]) -> Bool {
    if store.filterActive || index == 0 { return false }
    let row = rows[index]
    let previous = rows[index - 1]
    return row.depth == 0 && row.type == .file && previous.type == .directory
  }
}

// MARK: - Row View

private struct FileTreeRowView: View {
  let row: TreeRow
  let isSelected: Bool
  let isHovered: Bool
  let onActivate: () -> Void

  @Environment(\.palette) private var palette

  private var indent: CGFloat {
    row.type == .directory
      ? 12 + CGFloat(row.depth) * 18
      : max(37, 19 + CGFloat(row.depth) * 18)
  }

  var body: some View {
    Button(action: onActivate) {
      HStack(spacing: 9) {
        if row.type == .directory {
          if row.loading {
            Spinner(size: 16)
              .foregroundStyle(palette.textMuted)
          } else {
            AppIcon(row.expanded ? .chevronDown : .chevronRight, size: 16)
              .foregroundStyle(palette.textMuted)
          }

          AppIcon(.folder, size: 16, filled: row.expanded)
            .foregroundStyle(row.expanded ? palette.accent : palette.textMuted)
        } else {
          TypeBadge(row.name, size: 20)
        }

        Text(row.name)
          .mono(14)
          .lineLimit(1)
          .foregroundStyle(palette.text)

        Spacer()

        if let status = row.status {
          Text(statusLetter(status))
            .mono(11)
            .foregroundStyle(palette.accent500)
        } else if row.changed > 0 {
          Text("\(row.changed)")
            .mono(11)
            .foregroundStyle(palette.textMuted)
        }
      }
      .padding(.leading, indent)
      .padding(.trailing, Space.s5)
      .padding(.vertical, 11)
      .background(
        isSelected || isHovered ? palette.surfaceRaised : palette.surface
      )
      .overlay(alignment: .leading) {
        if isSelected {
          Rectangle()
            .fill(palette.accent)
            .frame(width: 2)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func statusLetter(_ status: FileChangeStatus) -> String {
    switch status {
    case .added: return "A"
    case .modified: return "M"
    case .deleted: return "D"
    }
  }
}
