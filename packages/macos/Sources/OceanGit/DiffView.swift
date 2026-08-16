import OceanKit
import OceanUI
import SwiftUI

public struct DiffView: View {
  @Bindable public var store: GitStore
  public let path: String
  public var onBack: (() -> Void)?
  public var onSelectFile: ((String) -> Void)?

  @Environment(\.palette) private var palette

  public init(
    store: GitStore,
    path: String,
    onBack: (() -> Void)? = nil,
    onSelectFile: ((String) -> Void)? = nil
  ) {
    self.store = store
    self.path = path
    self.onBack = onBack
    self.onSelectFile = onSelectFile
  }

  private var name: String {
    Formatters.basename(path)
  }

  private var meta: String {
    guard let diff = store.diff else { return "" }
    let counts = GitDiffParser.formatChangeCounts(diff.added, diff.removed)
    let hunks = GitDiffParser.formatHunkCount(diff.hunks.count)
    return [counts, hunks].filter { !$0.isEmpty }.joined(separator: " · ")
  }

  private var neighbours: [FileStatus] {
    store.status?.files.filter { $0.status != .added } ?? []
  }

  private var position: Int? {
    neighbours.firstIndex { $0.path == path }
  }

  private var previousFile: FileStatus? {
    guard let pos = position, pos > 0 else { return nil }
    return neighbours[pos - 1]
  }

  private var nextFile: FileStatus? {
    guard let pos = position, pos < neighbours.count - 1 else { return nil }
    return neighbours[pos + 1]
  }

  public var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack(spacing: Space.s3) {
        if let onBack {
          Button(action: onBack) {
            AppIcon(.arrowLeft, size: 20)
              .foregroundStyle(palette.text)
          }
          .buttonStyle(.plain)
        }

        TypeBadge(name, size: 22)

        VStack(alignment: .leading, spacing: 2) {
          Text(name)
            .mono(15)
            .lineLimit(1)
            .foregroundStyle(palette.text)

          Text(meta.isEmpty ? relativeTo(store.directory, path) : meta)
            .mono(11)
            .lineLimit(1)
            .foregroundStyle(palette.textMuted)
        }

        Spacer()
      }
      .padding([.horizontal, .bottom], Space.s5)
      .padding(.top, Space.s4)
      .background(palette.surface)
      .overlay(alignment: .bottom) {
        RuleLine(.section, axis: .horizontal)
      }

      // Diff scroll body
      ZStack {
        if store.diffLoading && store.diff == nil {
          StateBlock(.loading, label: "Diff", message: "Reading the change from the server.")
        } else if let err = store.diffError {
          StateBlock(.error, label: "Diff unavailable", message: err) {
            Task { await store.refreshDiff(path) }
          }
        } else if let diff = store.diff, diff.hunks.isEmpty {
          StateBlock(.empty, label: "No diff", message: "No changes in this file — it matches the index and the last commit.")
        } else if let diff = store.diff {
          DiffBody(diff: diff)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      // Bottom Pager
      HStack(spacing: 0) {
        Button {
          if let prev = previousFile {
            onSelectFile?(prev.path)
          }
        } label: {
          Text(previousFile != nil ? "← \(Formatters.basename(previousFile!.path))" : "← no earlier file")
            .mono(12)
            .foregroundStyle(previousFile != nil ? palette.textMuted : palette.textFaint)
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(previousFile == nil)

        RuleLine(.section, axis: .vertical)

        Button {
          if let next = nextFile {
            onSelectFile?(next.path)
          }
        } label: {
          Text(nextFile != nil ? "\(Formatters.basename(nextFile!.path)) →" : "no later file →")
            .mono(12)
            .foregroundStyle(nextFile != nil ? palette.textMuted : palette.textFaint)
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .disabled(nextFile == nil)
      }
      .background(palette.surface)
      .overlay(alignment: .top) {
        RuleLine(.section, axis: .horizontal)
      }
    }
    .task(id: path) {
      await store.refreshDiff(path)
    }
  }

  private func relativeTo(_ root: String, _ p: String) -> String {
    let prefix = root.hasSuffix("/") ? root : root + "/"
    if p.hasPrefix(prefix) { return String(p.dropFirst(prefix.count)) }
    return p
  }
}
