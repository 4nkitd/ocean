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
  @State private var newWorktreePath: String = ""
  @State private var newWorktreeBranch: String = ""

  public enum ViewMode: String, Sendable, CaseIterable {
    case changes = "Changes"
    case commits = "Commits"
    case worktrees = "Worktrees"
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
      SectionHeader(isRepo ? "WORKING TREE" : "GIT") {
        if let onOpenProjects {
          IconButton(.grid, label: "All projects", size: 16) {
            onOpenProjects()
          }
        }
      }

      // Compact Branch Bar
      if isRepo {
        HStack(spacing: Space.s2) {
          AppIcon(.gitBranch, size: 13)
            .foregroundStyle(palette.textMuted)

          Text(branchName)
            .mono(12, weight: .medium)
            .lineLimit(1)
            .foregroundStyle(palette.text)

          Spacer()

          if let status = store.status {
            HStack(spacing: Space.s3) {
              Text("↑\(status.ahead)")
                .mono(11)
                .foregroundStyle(palette.textMuted)

              Text("↓\(status.behind)")
                .mono(11)
                .foregroundStyle(palette.textMuted)

              if let upstream = status.upstream {
                Text(upstream)
                  .mono(11)
                  .lineLimit(1)
                  .foregroundStyle(palette.textMuted)
              } else {
                Text("no upstream")
                  .mono(11)
                  .foregroundStyle(palette.textMuted)
              }
            }
          }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .background(palette.surfaceSunken)
        .overlay(alignment: .bottom) {
          RuleLine(.row)
        }
      }

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
                .fill(viewMode == .changes ? palette.accent : Color.clear)
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
                .fill(viewMode == .commits ? palette.accent : Color.clear)
                .frame(height: 2)
            }
          }
          .buttonStyle(.plain)

          RuleLine(.row, axis: .vertical)

          let worktreesAvailable = store.worktrees != nil || store.worktreesLoading || store.worktreesError != nil
          Button {
            viewMode = .worktrees
            Task { await store.loadWorktrees() }
          } label: {
            HStack(spacing: 7) {
              AppIcon(.gitBranch, size: 14)
                .foregroundStyle(viewMode == .worktrees ? palette.text : palette.textMuted)

              Text("WORKTREES")
                .font(OceanFont.mono(11, weight: viewMode == .worktrees ? .bold : .regular))
                .tracking(0.08 * 11)
                .foregroundStyle(viewMode == .worktrees ? palette.text : palette.textMuted)
            }
            .padding(.horizontal, Space.s4)
            .frame(minHeight: 36)
            .background(palette.surface)
            .overlay(alignment: .bottom) {
              Rectangle()
                .fill(viewMode == .worktrees ? palette.accent : Color.clear)
                .frame(height: 2)
            }
          }
          .buttonStyle(.plain)
          .opacity(worktreesAvailable ? 1.0 : 0.45)
          .help(worktreesAvailable ? "Git worktrees" : "Worktrees not available on this server")

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
        } else if viewMode == .commits {
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
        } else {
          // Worktrees View Mode
          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
              if store.worktreesLoading {
                StateBlock(.loading, label: "Worktrees", message: "Loading worktrees.")
              } else if let err = store.worktreesError {
                StateBlock(.error, label: "Worktrees unavailable", message: err) {
                  Task { await store.loadWorktrees() }
                }
              } else if let worktrees = store.worktrees {
                if worktrees.isEmpty {
                  StateBlock(.empty, label: "No worktrees", message: "No git worktrees found.")
                } else {
                  ForEach(worktrees) { wt in
                    VStack(alignment: .leading, spacing: 2) {
                      Text(wt.directory)
                        .font(OceanFont.mono(12.5, weight: .bold))
                        .foregroundStyle(palette.text)

                      if let strategy = wt.strategy, !strategy.isEmpty {
                        Text(strategy)
                          .mono(11)
                          .foregroundStyle(palette.textMuted)
                          .lineLimit(1)
                      }
                    }
                    .padding(.horizontal, Space.s5)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.surface)
                    .overlay(alignment: .bottom) {
                      RuleLine(.row, axis: .horizontal)
                    }
                  }
                }

                // Inline create row
                VStack(alignment: .leading, spacing: Space.s3) {
                  HStack(spacing: Space.s3) {
                    AppTextField("Worktree path", text: $newWorktreePath)
                      .frame(maxWidth: .infinity)
                    AppTextField("Branch (optional)", text: $newWorktreeBranch)
                      .frame(maxWidth: 180)
                    AppButton("Create", variant: .primary, loading: store.worktreeCreating) {
                      let path = newWorktreePath.trimmingCharacters(in: .whitespaces)
                      let branch = newWorktreeBranch.trimmingCharacters(in: .whitespaces)
                      guard !path.isEmpty else { return }
                      Task {
                        await store.createWorktree(path: path, branch: branch.isEmpty ? nil : branch)
                        if store.worktreeCreateError == nil {
                          newWorktreePath = ""
                          newWorktreeBranch = ""
                        }
                      }
                    }
                    .disabled(newWorktreePath.trimmingCharacters(in: .whitespaces).isEmpty || store.worktreeCreating)
                  }

                  if let createError = store.worktreeCreateError {
                    Text(createError)
                      .mono(11)
                      .foregroundStyle(palette.accent)
                  }
                }
                .padding(Space.s5)
              } else {
                StateBlock(.empty, label: "Not available", message: "This server does not expose worktrees.")
              }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
          }
          .background(palette.surface)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
          .foregroundStyle(file.status == .added ? palette.ok : palette.textMuted)
      }
      .padding(.horizontal, Space.s5)
      .padding(.vertical, 10)
      .background(palette.surface)
      .overlay(alignment: .bottom) {
        RuleLine(.row, axis: .horizontal)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
