import OceanKit
import OceanUI
import SwiftUI

public struct CommitLogView: View {
  @Bindable public var store: GitStore
  public var onSelectCommit: ((GitCommit) -> Void)?

  @Environment(\.palette) private var palette

  public init(store: GitStore, onSelectCommit: ((GitCommit) -> Void)? = nil) {
    self.store = store
    self.onSelectCommit = onSelectCommit
  }

  public var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        SectionLabel("RECENT COMMITS")

        if !store.commits.isEmpty {
          Text("· \(store.commits.count)")
            .mono(11)
            .foregroundStyle(palette.textDim)
        }

        Spacer()

        IconButton(.refresh, label: "Refresh commits", size: 15) {
          Task { await store.refreshCommits() }
        }
        .disabled(store.commitsLoading)
      }
      .padding(.horizontal, Space.s5)
      .padding(.vertical, Space.s3)
      .background(palette.surfaceRaised)
      .overlay(alignment: .bottom) {
        RuleLine(.row, axis: .horizontal)
      }

      // Content
      ScrollView {
        VStack(spacing: 0) {
          if store.commitsLoading && store.commits.isEmpty {
            StateBlock(.loading, label: "Commit history", message: "Reading recent commits.")
          } else if let err = store.commitsError, store.commits.isEmpty {
            StateBlock(.error, label: "History unavailable", message: err) {
              Task { await store.refreshCommits() }
            }
          } else if store.commits.isEmpty {
            StateBlock(.empty, label: "No commits yet", message: "This repository does not have any commits to show.")
          } else {
            ForEach(store.commits) { commit in
              Button {
                onSelectCommit?(commit)
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  HStack(alignment: .center, spacing: Space.s2) {
                    Text(commit.subject)
                      .bodyText(13.5)
                      .foregroundStyle(palette.text)
                      .lineLimit(1)
                      .truncationMode(.tail)

                    Spacer()

                    Text(commit.shortHash)
                      .mono(11)
                      .foregroundStyle(palette.textMuted)
                  }

                  HStack(spacing: Space.s2) {
                    Text(commit.author)
                      .mono(11)
                      .foregroundStyle(palette.textMuted)
                      .lineLimit(1)

                    Text("·")
                      .mono(11)
                      .foregroundStyle(palette.textDim)

                    Text(Formatters.relativeTime(commit.date))
                      .mono(11)
                      .foregroundStyle(palette.textMuted)
                      .lineLimit(1)

                    if !commit.refs.isEmpty {
                      Spacer()
                      ForEach(commit.refs.prefix(2), id: \.self) { ref in
                        Chip(ref, tone: .neutral, uppercased: false)
                      }
                    }
                  }
                }
                .padding(.horizontal, Space.s5)
                .padding(.vertical, 10)
                .frame(height: 54)
                .background(palette.surface)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .overlay(alignment: .bottom) {
                RuleLine(.row, axis: .horizontal)
              }
            }
          }
        }
      }
      .background(palette.surface)
    }
    .task {
      if store.commits.isEmpty {
        await store.refreshCommits()
      }
    }
  }
}
