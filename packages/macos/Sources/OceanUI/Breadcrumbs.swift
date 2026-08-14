import OceanKit
import SwiftUI

public struct Crumb: Identifiable, Hashable {
  public let id: String
  public let label: String

  public init(_ label: String, id: String? = nil) {
    self.label = label
    self.id = id ?? label
  }
}

/**
 A path, one tappable segment at a time. Ported from `FilesView`'s `.crumbs`.

 The last segment is where you already are, so it is ink-coloured and inert;
 everything before it is muted and navigates. Separators are a mono slash in
 the dim step, not a chevron — this is a filesystem path and it should read
 like one.
 */
public struct Breadcrumbs: View {
  private let crumbs: [Crumb]
  private let separator: String
  private let onSelect: ((Crumb) -> Void)?

  public init(
    _ crumbs: [Crumb],
    separator: String = "/",
    onSelect: ((Crumb) -> Void)? = nil
  ) {
    self.crumbs = crumbs
    self.separator = separator
    self.onSelect = onSelect
  }

  public var body: some View {
    FlowLayout(spacing: 6, lineSpacing: 4) {
      ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, crumb in
        CrumbView(
          crumb: crumb,
          current: index == crumbs.count - 1,
          onSelect: onSelect
        )
        if index < crumbs.count - 1 {
          Separator(text: separator)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Path")
  }

  private struct CrumbView: View {
    let crumb: Crumb
    let current: Bool
    let onSelect: ((Crumb) -> Void)?

    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
      Group {
        if current || onSelect == nil {
          text.foregroundStyle(current ? palette.text : palette.textMuted)
        } else {
          Button { onSelect?(crumb) } label: {
            text
              .foregroundStyle(hovering ? palette.accent500 : palette.textMuted)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .onHover { hovering = $0 }
        }
      }
      .accessibilityAddTraits(current ? [.isSelected] : [])
    }

    private var text: some View {
      Text(crumb.label).mono(12).lineLimit(1)
    }
  }

  private struct Separator: View {
    let text: String
    @Environment(\.palette) private var palette

    var body: some View {
      Text(text).mono(12).foregroundStyle(palette.textDim).accessibilityHidden(true)
    }
  }
}

/// Wraps its children onto as many lines as it needs. Crumbs and chips both do
/// this in the CSS via `flex-wrap`, and SwiftUI has no stack that will.
public struct FlowLayout: Layout {
  private let spacing: CGFloat
  private let lineSpacing: CGFloat
  private let alignment: HorizontalAlignment

  public init(
    spacing: CGFloat = Space.s2,
    lineSpacing: CGFloat = Space.s2,
    alignment: HorizontalAlignment = .leading
  ) {
    self.spacing = spacing
    self.lineSpacing = lineSpacing
    self.alignment = alignment
  }

  public func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Void
  ) -> CGSize {
    let lines = layout(subviews: subviews, width: proposal.width ?? .infinity)
    let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, lines.count - 1))
    let width = lines.map(\.width).max() ?? 0
    return CGSize(width: proposal.width ?? width, height: height)
  }

  public func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Void
  ) {
    let lines = layout(subviews: subviews, width: bounds.width)
    var y = bounds.minY
    for line in lines {
      var x = bounds.minX
      switch alignment {
      case .center: x += (bounds.width - line.width) / 2
      case .trailing: x += bounds.width - line.width
      default: break
      }
      for item in line.items {
        subviews[item.index].place(
          at: CGPoint(x: x, y: y + (line.height - item.size.height) / 2),
          proposal: ProposedViewSize(item.size)
        )
        x += item.size.width + spacing
      }
      y += line.height + lineSpacing
    }
  }

  private struct Item {
    let index: Int
    let size: CGSize
  }

  private struct Line {
    var items: [Item] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func layout(subviews: Subviews, width: CGFloat) -> [Line] {
    var lines: [Line] = []
    var line = Line()

    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let advance = line.items.isEmpty ? size.width : line.width + spacing + size.width
      if !line.items.isEmpty, advance > width {
        lines.append(line)
        line = Line()
      }
      line.width = line.items.isEmpty ? size.width : line.width + spacing + size.width
      line.height = max(line.height, size.height)
      line.items.append(Item(index: index, size: size))
    }

    if !line.items.isEmpty { lines.append(line) }
    return lines
  }
}
