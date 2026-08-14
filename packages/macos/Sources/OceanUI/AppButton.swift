import OceanKit
import SwiftUI

/**
 The system's button, ported from `AppButton.vue`.

 Unusual in one way worth knowing: labels are flush left, not centred, and a
 trailing icon is pushed to the far edge. That is the Modernist rule — labels
 sit flush left, even inside buttons — and it is why this exists rather than a
 modifier on `Button`.
 */
public struct AppButton: View {
  public enum Variant: Sendable {
    case primary
    case secondary
    case ghost
  }

  private let title: String
  private let variant: Variant
  private let icon: IconName?
  private let loading: Bool
  private let centered: Bool
  private let action: () -> Void

  public init(
    _ title: String,
    variant: Variant = .primary,
    icon: IconName? = nil,
    loading: Bool = false,
    centered: Bool = false,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.variant = variant
    self.icon = icon
    self.loading = loading
    self.centered = centered
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      if centered {
        HStack(spacing: Space.s3) {
          Spacer(minLength: 0)
          label
          trailing
          Spacer(minLength: 0)
        }
      } else {
        HStack(spacing: Space.s3) {
          label
          Spacer(minLength: Space.s3)
          trailing
        }
      }
    }
    .buttonStyle(AppButtonStyle(variant: variant))
    .disabled(loading)
    .accessibilityAddTraits(loading ? [.updatesFrequently] : [])
  }

  private var label: some View {
    Text(title)
      .font(OceanFont.body(15, weight: .semibold))
      .lineLimit(1)
      .truncationMode(.tail)
  }

  @ViewBuilder
  private var trailing: some View {
    if loading {
      Spinner(size: 18)
    } else if let icon {
      AppIcon(icon, size: 18)
    }
  }
}

struct AppButtonStyle: ButtonStyle {
  let variant: AppButton.Variant

  func makeBody(configuration: Configuration) -> some View {
    Chrome(variant: variant, configuration: configuration)
  }

  private struct Chrome: View {
    let variant: AppButton.Variant
    let configuration: AppButtonStyle.Configuration

    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
      configuration.label
        .foregroundStyle(foreground)
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background(background)
        .overlay(Rectangle().strokeBorder(border, lineWidth: RuleWidth.section))
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(Rectangle())
        .onHover { hovering = $0 && isEnabled }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var pressed: Bool { configuration.isPressed && isEnabled }
    private var hovered: Bool { hovering && isEnabled }

    /// The design insets a filled button's label further than an outlined one,
    /// so the text sits off the fill edge rather than off a hairline. The extra
    /// 2 is the border the CSS counts inside its box.
    private var horizontalPadding: CGFloat {
      switch variant {
      case .primary: return 20
      case .secondary: return 18
      case .ghost: return 0
      }
    }

    private var minHeight: CGFloat {
      variant == .ghost ? 44 : 52
    }

    private var foreground: Color {
      switch variant {
      case .primary: return palette.onAccent
      case .secondary: return palette.text
      case .ghost: return hovered ? palette.accent300 : palette.accent500
      }
    }

    private var background: Color {
      switch variant {
      case .primary:
        if pressed { return palette.accent700 }
        return hovered ? palette.accent600 : palette.accent
      case .secondary:
        if pressed { return palette.surfaceSunken }
        return hovered ? palette.surfaceRaised : .clear
      case .ghost:
        return .clear
      }
    }

    private var border: Color {
      variant == .secondary ? palette.rule : .clear
    }
  }
}
