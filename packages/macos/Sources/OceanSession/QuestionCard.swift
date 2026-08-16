import Foundation
import OceanKit
import OceanUI
import SwiftUI

public struct QuestionCard: View {
  private let request: QuestionRequest
  private let pending: Int
  private let error: String?
  private let onReply: ([[String]]) -> Void
  private let onDismiss: () -> Void

  @Environment(\.palette) private var palette

  @State private var picks: [[String]]
  @State private var customs: [String]

  public init(
    request: QuestionRequest,
    pending: Int = 1,
    error: String? = nil,
    onReply: @escaping ([[String]]) -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self.request = request
    self.pending = pending
    self.error = error
    self.onReply = onReply
    self.onDismiss = onDismiss
    self._picks = State(initialValue: request.questions.map { _ in [] })
    self._customs = State(initialValue: request.questions.map { _ in "" })
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Space.s3) {
      headRow

      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: Space.s4) {
          ForEach(Array(request.questions.enumerated()), id: \.offset) { idx, q in
            questionSection(index: idx, question: q)
          }
        }
      }
      .frame(maxHeight: 300)

      if let error {
        Text("\(error) Try again.")
          .mono(11)
          .foregroundStyle(palette.accent500)
      }

      actionsRow
    }
    .padding(Space.s4)
    .background(palette.surfaceRaised)
    .overlay(alignment: .top) { RuleLine(.section, color: palette.accent) }
    .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section))
  }

  private var headRow: some View {
    HStack(spacing: 7) {
      Spinner(size: 13).foregroundStyle(palette.accent)
      Text("THE AGENT ASKS")
        .mono(10, weight: .bold)
        .tracking(0.14 * 10)
        .foregroundStyle(palette.accent)
      Spacer()
      if pending > 1 {
        Text("\(pending - 1) more")
          .mono(10)
          .foregroundStyle(palette.textDim)
      }
    }
  }

  private func questionSection(index: Int, question: QuestionInfo) -> some View {
    VStack(alignment: .leading, spacing: Space.s2) {
      if let header = question.header, !header.isEmpty {
        Text(header.uppercased())
          .mono(10, weight: .semibold)
          .foregroundStyle(palette.textDim)
      }

      Text(question.question)
        .bodyText(14, weight: .semibold)
        .foregroundStyle(palette.text)

      VStack(alignment: .leading, spacing: Space.s2) {
        ForEach(question.options, id: \.label) { option in
          let picked = isPicked(index: index, label: option.label)
          Button {
            toggleOption(index: index, option: option, multiple: question.multiple)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                  .mono(12.5, weight: .semibold)
                  .foregroundStyle(picked ? palette.accent500 : palette.text)
                if let desc = option.description, !desc.isEmpty {
                  Text(desc)
                    .bodyText(11.5)
                    .foregroundStyle(palette.textMuted)
                }
              }
              Spacer()
            }
            .padding(Space.s3)
            .background(palette.surface)
            .overlay(
              Rectangle().strokeBorder(picked ? palette.accent : palette.rule, lineWidth: RuleWidth.section)
            )
          }
          .buttonStyle(.plain)
        }
      }

      if question.custom {
        AppTextField(
          "",
          text: Binding(
            get: { customs[index] },
            set: { val in
              customs[index] = val
              if !question.multiple && !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                picks[index].removeAll()
              }
            }
          ),
          placeholder: "Or type your own answer…"
        )
      }
    }
  }

  private func isPicked(index: Int, label: String) -> Bool {
    picks[index].contains(label)
  }

  private func toggleOption(index: Int, option: QuestionOption, multiple: Bool) {
    if multiple {
      if picks[index].contains(option.label) {
        picks[index].removeAll { $0 == option.label }
      } else {
        picks[index].append(option.label)
      }
    } else {
      if picks[index].contains(option.label) {
        picks[index].removeAll()
      } else {
        picks[index] = [option.label]
        customs[index] = ""
      }
    }
  }

  private func answerFor(index: Int) -> [String] {
    let typed = customs[index].trimmingCharacters(in: .whitespacesAndNewlines)
    let chosen = picks[index]
    if request.questions[index].multiple {
      return typed.isEmpty ? chosen : chosen + [typed]
    }
    return !chosen.isEmpty ? chosen : (typed.isEmpty ? [] : [typed])
  }

  private var isComplete: Bool {
    request.questions.indices.allSatisfy { !answerFor(index: $0).isEmpty }
  }

  private var actionsRow: some View {
    HStack(spacing: Space.s2) {
      AppButton("Answer", variant: .primary, centered: true) {
        let answers = request.questions.indices.map { answerFor(index: $0) }
        onReply(answers)
      }
      .disabled(!isComplete)

      AppButton("Dismiss", variant: .secondary, centered: true) {
        onDismiss()
      }
    }
  }
}
