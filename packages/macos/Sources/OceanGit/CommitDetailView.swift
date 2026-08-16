import OceanKit
import OceanUI
import SwiftUI

public struct CommitDetailView: View {
  @Bindable public var store: GitStore
  public let hash: String
  public var subject: String?
  public var onBack: (() -> Void)?

  @Environment(\.palette) private var palette
  @State private var detail: GitCommitDetail? = nil
  @State private var loading: Bool = true
  @State private var error: String? = nil

  @State private var selectedFile: GitCommitFile? = nil
  @State private var diff: FileDiff? = nil
  @State private var diffLoading: Bool = false
  @State private var diffError: String? = nil

  public init(
    store: GitStore,
    hash: String,
    subject: String? = nil,
    onBack: (() -> Void)? = nil
  ) {
    self.store = store
    self.hash = hash
    self.subject = subject
    self.onBack = onBack
  }

  private var totals: (added: Int, removed: Int) {
    var added = 0
    var removed = 0
    for file in detail?.files ?? [] {
      added += file.added
      removed += file.removed
    }
    return (added, removed)
  }

  public var body: some View {
    VStack(spacing: 0) {
      // Commit Header
      HStack(spacing: 10) {
        if selectedFile != nil {
          Button {
            selectedFile = nil
            diff = nil
          } label: {
            AppIcon(.arrowLeft, size: 16)
              .foregroundStyle(palette.textMuted)
              .frame(width: 28, height: 28)
          }
          .buttonStyle(.plain)
        } else if let onBack {
          Button(action: onBack) {
            AppIcon(.arrowLeft, size: 20)
              .foregroundStyle(palette.text)
          }
          .buttonStyle(.plain)
        }

        VStack(alignment: .leading, spacing: 3) {
          Text(detail?.commit.subject ?? subject ?? "Commit")
            .heading(15)
            .lineLimit(1)
            .foregroundStyle(palette.text)

          HStack(spacing: Space.s1) {
            Text(detail?.commit.shortHash ?? String(hash.prefix(7)))
              .mono(11)
              .foregroundStyle(palette.accent400)

            if let author = detail?.commit.author {
              Text("· \(author)")
                .mono(11)
                .foregroundStyle(palette.textMuted)
            }

            if let date = detail?.commit.date {
              Text("· \(Formatters.relativeTime(date))")
                .mono(11)
                .foregroundStyle(palette.textMuted)
            }
          }
        }

        Spacer()

        if detail != nil && selectedFile == nil {
          HStack(spacing: Space.s2) {
            Text("+\(totals.added)")
              .mono(11)
              .foregroundStyle(palette.accent400)

            Text("−\(totals.removed)")
              .mono(11)
              .foregroundStyle(palette.accent500)
          }
        }
      }
      .padding(Space.s5)
      .background(palette.surface)
      .overlay(alignment: .bottom) {
        RuleLine(.row, axis: .horizontal)
      }

      // Body Content
      ZStack {
        if loading {
          StateBlock(.loading, label: "Commit", message: "Reading this commit…")
        } else if let err = error {
          StateBlock(.error, label: "Commit unavailable", message: err) {
            Task { await loadCommitDetail() }
          }
        } else if let file = selectedFile {
          // File diff view inside commit
          VStack(spacing: 0) {
            HStack(spacing: 9) {
              TypeBadge(Formatters.basename(file.path), size: 18)
              Text(file.path)
                .mono(11)
                .lineLimit(1)
                .foregroundStyle(palette.textSecondary)

              Spacer()

              Text(GitDiffParser.formatChangeCounts(file.added, file.removed))
                .mono(10)
                .foregroundStyle(palette.textMuted)
            }
            .padding(.horizontal, Space.s5)
            .padding(.vertical, 11)
            .background(palette.surfaceRaised)
            .overlay(alignment: .bottom) {
              RuleLine(.row, axis: .horizontal)
            }

            ZStack {
              if diffLoading {
                StateBlock(.loading, message: "Reading the change…")
              } else if let dErr = diffError {
                StateBlock(.error, label: "Diff unavailable", message: dErr) {
                  Task { await openFileDiff(file) }
                }
              } else if let d = diff, d.hunks.isEmpty {
                StateBlock(.empty, label: "No textual diff", message: "This file has no line changes to show — it may be binary or a pure rename.")
              } else if let d = diff {
                DiffBody(diff: d)
              }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        } else if let detail = detail {
          // List of touched files
          ScrollView {
            VStack(spacing: 0) {
              HStack {
                SectionLabel("Files")
                Spacer()
                Text("\(detail.files.count)")
                  .mono(10)
                  .foregroundStyle(palette.textDim)
              }
              .padding(.horizontal, Space.s5)
              .padding(.top, Space.s3)
              .padding(.bottom, Space.s2)

              if detail.files.isEmpty {
                StateBlock(.empty, label: "No files", message: "This commit does not touch any file — it may be a merge.")
              } else {
                ForEach(detail.files) { file in
                  Button {
                    Task { await openFileDiff(file) }
                  } label: {
                    HStack(spacing: 10) {
                      Text(letterFor(file))
                        .mono(11)
                        .foregroundStyle(letterColor(file.status))
                        .frame(width: 11)

                      TypeBadge(Formatters.basename(file.path), size: 18)

                      VStack(alignment: .leading, spacing: 2) {
                        Text(Formatters.basename(file.path))
                          .mono(13)
                          .foregroundStyle(palette.text)
                          .lineLimit(1)

                        Text(relativeTo(store.directory, file.path))
                          .mono(10)
                          .foregroundStyle(palette.textMuted)
                          .lineLimit(1)
                      }

                      Spacer()

                      Text(GitDiffParser.formatChangeCounts(file.added, file.removed))
                        .mono(10)
                        .foregroundStyle(palette.textMuted)

                      AppIcon(.chevronRight, size: 14)
                        .foregroundStyle(palette.textDim)
                    }
                    .padding(.horizontal, Space.s5)
                    .padding(.vertical, 11)
                    .background(palette.surface)
                  }
                  .buttonStyle(.plain)
                  .overlay(alignment: .bottom) {
                    RuleLine(.row, axis: .horizontal)
                  }
                }
              }
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .task {
      await loadCommitDetail()
    }
  }

  private func loadCommitDetail() async {
    loading = true
    error = nil
    selectedFile = nil
    diff = nil

    detail = await store.loadCommit(hash)
    if detail == nil {
      error = "This commit could not be read from the repository."
    }
    loading = false
  }

  private func openFileDiff(_ file: GitCommitFile) async {
    selectedFile = file
    diff = nil
    diffError = nil
    diffLoading = true
    diff = await store.loadCommitDiff(hash: hash, path: file.path)
    diffLoading = false
  }

  private func letterFor(_ file: GitCommitFile) -> String {
    switch file.status {
    case .added: return "A"
    case .deleted: return "D"
    case .modified: return "M"
    }
  }

  private func letterColor(_ status: FileChangeStatus) -> Color {
    switch status {
    case .added, .modified: return palette.accent400
    case .deleted: return palette.accent500
    }
  }

  private func relativeTo(_ root: String, _ path: String) -> String {
    let prefix = root.hasSuffix("/") ? root : root + "/"
    if path.hasPrefix(prefix) { return String(path.dropFirst(prefix.count)) }
    return path
  }
}
