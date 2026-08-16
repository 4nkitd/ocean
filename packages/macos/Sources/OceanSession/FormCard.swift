import Foundation
import OceanKit
import OceanUI
import SwiftUI

public struct FormCard: View {
  private let request: FormRequest
  private let pending: Int
  private let error: String?
  private let onReply: (FormAnswer) -> Void
  private let onCancel: () -> Void

  @Environment(\.palette) private var palette

  @State private var texts: [String: String] = [:]
  @State private var picks: [String: [String]] = [:]
  @State private var flags: [String: Bool] = [:]
  @State private var acked: [String: Bool] = [:]

  public init(
    request: FormRequest,
    pending: Int = 1,
    error: String? = nil,
    onReply: @escaping (FormAnswer) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.request = request
    self.pending = pending
    self.error = error
    self.onReply = onReply
    self.onCancel = onCancel

    var initTexts: [String: String] = [:]
    var initPicks: [String: [String]] = [:]
    var initFlags: [String: Bool] = [:]

    for field in request.fields {
      initTexts[field.key] = ""
      switch field {
      case .string(let sf):
        let listed = sf.options?.contains(where: { $0.value == sf.default }) ?? false
        if listed, let def = sf.default { initPicks[field.key] = [def] }
        else if let def = sf.default { initTexts[field.key] = def }
      case .number(let nf):
        if let def = nf.default { initTexts[field.key] = String(def) }
      case .boolean(let bf):
        if let def = bf.default { initFlags[field.key] = def }
      case .multiselect(let mf):
        if let def = mf.default { initPicks[field.key] = def }
      case .external:
        break
      }
    }

    self._texts = State(initialValue: initTexts)
    self._picks = State(initialValue: initPicks)
    self._flags = State(initialValue: initFlags)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Space.s3) {
      headRow

      Text(request.title)
        .bodyText(14, weight: .bold)
        .foregroundStyle(palette.text)

      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: Space.s4) {
          ForEach(activeFields) { field in
            renderField(field)
          }
        }
      }
      .frame(maxHeight: 320)

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
      Text("FORM REQUEST")
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

  private var currentAnswers: FormAnswer {
    var answer: FormAnswer = [:]
    for field in request.fields {
      if let val = valueOf(field) {
        answer[field.key] = val
      }
    }
    return answer
  }

  private var activeFields: [FormField] {
    let answers = currentAnswers
    return request.fields.filter { $0.isActive(in: answers) }
  }

  private func valueOf(_ field: FormField) -> FormValue? {
    switch field {
    case .boolean:
      if let b = flags[field.key] { return .boolean(b) }
      return nil

    case .number(let nf):
      let str = (texts[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !str.isEmpty, let d = Double(str) else { return nil }
      if nf.integer && floor(d) != d { return nil }
      return .number(d)

    case .multiselect:
      let list = chosenStrings(field)
      return list.isEmpty ? nil : .list(list)

    case .external:
      return acked[field.key] == true ? .boolean(true) : nil

    case .string:
      let chosen = chosenStrings(field)
      return chosen.first.map { .string($0) }
    }
  }

  private func chosenStrings(_ field: FormField) -> [String] {
    let listed = picks[field.key] ?? []
    let typed = (texts[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    switch field {
    case .string(let sf):
      if sf.options != nil && !sf.options!.isEmpty {
        if sf.custom && !typed.isEmpty && !listed.contains(typed) {
          return listed.isEmpty ? [typed] : listed + [typed]
        }
        return listed
      }
      return typed.isEmpty ? [] : [typed]

    case .multiselect(let mf):
      if mf.custom && !typed.isEmpty && !listed.contains(typed) {
        return listed + [typed]
      }
      return listed

    default:
      return []
    }
  }

  @ViewBuilder
  private func renderField(_ field: FormField) -> some View {
    VStack(alignment: .leading, spacing: Space.s2) {
      HStack {
        Text(field.base.title ?? field.key)
          .bodyText(13.5, weight: .semibold)
          .foregroundStyle(palette.text)
        if field.base.required {
          Text("*").mono(12).foregroundStyle(palette.accent)
        }
      }

      if let desc = field.base.description, !desc.isEmpty {
        Text(desc)
          .bodyText(11.5)
          .foregroundStyle(palette.textMuted)
      }

      switch field {
      case .boolean:
        HStack(spacing: Space.s2) {
          Button {
            flags[field.key] = true
          } label: {
            Text("Yes")
              .mono(12, weight: .semibold)
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
              .background(flags[field.key] == true ? palette.surfaceSunken : palette.surface)
              .overlay(Rectangle().strokeBorder(flags[field.key] == true ? palette.accent : palette.rule, lineWidth: RuleWidth.section))
          }
          .buttonStyle(.plain)

          Button {
            flags[field.key] = false
          } label: {
            Text("No")
              .mono(12, weight: .semibold)
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
              .background(flags[field.key] == false ? palette.surfaceSunken : palette.surface)
              .overlay(Rectangle().strokeBorder(flags[field.key] == false ? palette.accent : palette.rule, lineWidth: RuleWidth.section))
          }
          .buttonStyle(.plain)
        }

      case .external(let ef):
        HStack(spacing: Space.s2) {
          if let url = URL(string: ef.url) {
            Link(destination: url) {
              HStack(spacing: 4) {
                AppIcon(.arrowRight, size: 14)
                Text("Open URL")
                  .mono(12, weight: .semibold)
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background(palette.surface)
              .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section))
            }
          }

          AppButton(acked[field.key] == true ? "Acknowledged" : "Acknowledge", variant: acked[field.key] == true ? .primary : .secondary) {
            acked[field.key] = true
          }
        }

      case .number(let nf):
        AppTextField(
          "",
          text: Binding(
            get: { texts[field.key] ?? "" },
            set: { texts[field.key] = $0 }
          ),
          placeholder: nf.integer ? "Enter integer…" : "Enter number…"
        )

      case .multiselect(let mf):
        VStack(alignment: .leading, spacing: Space.s2) {
          ForEach(mf.options) { option in
            let picked = (picks[field.key] ?? []).contains(option.value)
            Button {
              var current = picks[field.key] ?? []
              if picked {
                current.removeAll { $0 == option.value }
              } else {
                current.append(option.value)
              }
              picks[field.key] = current
            } label: {
              HStack {
                Text(option.label)
                  .mono(12, weight: .semibold)
                  .foregroundStyle(picked ? palette.accent500 : palette.text)
                Spacer()
              }
              .padding(Space.s2)
              .background(palette.surface)
              .overlay(Rectangle().strokeBorder(picked ? palette.accent : palette.rule, lineWidth: RuleWidth.section))
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }

          if mf.custom {
            AppTextField(
              "",
              text: Binding(
                get: { texts[field.key] ?? "" },
                set: { texts[field.key] = $0 }
              ),
              placeholder: "Add custom value…"
            )
          }
        }

      case .string(let sf):
        if let options = sf.options, !options.isEmpty {
          VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(options) { option in
              let picked = (picks[field.key] ?? []).contains(option.value)
              Button {
                if picked {
                  picks[field.key] = []
                } else {
                  picks[field.key] = [option.value]
                  texts[field.key] = ""
                }
              } label: {
                HStack {
                  Text(option.label)
                    .mono(12, weight: .semibold)
                    .foregroundStyle(picked ? palette.accent500 : palette.text)
                  Spacer()
                }
                .padding(Space.s2)
                .background(palette.surface)
                .overlay(Rectangle().strokeBorder(picked ? palette.accent : palette.rule, lineWidth: RuleWidth.section))
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }

            if sf.custom {
              AppTextField(
                "",
                text: Binding(
                  get: { texts[field.key] ?? "" },
                  set: {
                    texts[field.key] = $0
                    if !$0.isEmpty { picks[field.key] = [] }
                  }
                ),
                placeholder: "Or type your own answer…"
              )
            }
          }
        } else {
          AppTextField(
            "",
            text: Binding(
              get: { texts[field.key] ?? "" },
              set: { texts[field.key] = $0 }
            ),
            placeholder: sf.placeholder ?? "Enter text…"
          )
        }
      }
    }
  }

  private var isComplete: Bool {
    activeFields.allSatisfy { field in
      if field.base.required {
        return valueOf(field) != nil
      }
      if case .external = field {
        return acked[field.key] == true
      }
      return true
    }
  }

  private var actionsRow: some View {
    HStack(spacing: Space.s2) {
      AppButton("Submit", variant: .primary, centered: true) {
        var finalAnswer: FormAnswer = [:]
        for field in activeFields {
          if let val = valueOf(field) {
            finalAnswer[field.key] = val
          }
        }
        onReply(finalAnswer)
      }
      .disabled(!isComplete)

      AppButton("Cancel", variant: .secondary, centered: true) {
        onCancel()
      }
    }
  }
}
