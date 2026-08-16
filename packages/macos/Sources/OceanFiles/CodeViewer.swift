import OceanKit
import OceanUI
import SwiftUI

public struct CodeViewer: View {
  private let content: String
  private let language: String
  private let changedLines: Set<Int>
  @Binding private var selectedLine: Int?

  @Environment(\.palette) private var palette

  public init(
    content: String,
    language: String,
    changedLines: Set<Int> = [],
    selectedLine: Binding<Int?>
  ) {
    self.content = content
    self.language = language
    self.changedLines = changedLines
    self._selectedLine = selectedLine
  }

  @State private var tokenizedLines: [[Token]]?

  public var body: some View {
    Group {
      if let lines = tokenizedLines {
        ScrollView([.horizontal, .vertical]) {
          LazyVStack(alignment: .leading, spacing: 0) {
            let maxLines = min(lines.count, 3_000)
            ForEach(0..<maxLines, id: \.self) { index in
              let lineNum = index + 1
              let tokens = lines[index]
              let isChanged = changedLines.contains(lineNum)
              let isSelected = selectedLine == lineNum

              Button {
                selectedLine = lineNum
              } label: {
                HStack(spacing: 0) {
                  // Sticky Gutter
                  Text("\(lineNum)")
                    .mono(12)
                    .foregroundStyle(
                      isSelected
                        ? palette.accent
                        : isChanged ? palette.textMuted : palette.textFaint
                    )
                    .frame(width: 44, alignment: .trailing)
                    .padding(.trailing, Space.s3)

                  // Code Tokens
                  lineText(tokens: tokens)

                  Spacer(minLength: Space.s5)
                }
                .padding(.vertical, 1)
                .background(
                  isSelected
                    ? palette.surfaceSunken
                    : isChanged ? palette.surfaceRaised : palette.surface
                )
              }
              .buttonStyle(.plain)
            }

            if lines.count > 3_000 {
              Text("\(lines.count - 3_000) more lines not shown")
                .mono(11)
                .foregroundStyle(palette.textMuted)
                .padding(Space.s4)
            }
          }
          .padding(.vertical, Space.s3)
        }
      } else {
        StateBlock(.loading, label: "Code", message: "Highlighting code…")
      }
    }
    .background(palette.surface)
    .task(id: content) {
      let code = content
      let lang = language
      tokenizedLines = await Task.detached(priority: .userInitiated) {
        SyntaxHighlighter.tokenize(code, language: lang)
      }.value
    }
  }

  private func lineText(tokens: [Token]) -> Text {
    if tokens.isEmpty {
      return Text(" ").mono(12.5)
    }
    var attributed = AttributedString()
    for token in tokens {
      var container = AttributedString(token.text)
      container.foregroundColor = tokenColor(token.kind)
      attributed.append(container)
    }
    return Text(attributed).mono(12.5)
  }

  private func tokenColor(_ kind: TokenKind) -> Color {
    switch kind {
    case .keyword:
      return palette.accent
    case .string:
      return palette.accent300
    case .function:
      return palette.accent500
    case .number:
      return palette.accent400
    case .comment:
      return palette.textDim
    case .plain:
      return palette.text
    }
  }
}
