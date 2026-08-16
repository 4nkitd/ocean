import OceanKit
import OceanUI
import SwiftUI

public struct GitView: View {
  @Bindable public var store: GitStore
  public var onSelectFile: ((FileStatus) -> Void)?
  public var onOpenProjects: (() -> Void)?

  @Environment(\.palette) private var palette
  @State private var viewMode: ViewMode = .changes
  @State private var selectedCommitHash: String? = nil

  public enum ViewMode: String, Sendable, CaseIterable {
    case changes = "Changes"
    case commits = "Commits"
  }

  public init(
    store: GitStore,
    onSelectFile: ((FileStatus) -> Void)? = nil,
    onOpenProjects: (() -> Void)? = nil
  ) {
    self.store = store
    self.onSelectFile = onSelectFile
    self.onOpenProjects = onOpenProjects
  }

  private var isRepo: Bool {
    store.status?.isRepo ?? true
  }

  private var branchName: String {
    store.status?.branch ?? (isRepo ? "working tree" : "no repository")
  }

  private var hasChanges: Bool {
    (store.status?.files.count ?? 0) > 0
  }

  private var changeCount: Int {
    store.status?.files.count ?? 0
  }

  public var body: some View {
    VStack(spacing: 0) {
      // Header
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: Space.s3) {
          HStack(spacing: 9) {
            AppIcon(.gitBranch, size: 15)
              .foregroundStyle(palette.textMuted)

            Text(branchName)
              .mono(14)
              .lineLimit(1)
              .foregroundStyle(palette.text)
          }

          Spacer()

          if let onOpenProjects {
            Button(action: onOpenProjects) {
              AppIcon(.grid, size: 18)
                .foregroundStyle(palette.textMuted)
                .padding(Space.s1)
            }
            .buttonStyle(.plain)
          }
        }

        if isRepo, let status = store.status {
          HStack(spacing: Space.s4) {
            Text("↑\(status.ahead)")
              .mono(12)
              .foregroundStyle(palette.textMuted)

            Text("↓\(status.behind)")
              .mono(12)
              .foregroundStyle(palette.textMuted)

            if let upstream = status.upstream {
              Text(upstream)
                .mono(12)
                .lineLimit(1)
                .foregroundStyle(palette.textMuted)
            } else {
              Text("no upstream")
                .mono(12)
                .foregroundStyle(palette.textMuted)
            }
          }
        }
      }
      .padding(.horizontal, Space.s4)
      .padding(.vertical, Space.s3)
      .background(palette.surface)
      .overlay(alignment: .bottom) {
        RuleLine(.section)
      }
      .fixedSize(horizontal: false, vertical: true)

      // Mode Switcher
      if isRepo {
        HStack(spacing: 0) {
          Button {
            viewMode = .changes
            selectedCommitHash = nil
          } label: {
            HStack(spacing: 7) {
              Text("CHANGES")
                .font(OceanFont.mono(11, weight: viewMode == .changes ? .bold : .regular))
                .tracking(0.08 * 11)
                .foregroundStyle(viewMode == .changes ? palette.text : palette.textMuted)

              if let status = store.status {
                Text("\(status.files.count)")
                  .mono(11)
                  .foregroundStyle(palette.textMuted)
              }
            }
            .padding(.horizontal, Space.s4)
            .frame(minHeight: 36)
            .background(palette.surface)
            .overlay(alignment: .bottom) {
              Rectangle()
                .fill(viewMode == .changes ? palette.text : Color.clear)
                .frame(height: 2)
            }
          }
          .buttonStyle(.plain)

          RuleLine(.row, axis: .vertical)

          Button {
            viewMode = .commits
            Task { await store.refreshCommits() }
          } label: {
            HStack(spacing: 7) {
              AppIcon(.history, size: 14)
                .foregroundStyle(viewMode == .commits ? palette.text : palette.textMuted)

              Text("COMMITS")
                .font(OceanFont.mono(11, weight: viewMode == .commits ? .bold : .regular))
                .tracking(0.08 * 11)
                .foregroundStyle(viewMode == .commits ? palette.text : palette.textMuted)
            }
            .padding(.horizontal, Space.s4)
            .frame(minHeight: 36)
            .background(palette.surface)
            .overlay(alignment: .bottom) {
              Rectangle()
                .fill(viewMode == .commits ? palette.text : Color.clear)
                .frame(height: 2)
            }
          }
          .buttonStyle(.plain)

          Spacer()
        }
        .background(palette.surface)
        .overlay(alignment: .bottom) {
          RuleLine(.row)
        }
        .fixedSize(horizontal: false, vertical: true)
      }

      // Content Area
      Group {
        if !isRepo {
          // Git unavailable state block
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
          .padding(18)
          .overlay(
            Rectangle()
              .stroke(palette.rule, lineWidth: 2)
          )
          .padding(Space.s5)
          .frame(maxWidth: .infinity, alignment: .topLeading)
        } else if viewMode == .changes {
          // Changes List
          VStack(spacing: 0) {
            ScrollView {
              VStack(alignment: .leading, spacing: 0) {
                if let err = store.statusError {
                  StateBlock(.error, label: "Status unavailable", message: err) {
                    Task { await store.refreshStatus() }
                  }
                } else if store.status == nil {
                  StateBlock(.loading, label: "Status", message: "Reading the working tree.")
                } else if let status = store.status {
                  if !hasChanges {
                    StateBlock(.empty, label: "Clean", message: "The working tree is clean. Nothing to commit.")
                  } else {
                    HStack {
                      SectionLabel("Changes · \(status.files.count)")
                      Spacer()
                    }
                    .padding(.horizontal, Space.s5)
                    .padding(.vertical, Space.s3)
                    .background(palette.surfaceRaised)
                    .overlay(alignment: .bottom) {
                      RuleLine(.section, axis: .horizontal)
                    }

                    ForEach(status.files) { file in
                      GitFileRowView(file: file, root: store.directory) {
                        onSelectFile?(file)
                      }
                    }
                  }
                }
              }
              .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(palette.surface)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Commit composer bar at bottom
            CommitComposerView(store: store)
          }
        } else {
          // Commits View Mode
          if let commitHash = selectedCommitHash {
            CommitDetailView(store: store, hash: commitHash) {
              selectedCommitHash = nil
            }
          } else {
            CommitLogView(store: store) { commit in
              selectedCommitHash = commit.hash
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .task {
      await store.refreshStatus()
    }
  }
}

// MARK: - Git File Row

private struct GitFileRowView: View {
  let file: FileStatus
  let root: String
  let onSelect: () -> Void

  @Environment(\.palette) private var palette

  private var relative: String {
    let prefix = root.hasSuffix("/") ? root : root + "/"
    if file.path.hasPrefix(prefix) {
      return String(file.path.dropFirst(prefix.count))
    }
    return file.path
  }

  public var body: some View {
    Button(action: onSelect) {
      HStack(spacing: Space.s3) {
        StatusDot(file.status == .added ? .ok : .accent, size: 7)

        Text(relative)
          .mono(12.5)
          .foregroundStyle(palette.text)
          .lineLimit(1)

        Spacer()

        Text(file.status.rawValue.prefix(1).uppercased())
          .mono(11, weight: .bold)
          .foregroundStyle(file.status == .added ? palette.ok : palette.accent500)
      }
      .padding(.horizontal, Space.s5)
      .padding(.vertical, 10)
      .background(palette.surface)
      .overlay(alignment: .bottom) {
        RuleLine(.row, axis: .horizontal)
      }
    }
    .buttonStyle(.plain)
  }
}
