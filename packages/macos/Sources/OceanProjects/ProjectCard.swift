import OceanKit
import OceanUI
import SwiftUI

public struct ProjectCard: View {
  private let project: ProjectRow
  private let active: Bool
  private let reordering: Bool
  private let canMoveUp: Bool
  private let canMoveDown: Bool
  private let onSelect: () -> Void
  private let onMove: (Int) -> Void
  private let onFavourite: () -> Void

  @Environment(\.palette) private var palette

  public init(
    project: ProjectRow,
    active: Bool = false,
    reordering: Bool = false,
    canMoveUp: Bool = false,
    canMoveDown: Bool = false,
    onSelect: @escaping () -> Void,
    onMove: @escaping (Int) -> Void,
    onFavourite: @escaping () -> Void
  ) {
    self.project = project
    self.active = active
    self.reordering = reordering
    self.canMoveUp = canMoveUp
    self.canMoveDown = canMoveDown
    self.onSelect = onSelect
    self.onMove = onMove
    self.onFavourite = onFavourite
  }

  public var body: some View {
    HStack(spacing: 0) {
      Button {
        if !reordering { onSelect() }
      } label: {
        HStack(spacing: Space.s4) {
          tile
          bodyText
          Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if reordering {
        reorderButtons
          .padding(.trailing, Space.s4)
          .padding(.vertical, Space.s4)
      } else {
        trailingInfo
          .padding(.trailing, Space.s4)
          .padding(.vertical, Space.s4)
      }
    }
    .background(active ? palette.surfaceRaised : palette.surface)
    .overlay(alignment: .leading) {
      if active {
        Rectangle()
          .fill(palette.accent)
          .frame(width: 2)
      }
    }
  }

  private var tile: some View {
    Text(project.initials)
      .font(OceanFont.mono(15, weight: .bold))
      .foregroundStyle(palette.textSecondary)
      .frame(width: 44, height: 44)
      .background(palette.surfaceSunken)
  }

  private var bodyText: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(project.name)
        .font(OceanFont.body(15, weight: .semibold))
        .foregroundStyle(palette.text)
        .lineLimit(1)
        .truncationMode(.middle)

      Text(project.displayPath)
        .mono(11)
        .foregroundStyle(palette.textMuted)
        .lineLimit(1)
        .truncationMode(.middle)

      HStack(spacing: Space.s2) {
        if project.isGit {
          Chip(project.branch ?? "git", tone: .neutral)
        } else {
          Chip("NO REPO", tone: .neutral)
        }

        Text("\(project.sessionCount) \(project.sessionCount == 1 ? "session" : "sessions")")
          .mono(11)
          .foregroundStyle(palette.textMuted)
      }
      .padding(.top, 4)
    }
  }

  private var trailingInfo: some View {
    VStack(alignment: .trailing, spacing: Space.s2) {
      Button(action: onFavourite) {
        Text("★")
          .font(.system(size: 14))
          .foregroundStyle(project.favourite ? palette.text : palette.textFaint)
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)

      Spacer(minLength: 0)

      if project.running {
        StatusDot(.accent, size: 8)
      }

      if let timeStr = Formatters.shortRelativeTime(project.lastActivity) {
        Text(timeStr)
          .mono(11)
          .foregroundStyle(palette.textMuted)
      } else {
        Text("no activity")
          .mono(11)
          .foregroundStyle(palette.textMuted)
      }
    }
  }

  private var reorderButtons: some View {
    HStack(spacing: Space.s1) {
      IconButton(.chevronDown, label: "Move up", size: 16) {
        onMove(-1)
      }
      .rotationEffect(.degrees(180))
      .disabled(!canMoveUp)

      IconButton(.chevronDown, label: "Move down", size: 16) {
        onMove(1)
      }
      .disabled(!canMoveDown)
    }
  }
}
