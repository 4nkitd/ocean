import OceanKit
import OceanUI
import SwiftUI

public struct FileViewerView: View {
  @Bindable public var store: FilesStore
  public let path: String
  public var onBack: (() -> Void)?
  public var onRevealInTree: ((String) -> Void)?

  @Environment(\.palette) private var palette
  @State private var noticeMessage: String? = nil
  @State private var noticeTask: Task<Void, Never>? = nil

  public init(
    store: FilesStore,
    path: String,
    onBack: (() -> Void)? = nil,
    onRevealInTree: ((String) -> Void)? = nil
  ) {
    self.store = store
    self.path = path
    self.onBack = onBack
    self.onRevealInTree = onRevealInTree
  }

  private var filename: String {
    Formatters.basename(path)
  }

  private var parentPath: String {
    store.relative(store.parentOf(path))
  }

  private var language: String {
    SyntaxHighlighter.languageFor(filename)
  }

  private var isBinary: Bool {
    SyntaxHighlighter.isBinary(filename)
  }

  private var byteSize: Int {
    store.selectedContent.utf8.count
  }

  private var lineEnding: String {
    if store.selectedContent.contains("\r\n") { return "CRLF" }
    if store.selectedContent.contains("\r") { return "CR" }
    return "LF"
  }

  private var statusLabel: String {
    switch store.gitStatus {
    case .modified: return "modified"
    case .added: return "added"
    case .deleted: return "deleted"
    case .none: return "unchanged"
    }
  }

  public var body: some View {
    VStack(spacing: 0) {
      // Header
      VStack(alignment: .leading, spacing: Space.s3) {
        HStack(spacing: Space.s3) {
          if let onBack {
            Button(action: onBack) {
              AppIcon(.arrowLeft, size: 20)
                .foregroundStyle(palette.text)
                .frame(width: 24, height: 32)
            }
            .buttonStyle(.plain)
          }

          TypeBadge(filename, size: 22)

          VStack(alignment: .leading, spacing: 2) {
            Text(filename)
              .mono(15)
              .lineLimit(1)
              .foregroundStyle(palette.text)

            if !parentPath.isEmpty {
              Text(parentPath)
                .mono(11)
                .lineLimit(1)
                .foregroundStyle(palette.textMuted)
            }
          }

          Spacer()

          // Menu actions
          Menu {
            Button("Copy path") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(path, forType: .string)
              flashNotice("Path copied")
            }
            if !isBinary && !store.selectedContent.isEmpty {
              Button("Copy contents") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(store.selectedContent, forType: .string)
                flashNotice("Contents copied")
              }
            }
            if let onRevealInTree {
              Button("Reveal in tree") {
                onRevealInTree(path)
              }
            }
          } label: {
            AppIcon(.more, size: 18)
              .foregroundStyle(palette.textMuted)
              .frame(width: 32, height: 32)
          }
          .menuStyle(.borderlessButton)
          .frame(width: 32, height: 32)
        }

        // Chips
        FlowLayout(spacing: Space.s2, lineSpacing: Space.s2) {
          Chip(language)
          if !store.selectedLoading && !isBinary {
            Chip(formatBytes(byteSize))
          }
          Chip("read only", tone: .accent)
        }
      }
      .padding([.horizontal, .bottom], Space.s5)
      .padding(.top, Space.s4)
      .background(palette.surface)
      .overlay(alignment: .bottom) {
        RuleLine(.section, axis: .horizontal)
      }

      // Main content body
      ZStack {
        if store.selectedLoading {
          StateBlock(.loading, message: "Reading the file…")
        } else if let err = store.selectedError {
          StateBlock(.error, label: "Could not read", message: err) {
            Task { await store.selectFile(path) }
          }
        } else if isBinary {
          StateBlock(
            .empty,
            label: "Binary file",
            message: "\(filename) is not text, so there is nothing to show here."
          )
        } else if store.selectedContent.isEmpty {
          StateBlock(.empty, label: "Empty file", message: "This file has no contents.")
        } else {
          CodeViewer(
            content: store.selectedContent,
            language: language,
            changedLines: store.changedLines,
            selectedLine: $store.selectedLine
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      // Footer
      HStack(spacing: Space.s3) {
        Text("Ln \(store.selectedLine ?? 1) · UTF-8 · \(lineEnding)")
          .mono(11)
          .foregroundStyle(palette.textMuted)

        Spacer()

        if let noticeMessage {
          Text(noticeMessage)
            .mono(11)
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
        }

        Spacer()

        Text(statusLabel)
          .mono(11)
          .foregroundStyle(
            store.gitStatus != nil ? palette.accent500 : palette.textMuted
          )
      }
      .padding(Space.s3)
      .padding(.horizontal, Space.s2)
      .background(palette.surface)
      .overlay(alignment: .top) {
        RuleLine(.section, axis: .horizontal)
      }
    }
    .task {
      await store.selectFile(path)
    }
  }

  private func flashNotice(_ msg: String) {
    noticeTask?.cancel()
    noticeMessage = msg
    noticeTask = Task {
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      if !Task.isCancelled {
        noticeMessage = nil
      }
    }
  }

  private func formatBytes(_ bytes: Int) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    let kb = Double(bytes) / 1024.0
    if kb < 1024 { return String(format: "%.1f KB", kb) }
    let mb = kb / 1024.0
    return String(format: "%.1f MB", mb)
  }
}
