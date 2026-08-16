import OceanKit
import OceanUI
import SwiftUI

public struct CommitComposerView: View {
  @Bindable public var store: GitStore
  @State private var message: String = ""

  @Environment(\.palette) private var palette

  public init(store: GitStore) {
    self.store = store
  }

  private var changeCount: Int {
    store.status?.files.count ?? 0
  }

  private var hasChanges: Bool {
    changeCount > 0
  }

  private var commitLabel: String {
    if changeCount == 1 { return "Commit 1 change" }
    return "Commit all \(changeCount) changes"
  }

  private var disabledReason: String? {
    if !hasChanges { return "There is nothing to commit yet." }
    if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "Write a commit message first."
    }
    return nil
  }

  public var body: some View {
    VStack(spacing: 0) {
      // Feedback Block
      if store.committed != nil || store.commitError != nil || store.pushed != nil || store.pushError != nil {
        VStack(alignment: .leading, spacing: Space.s2) {
          HStack {
            SectionLabel(
              store.commitError != nil ? "Commit failed" :
                store.pushError != nil ? "Push failed" :
                store.pushed != nil ? "Pushed" : "Committed",
              color: (store.commitError != nil || store.pushError != nil) ? palette.accent500 : nil
            )

            Spacer()

            Button {
              store.dismissFeedback()
            } label: {
              AppIcon(.close, size: 14)
                .foregroundStyle(palette.textMuted)
                .padding(Space.s1)
            }
            .buttonStyle(.plain)
          }

          if let committed = store.committed, store.commitError == nil {
            HStack(spacing: Space.s2) {
              Text(committed.shortHash ?? "HEAD")
                .mono(12)
                .foregroundStyle(palette.text)
              Text(committed.subject)
                .bodyText(13)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            }
          }

          if let err = store.commitError {
            Text(err.message)
              .bodyText(13)
              .foregroundStyle(palette.textSecondary)
          }

          if let pushed = store.pushed {
            Text(pushed)
              .bodyText(13)
              .foregroundStyle(palette.textSecondary)
          }

          if let pErr = store.pushError {
            Text(pErr.message)
              .bodyText(13)
              .foregroundStyle(palette.textSecondary)
          }

          let detail = store.commitError?.detail ?? store.pushError?.detail
          if let detail, !detail.isEmpty {
            DisclosureGroup("git output") {
              ScrollView {
                Text(detail)
                  .mono(11)
                  .foregroundStyle(palette.textSecondary)
                  .padding(Space.s2)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .frame(maxHeight: 120)
              .background(palette.surfaceSunken)
            }
            .font(OceanFont.mono(11))
            .foregroundStyle(palette.accent500)
          }

          if store.committed != nil && store.commitError == nil && store.pushed == nil {
            AppButton(
              "Push",
              variant: .ghost,
              icon: .upload,
              loading: store.pushPending
            ) {
              Task { await store.push() }
            }
            .padding(.top, Space.s1)
          }
        }
        .padding(.horizontal, Space.s5)
        .padding(.vertical, Space.s3)
        .background(palette.surfaceRaised)
        .overlay(alignment: .bottom) {
          RuleLine(.row, axis: .horizontal)
        }
      }

      // Scope header
      HStack {
        SectionLabel(hasChanges ? commitLabel : "Nothing to commit")
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.top, Space.s2)
      .padding(.bottom, 6)

      // Bar with Message Input + Commit Button
      HStack(spacing: 0) {
        TextField("Commit message", text: $message)
          .textFieldStyle(.plain)
          .font(OceanFont.mono(13))
          .foregroundStyle(palette.text)
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .background(palette.surface)
          .disabled(!hasChanges || store.commitPending)

        RuleLine(.section, axis: .vertical)

        Button {
          let msg = message
          Task {
            await store.stageAllAndCommit(message: msg)
            if store.commitError == nil {
              message = ""
            }
          }
        } label: {
          HStack(spacing: Space.s2) {
            if store.commitPending {
              Spinner(size: 14)
            } else {
              AppIcon(.check, size: 14)
            }
            Text("Commit")
              .font(OceanFont.heading(13, weight: .bold))
          }
          .foregroundStyle(palette.onAccent)
          .padding(.horizontal, Space.s4)
          .frame(minWidth: 80, maxHeight: .infinity)
          .background(palette.accent)
          .clipShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabledReason != nil || store.commitPending)
        .opacity(disabledReason != nil ? 0.45 : 1.0)
      }
      .frame(height: 44)
    }
    .background(palette.surface)
    .overlay(alignment: .top) {
      RuleLine(.section, axis: .horizontal)
    }
  }
}
