import OceanKit
import OceanUI
import SwiftUI

public struct DiffBody: View {
  public let diff: FileDiff

  @Environment(\.palette) private var palette

  public init(diff: FileDiff) {
    self.diff = diff
  }

  public var body: some View {
    ScrollView([.horizontal, .vertical]) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(diff.hunks.enumerated()), id: \.offset) { hunkIdx, hunk in
          VStack(alignment: .leading, spacing: 0) {
            // Hunk header band
            Text(hunk.header)
              .mono(12)
              .foregroundStyle(palette.textMuted)
              .padding(.horizontal, Space.s5)
              .padding(.vertical, Space.s2)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(palette.surfaceSunken)

            // Hunk lines
            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { lineIdx, line in
              HStack(spacing: 0) {
                // Line numbers gutter
                HStack(spacing: Space.s1) {
                  Text(line.oldNumber != nil ? "\(line.oldNumber!)" : "")
                    .mono(11)
                    .foregroundStyle(palette.textFaint)
                    .frame(width: 32, alignment: .trailing)

                  Text(line.newNumber != nil ? "\(line.newNumber!)" : "")
                    .mono(11)
                    .foregroundStyle(palette.textFaint)
                    .frame(width: 32, alignment: .trailing)
                }
                .padding(.trailing, Space.s3)

                // Marker
                Text(marker(line.kind))
                  .mono(12)
                  .foregroundStyle(markerColor(line.kind))
                  .frame(width: 16, alignment: .leading)

                // Line text
                Text(line.text.isEmpty ? " " : line.text)
                  .mono(12)
                  .strikethrough(line.kind == .del, color: palette.textFaint)
                  .foregroundStyle(textColor(line.kind))
              }
              .padding(.horizontal, Space.s5)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(backgroundColor(line.kind))
              .overlay(alignment: .leading) {
                if line.kind == .add {
                  Rectangle()
                    .fill(palette.accent)
                    .frame(width: 2)
                }
              }
            }
          }
          .padding(.top, hunkIdx > 0 ? Space.s2 : 0)
        }
      }
      .padding(.vertical, Space.s2)
    }
    .background(palette.surface)
  }

  private func marker(_ kind: DiffLine.Kind) -> String {
    switch kind {
    case .add: return "+"
    case .del: return "−"
    case .context: return " "
    }
  }

  private func markerColor(_ kind: DiffLine.Kind) -> Color {
    switch kind {
    case .add: return palette.accent
    case .del: return palette.diffDelText
    case .context: return palette.textFaint
    }
  }

  private func textColor(_ kind: DiffLine.Kind) -> Color {
    switch kind {
    case .add: return palette.text
    case .del: return palette.diffDelText
    case .context: return palette.textSecondary
    }
  }

  private func backgroundColor(_ kind: DiffLine.Kind) -> Color {
    switch kind {
    case .add: return palette.diffAddBg
    case .del: return palette.diffDelBg
    case .context: return palette.surface
    }
  }
}
