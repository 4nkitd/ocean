import OceanKit
import SwiftUI

/**
 A multi-line field, ported from the composer's `box__field`.

 Body font rather than mono: this carries prose — a prompt, a commit message —
 and the mono roles are for paths, counts and ids. Same chrome as `AppTextField`
 so a form can mix the two without a seam.
 */
public struct AppTextArea: View {
  private let label: String?
  private let text: Binding<String>
  private let placeholder: String
  private let minHeight: CGFloat
  private let maxHeight: CGFloat?
  private let mono: Bool
  private let invalid: Bool
  private let error: String?
  private let hint: String?

  @Environment(\.palette) private var palette
  @FocusState private var focused: Bool

  public init(
    _ label: String? = nil,
    text: Binding<String>,
    placeholder: String = "",
    minHeight: CGFloat = 96,
    maxHeight: CGFloat? = nil,
    mono: Bool = false,
    invalid: Bool = false,
    error: String? = nil,
    hint: String? = nil
  ) {
    self.label = label
    self.text = text
    self.placeholder = placeholder
    self.minHeight = minHeight
    self.maxHeight = maxHeight
    self.mono = mono
    self.invalid = invalid
    self.error = error
    self.hint = hint
  }

  public var body: some View {
    FieldShell(label: label, error: error, hint: hint, focused: focused, invalid: invalid) {
      TextEditor(text: text)
        .focused($focused)
        .textEditorStyle(.plain)
        .scrollContentBackground(.hidden)
        .font(mono ? OceanFont.mono(13.5) : OceanFont.body(13.5))
        .foregroundStyle(palette.text)
        .tint(palette.accent)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(minHeight: minHeight, maxHeight: maxHeight, alignment: .topLeading)
        .background(alignment: .topLeading) {
          if text.wrappedValue.isEmpty, !placeholder.isEmpty {
            // 14 not 9: TextEditor insets its own text by about five points,
            // and the placeholder has to land on the same left edge.
            Text(placeholder)
              .font(mono ? OceanFont.mono(13.5) : OceanFont.body(13.5))
              .foregroundStyle(palette.textDim)
              .padding(.horizontal, 14)
              .padding(.vertical, 8)
              .allowsHitTesting(false)
          }
        }
    }
  }
}

/**
 The filter field that heads a list, ported from `FilesView`'s `.filter`.

 Not `AppTextField` with an icon bolted on: it is shorter, always mono, has no
 kicker, and clears itself — a different control that happens to share a border.
 */
public struct AppSearchField: View {
  private let placeholder: String
  private let text: Binding<String>
  private let onSubmit: (() -> Void)?

  @Environment(\.palette) private var palette
  @FocusState private var focused: Bool

  public init(
    _ placeholder: String = "Filter",
    text: Binding<String>,
    onSubmit: (() -> Void)? = nil
  ) {
    self.placeholder = placeholder
    self.text = text
    self.onSubmit = onSubmit
  }

  public var body: some View {
    HStack(spacing: Space.s2) {
      AppIcon(.search, size: 14)
        .foregroundStyle(palette.textDim)

      TextField("", text: text, prompt: Text(placeholder).foregroundStyle(palette.textDim))
        .textFieldStyle(.plain)
        .focused($focused)
        .font(OceanFont.mono(13))
        .foregroundStyle(palette.text)
        .tint(palette.accent)
        .autocorrectionDisabled()
        .onSubmit { onSubmit?() }

      if !text.wrappedValue.isEmpty {
        Button {
          text.wrappedValue = ""
        } label: {
          AppIcon(.close, size: 14)
            .foregroundStyle(palette.textMuted)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear")
      }
    }
    .padding(.horizontal, Space.s3)
    .frame(minHeight: 38)
    .background(palette.surfaceRaised)
    .overlay(
      Rectangle()
        .strokeBorder(focused ? palette.accent : palette.rule, lineWidth: RuleWidth.section)
    )
    .overlay {
      if focused {
        Rectangle()
          .strokeBorder(palette.accent, lineWidth: RuleWidth.section)
          .padding(-(RuleWidth.section + 2))
      }
    }
  }
}
