import OceanKit
import OceanUI
import SwiftUI

public struct ActiveView: View {
  @State private var store: ActiveStore
  private let onSelectSession: (String, String) -> Void

  @Environment(\.palette) private var palette

  public init(
    store: ActiveStore? = nil,
    onSelectSession: @escaping (String, String) -> Void
  ) {
    _store = State(initialValue: store ?? ActiveStore())
    self.onSelectSession = onSelectSession
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      headerView

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if store.loading && store.rows.isEmpty {
            StateBlock(.loading, message: "Looking for running sessions…")
          } else if let err = store.error {
            StateBlock(.error, message: err) {
              Task { await store.refresh() }
            }
          } else if store.rows.isEmpty {
            StateBlock(
              .empty,
              message: "Nothing is running. Start a session and it will show up here."
            )
          } else {
            VStack(spacing: 0) {
              ForEach(store.rows) { row in
                sessionRow(row)
              }
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(palette.bg)
    .task {
      store.startTimer()
      await store.refresh()
    }
    .onDisappear {
      store.stopTimer()
    }
  }

  private var headerView: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("Active")
          .font(OceanFont.body(24, weight: .bold))
          .foregroundStyle(palette.text)

        Text(subText)
          .mono(11)
          .foregroundStyle(palette.textMuted)
          .lineLimit(1)
      }

      Spacer()

      IconButton(.refresh, label: "Refresh", size: 18) {
        Task { await store.refresh() }
      }
    }
    .padding(Space.s5)
    .background(palette.surface)
    .overlay(alignment: .bottom) { RuleLine(.section) }
  }

  private var subText: String {
    let server = ConnectionStore.shared.serverLabel
    var parts = [server, "\(store.runningCount) running"]
    if store.blockedCount > 0 {
      parts.append("\(store.blockedCount) waiting on you")
    }
    return parts.joined(separator: " · ")
  }

  private func sessionRow(_ row: ActiveRow) -> some View {
    Button {
      if !row.directory.isEmpty {
        onSelectSession(row.directory, row.session.id)
      }
    } label: {
      HStack(spacing: Space.s3) {
        if row.request != nil {
          AppIcon(.alert, size: 14)
            .foregroundStyle(palette.accent)
        } else {
          Spinner(size: 14)
            .foregroundStyle(palette.accent)
        }

        VStack(alignment: .leading, spacing: 3) {
          Text(row.session.title ?? "Untitled session")
            .font(OceanFont.body(14, weight: .semibold))
            .foregroundStyle(palette.text)
            .lineLimit(1)

          HStack(spacing: Space.s2) {
            Text(row.project)
              .mono(10.5)
              .foregroundStyle(palette.textMuted)

            if let req = row.request {
              Text("needs you · \(req.action)")
                .mono(10.5)
                .foregroundStyle(palette.accent500)
            } else if row.started != nil {
              Text("working \(store.elapsed(for: row))")
                .mono(10.5)
                .foregroundStyle(palette.textDim)
            } else {
              Text(Formatters.relativeTime(row.session.timeUpdated))
                .mono(10.5)
                .foregroundStyle(palette.textDim)
            }
          }
        }

        Spacer()

        AppIcon(.chevronRight, size: 15)
          .foregroundStyle(palette.textDim)
      }
      .padding(.horizontal, Space.s5)
      .padding(.vertical, 15)
      .background(row.request != nil ? palette.surfaceRaised : Color.clear)
      .overlay(alignment: .leading) {
        if row.request != nil {
          RuleLine(.section, axis: .vertical, color: palette.accent)
        }
      }
      .overlay(alignment: .bottom) { RuleLine(.row) }
    }
    .buttonStyle(.plain)
  }
}
