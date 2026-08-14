import OceanKit
import SwiftUI

/**
 A pickable option, ported from `QuestionCard`'s `.q__option` and `FormCard`'s
 `.f__option`.

 There is no tick and no radio pip: selection is carried by the border turning
 accent and the label going with it. Single and multiple choice look identical
 in this design — the card above says which it is — so this control does not
 try to distinguish them either.
 */
public struct OptionRow: View {
  private let label: String
  private let description: String?
  private let selected: Bool
  private let action: () -> Void

  @Environment(\.palette) private var palette
  @Environment(\.isEnabled) private var isEnabled
  @State private var hovering = false

  public init(
    _ label: String,
    description: String? = nil,
    selected: Bool,
    action: @escaping () -> Void
  ) {
    self.label = label
    self.description = description
    self.selected = selected
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .font(OceanFont.mono(12.5))
          .foregroundStyle(selected ? palette.accent500 : palette.text)
        if let description {
          Text(description)
            .bodyText(11.5)
            .foregroundStyle(palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(hovering && isEnabled ? palette.surfaceRaised : .clear)
      .overlay(
        Rectangle()
          .strokeBorder(selected ? palette.accent : palette.rule, lineWidth: RuleWidth.section)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .opacity(isEnabled ? 1 : 0.5)
    .onHover { hovering = $0 }
    .accessibilityAddTraits(selected ? [.isSelected] : [])
  }
}

/// A square box with a tick. Not in the Vue client — it has no checkbox
/// anywhere — but a desktop settings pane wants one, and this is what the
/// system's geometry says it looks like.
public struct AppCheckbox: View {
  private let label: String
  private let description: String?
  private let isOn: Binding<Bool>

  @Environment(\.palette) private var palette
  @Environment(\.isEnabled) private var isEnabled

  public init(_ label: String, isOn: Binding<Bool>, description: String? = nil) {
    self.label = label
    self.isOn = isOn
    self.description = description
  }

  public var body: some View {
    ChoiceRow(
      label: label,
      description: description,
      on: isOn.wrappedValue,
      marker: { on in
        Rectangle()
          .strokeBorder(on ? palette.accent : palette.rule, lineWidth: RuleWidth.section)
          .background(on ? palette.accent : Color.clear)
          .frame(width: 16, height: 16)
          .overlay {
            if on {
              AppIcon(.check, size: 12).foregroundStyle(palette.onAccent)
            }
          }
      },
      action: { isOn.wrappedValue.toggle() }
    )
    .opacity(isEnabled ? 1 : 0.45)
    .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
  }
}

/// One of a set. Square, like everything else — a round radio would be the only
/// curve in the whole app.
public struct AppRadio<Value: Hashable>: View {
  private let label: String
  private let description: String?
  private let value: Value
  private let selection: Binding<Value>

  @Environment(\.palette) private var palette
  @Environment(\.isEnabled) private var isEnabled

  public init(
    _ label: String,
    value: Value,
    selection: Binding<Value>,
    description: String? = nil
  ) {
    self.label = label
    self.value = value
    self.selection = selection
    self.description = description
  }

  public var body: some View {
    ChoiceRow(
      label: label,
      description: description,
      on: selection.wrappedValue == value,
      marker: { on in
        Rectangle()
          .strokeBorder(on ? palette.accent : palette.rule, lineWidth: RuleWidth.section)
          .frame(width: 16, height: 16)
          .overlay {
            if on {
              Rectangle().fill(palette.accent).frame(width: 6, height: 6)
            }
          }
      },
      action: { selection.wrappedValue = value }
    )
    .opacity(isEnabled ? 1 : 0.45)
    .accessibilityAddTraits(selection.wrappedValue == value ? [.isSelected] : [])
  }
}

private struct ChoiceRow<Marker: View>: View {
  let label: String
  let description: String?
  let on: Bool
  @ViewBuilder let marker: (Bool) -> Marker
  let action: () -> Void

  @Environment(\.palette) private var palette
  @Environment(\.isEnabled) private var isEnabled
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
        marker(on)
          .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
        VStack(alignment: .leading, spacing: 2) {
          Text(label)
            .bodyText(14)
            .foregroundStyle(palette.text)
          if let description {
            Text(description)
              .bodyText(12)
              .foregroundStyle(palette.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(.vertical, Space.s2)
      .background(hovering && isEnabled ? palette.surfaceRaised : .clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
  }
}
