import OceanKit
import SwiftUI

/**
 Loading, empty and error states, ported from `StateBlock.vue`.

 One view for all three so every screen's non-happy path looks the same and no
 screen quietly renders nothing. The error variant always offers the retry the
 caller supplies, because a dropped connection to a laptop is usually transient.
 */
public struct StateBlock: View {
  public enum Variant: Sendable {
    case loading
    case empty
    case error
  }

  private let variant: Variant
  private let label: String?
  private let message: String
  private let retryLabel: String
  private let onRetry: (() -> Void)?

  @Environment(\.palette) private var palette

  public init(
    _ variant: Variant,
    label: String? = nil,
    message: String,
    retryLabel: String = "Try again",
    onRetry: (() -> Void)? = nil
  ) {
    self.variant = variant
    self.label = label
    self.message = message
    self.retryLabel = retryLabel
    self.onRetry = onRetry
  }

  public var body: some View {
    block
      .padding(variant == .error ? Space.s5 : 0)
      .accessibilityElement(children: .combine)
  }

  private var block: some View {
    VStack(alignment: .leading, spacing: Space.s3) {
      switch variant {
      case .loading:
        Spinner(size: 20).foregroundStyle(palette.textDim)
      case .error:
        AppIcon(.alert, size: 20).foregroundStyle(palette.accent)
      case .empty:
        EmptyView()
      }

      VStack(alignment: .leading, spacing: Space.s1) {
        if let label {
          SectionLabel(label, color: variant == .error ? palette.accent500 : nil)
        }
        Text(message)
          .bodyText(13.5)
          .foregroundStyle(variant == .empty ? palette.textMuted : palette.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if variant == .error, let onRetry {
        RetryButton(title: retryLabel, action: onRetry)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(padding)
    .background(variant == .error ? palette.surfaceRaised : .clear)
    .overlay(alignment: .leading) {
      if variant == .error {
        RuleLine(.section, axis: .vertical, color: palette.accent)
      }
    }
  }

  private var padding: EdgeInsets {
    variant == .error
      ? EdgeInsets(top: Space.s4, leading: Space.s4, bottom: Space.s4, trailing: Space.s4)
      : EdgeInsets(top: Space.s6, leading: Space.s5, bottom: Space.s6, trailing: Space.s5)
  }
}

private struct RetryButton: View {
  let title: String
  let action: () -> Void

  @Environment(\.palette) private var palette
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Text(title)
        .mono(12)
        .foregroundStyle(hovering ? palette.accent300 : palette.accent500)
        .frame(minHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
  }
}
