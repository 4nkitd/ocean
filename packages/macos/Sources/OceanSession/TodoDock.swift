import Foundation
import OceanKit
import OceanUI
import SwiftUI

public struct TodoDock: View {
  private let todos: [TodoItem]

  @Environment(\.palette) private var palette
  @State private var expanded = false

  public init(todos: [TodoItem]) {
    self.todos = todos
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      headRow
      if expanded {
        RuleLine(.row)
        listContent
      }
    }
    .background(palette.surface)
    .overlay(alignment: .top) { RuleLine(.section) }
  }

  private var doneCount: Int {
    todos.filter { $0.status == .completed }.count
  }

  private var currentTask: TodoItem? {
    todos.first { $0.status == .in_progress }
  }

  private var headRow: some View {
    Button {
      expanded.toggle()
    } label: {
      HStack(spacing: Space.s2) {
        Text("PLAN")
          .mono(10, weight: .bold)
          .tracking(0.14 * 10)
          .foregroundStyle(palette.accent)

        Text("\(doneCount)/\(todos.count)")
          .mono(10)
          .foregroundStyle(palette.textDim)

        if let currentTask, !expanded {
          Text(currentTask.content)
            .bodyText(11.5)
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
        } else {
          Spacer()
        }

        AppIcon(expanded ? .chevronDown : .chevronRight, size: 14)
          .foregroundStyle(palette.textDim)
      }
      .frame(minHeight: 38)
      .padding(.horizontal, Space.s4)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var listContent: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(todos) { todo in
          HStack(alignment: .top, spacing: 8) {
            Text(statusMark(todo.status))
              .mono(11, weight: .bold)
              .foregroundStyle(statusColor(todo.status))

            Text(todo.content)
              .bodyText(12.5)
              .strikethrough(todo.status == .completed)
              .foregroundStyle(textColor(todo.status))
              .multilineTextAlignment(.leading)
          }
          .padding(.vertical, 3)
        }
      }
      .padding(.horizontal, Space.s4)
      .padding(.vertical, 8)
    }
    .frame(maxHeight: 220)
  }

  private func statusMark(_ status: TodoStatus) -> String {
    switch status {
    case .completed: return "×"
    case .cancelled: return "–"
    case .in_progress: return "→"
    case .pending: return "□"
    }
  }

  private func statusColor(_ status: TodoStatus) -> Color {
    switch status {
    case .in_progress: return palette.accent
    case .completed, .cancelled: return palette.textDim
    case .pending: return palette.textMuted
    }
  }

  private func textColor(_ status: TodoStatus) -> Color {
    switch status {
    case .in_progress: return palette.text
    case .completed: return palette.textDim
    case .cancelled: return palette.textDim
    case .pending: return palette.textSecondary
    }
  }
}
