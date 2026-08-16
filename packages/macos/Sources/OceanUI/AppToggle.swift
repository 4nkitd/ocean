import OceanKit
import SwiftUI

/**
 A switch, drawn square because the system rounds nothing. Ported from
 `AppToggle.vue`: the whole row is the hit target, and the description is part
 of the control rather than text beside it.
 */
public struct AppToggle: View {
  private let label: String
  private let description: String?
  private let monoDescription: Bool
  private let isOn: Binding<Bool>

  @Environment(\.palette) private var palette
  @Environment(\.isEnabled) private var isEnabled

  public init(_ label: String, isOn: Binding<Bool>, description: String? = nil, monoDescription: Bool = false) {
    self.label = label
    self.isOn = isOn
    self.description = description
    self.monoDescription = monoDescription
  }

  public var body: some View {
    Button {
      isOn.wrappedValue.toggle()
    } label: {
      HStack(alignment: .center, spacing: Space.s4) {
        VStack(alignment: .leading, spacing: 2) {
          Text(label)
            .bodyText(14, weight: .semibold)
            .foregroundStyle(palette.text)
          if let description {
            if monoDescription {
              Text(description)
                .mono(11.5)
                .foregroundStyle(palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            } else {
              Text(description)
                .bodyText(12)
                .foregroundStyle(palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        SwitchTrack(on: isOn.wrappedValue)
      }
      .padding(.vertical, 14)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .opacity(isEnabled ? 1 : 0.45)
    .overlay(alignment: .top) { RuleLine(.section) }
    .overlay(alignment: .bottom) { RuleLine(.section) }
    .accessibilityAddTraits(isOn.wrappedValue ? [.isSelected] : [])
    .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
  }
}

private struct SwitchTrack: View {
  let on: Bool

  @Environment(\.palette) private var palette

  var body: some View {
    ZStack(alignment: on ? .trailing : .leading) {
      Rectangle().fill(on ? palette.accent : palette.surfaceSunken)
      Rectangle()
        .fill(on ? palette.text : palette.textDim)
        .frame(width: knob, height: knob)
        .padding(.horizontal, inset)
    }
    .frame(width: 52, height: 28)
    .overlay(
      Rectangle().strokeBorder(on ? palette.accent : palette.rule, lineWidth: RuleWidth.section)
    )
    .animation(.easeOut(duration: 0.12), value: on)
  }

  /// The on knob is a step larger and sits a step closer to the edge — in the
  /// CSS it overflows a 3px pad, which comes to the same thing.
  private var knob: CGFloat { on ? 22 : 20 }
  private var inset: CGFloat { on ? 3 : 4 }
}
