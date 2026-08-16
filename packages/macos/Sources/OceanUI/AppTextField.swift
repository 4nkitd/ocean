import OceanKit
import SwiftUI

/**
 A labelled text field, ported from `AppInput.vue`.

 The label is the system's small uppercase mono kicker, the value is monospace,
 and focus is carried by the 2px border turning accent plus a ring outside it —
 a colour change on an already-2px border is not enough of an indicator on its
 own.
 */
public struct AppTextField: View {
  private let label: String
  private let text: Binding<String>
  private let placeholder: String
  private let invalid: Bool
  private let error: String?
  private let hint: String?
  private let onSubmit: (() -> Void)?

  @FocusState private var focused: Bool

  public init(
    _ label: String,
    text: Binding<String>,
    placeholder: String = "",
    invalid: Bool = false,
    error: String? = nil,
    hint: String? = nil,
    onSubmit: (() -> Void)? = nil
  ) {
    self.label = label
    self.text = text
    self.placeholder = placeholder
    self.invalid = invalid
    self.error = error
    self.hint = hint
    self.onSubmit = onSubmit
  }

  public var body: some View {
    FieldShell(label: label, error: error, hint: hint, focused: focused, invalid: invalid) {
      FieldInput(text: text, placeholder: placeholder, secure: false, onSubmit: onSubmit)
        .focused($focused)
    }
  }
}

/// The password field, with the reveal affordance the design puts at the
/// trailing edge. Revealing swaps in a plain field, so the border has to belong
/// to the shell rather than the control — same as the Vue `--split` case.
public struct AppSecureField: View {
  private let label: String
  private let text: Binding<String>
  private let placeholder: String
  private let invalid: Bool
  private let error: String?
  private let hint: String?
  private let onSubmit: (() -> Void)?

  @Environment(\.palette) private var palette
  @FocusState private var focused: Bool
  @State private var revealed = false

  public init(
    _ label: String,
    text: Binding<String>,
    placeholder: String = "",
    invalid: Bool = false,
    error: String? = nil,
    hint: String? = nil,
    onSubmit: (() -> Void)? = nil
  ) {
    self.label = label
    self.text = text
    self.placeholder = placeholder
    self.invalid = invalid
    self.error = error
    self.hint = hint
    self.onSubmit = onSubmit
  }

  public var body: some View {
    FieldShell(label: label, error: error, hint: hint, focused: focused, invalid: invalid) {
      FieldInput(text: text, placeholder: placeholder, secure: !revealed, onSubmit: onSubmit)
        .focused($focused)
        .id(revealed)

      Button {
        revealed.toggle()
      } label: {
        AppIcon(revealed ? .eyeOff : .eye, size: 18)
          .foregroundStyle(palette.textMuted)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(revealed ? "Hide" : "Reveal")
    }
  }
}

private struct FieldInput: View {
  let text: Binding<String>
  let placeholder: String
  let secure: Bool
  let onSubmit: (() -> Void)?

  @Environment(\.palette) private var palette

  var body: some View {
    Group {
      if secure {
        SecureField("", text: text, prompt: prompt)
      } else {
        TextField("", text: text, prompt: prompt)
      }
    }
    .textFieldStyle(.plain)
    .font(OceanFont.mono(15))
    .foregroundStyle(palette.text)
    .tint(palette.accent)
    .autocorrectionDisabled()
    .padding(14)
    .onSubmit { onSubmit?() }
  }

  private var prompt: Text? {
    placeholder.isEmpty ? nil : Text(placeholder).foregroundStyle(palette.textDim)
  }
}

/// Shared by every field in the target — the kicker, the bordered control, the
/// focus ring outside the border, and the error-or-hint line under it.
struct FieldShell<Content: View>: View {
  var label: String?
  var error: String?
  var hint: String?
  var focused: Bool
  var invalid: Bool
  @ViewBuilder let content: () -> Content

  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: Space.s2) {
      if let label {
        SectionLabel(label)
      }

      HStack(spacing: 0) {
        content()
      }
      .background(palette.surfaceRaised)
      .clipShape(Rectangle())
      .overlay(Rectangle().strokeBorder(borderColor, lineWidth: RuleWidth.section))
      .overlay {
        if focused {
          Rectangle()
            .strokeBorder(palette.accent, lineWidth: RuleWidth.section)
            .padding(-(RuleWidth.section + 2))
        }
      }

      if let error {
        Text(error)
          .bodyText(12)
          .foregroundStyle(palette.accent500)
          .fixedSize(horizontal: false, vertical: true)
      } else if let hint {
        Text(hint)
          .bodyText(12)
          .foregroundStyle(palette.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var borderColor: Color {
    invalid || focused ? palette.accent : palette.rule
  }
}
