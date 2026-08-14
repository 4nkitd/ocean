import OceanKit
import SwiftUI

/**
 The row every list in the app is made of, ported from `SessionRow`,
 `ModelAgentSheet`'s `.row` and `AddProjectSheet`'s `.row`.

 One 1px hair rule along the bottom — rows are separated by hairs, sections by
 2px — and the active row is marked by a 2px accent rule down its leading edge
 plus the raised surface, never by a fill. `desc` is prose, `meta` is mono: a
 path, a count, a timestamp.

 Label the slots. `leading:` and `trailing:` are both the last parameter of one
 of the convenience initialisers, so an unlabelled trailing closure is genuinely
 ambiguous and the compiler will say so.
 */
public struct ListRow<Leading: View, Trailing: View>: View {
  private let title: String
  private let desc: String?
  private let meta: String?
  private let monoTitle: Bool
  private let active: Bool
  private let action: (() -> Void)?
  private let leading: () -> Leading
  private let trailing: () -> Trailing

  @Environment(\.palette) private var palette
  @Environment(\.isEnabled) private var isEnabled
  @State private var hovering = false

  public init(
    _ title: String,
    desc: String? = nil,
    meta: String? = nil,
    monoTitle: Bool = false,
    active: Bool = false,
    action: (() -> Void)? = nil,
    @ViewBuilder leading: @escaping () -> Leading,
    @ViewBuilder trailing: @escaping () -> Trailing
  ) {
    self.title = title
    self.desc = desc
    self.meta = meta
    self.monoTitle = monoTitle
    self.active = active
    self.action = action
    self.leading = leading
    self.trailing = trailing
  }

  public var body: some View {
    Group {
      if let action {
        Button(action: action) { content }
          .buttonStyle(.plain)
          .onHover { hovering = $0 }
      } else {
        content
      }
    }
    .opacity(isEnabled ? 1 : 0.6)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(active ? [.isSelected] : [])
  }

  private var content: some View {
    HStack(alignment: .top, spacing: Space.s3) {
      leading()
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(monoTitle ? OceanFont.mono(14) : OceanFont.body(14.5))
          .foregroundStyle(active ? palette.accent500 : palette.text)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
        if let desc {
          Text(desc)
            .bodyText(12)
            .foregroundStyle(palette.textMuted)
            .lineLimit(1)
        }
        if let meta {
          Text(meta)
            .mono(11)
            .foregroundStyle(active ? palette.accent500 : palette.textMuted)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      trailing()
    }
    .padding(.horizontal, Space.s5)
    .padding(.vertical, Space.s4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(fill)
    .overlay(alignment: .leading) {
      if active {
        RuleLine(.section, axis: .vertical, color: palette.accent)
      }
    }
    .overlay(alignment: .bottom) { RuleLine(.row) }
    .contentShape(Rectangle())
  }

  private var fill: Color {
    if active { return palette.surfaceRaised }
    return hovering && isEnabled && action != nil ? palette.surfaceRaised : .clear
  }
}

extension ListRow where Leading == EmptyView, Trailing == EmptyView {
  public init(
    _ title: String,
    desc: String? = nil,
    meta: String? = nil,
    monoTitle: Bool = false,
    active: Bool = false,
    action: (() -> Void)? = nil
  ) {
    self.init(
      title,
      desc: desc,
      meta: meta,
      monoTitle: monoTitle,
      active: active,
      action: action,
      leading: { EmptyView() },
      trailing: { EmptyView() }
    )
  }
}

extension ListRow where Leading == EmptyView {
  public init(
    _ title: String,
    desc: String? = nil,
    meta: String? = nil,
    monoTitle: Bool = false,
    active: Bool = false,
    action: (() -> Void)? = nil,
    @ViewBuilder trailing: @escaping () -> Trailing
  ) {
    self.init(
      title,
      desc: desc,
      meta: meta,
      monoTitle: monoTitle,
      active: active,
      action: action,
      leading: { EmptyView() },
      trailing: trailing
    )
  }
}

extension ListRow where Trailing == EmptyView {
  public init(
    _ title: String,
    desc: String? = nil,
    meta: String? = nil,
    monoTitle: Bool = false,
    active: Bool = false,
    action: (() -> Void)? = nil,
    @ViewBuilder leading: @escaping () -> Leading
  ) {
    self.init(
      title,
      desc: desc,
      meta: meta,
      monoTitle: monoTitle,
      active: active,
      action: action,
      leading: leading,
      trailing: { EmptyView() }
    )
  }
}

/// The chevron a navigable row ends with. Pushed to the far edge by `ListRow`'s
/// own layout, per the flush-left rule.
public struct RowChevron: View {
  @Environment(\.palette) private var palette

  public init() {}

  public var body: some View {
    AppIcon(.chevronRight, size: 16)
      .foregroundStyle(palette.textDim)
  }
}
