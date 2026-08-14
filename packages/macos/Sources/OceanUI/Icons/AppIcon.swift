import OceanKit
import SwiftUI

/**
 The icon set, ported from `../mobile/src/components/ui/AppIcon.vue`.

 Lucide geometry drawn as square-capped 2px strokes on a 24 grid. The names are
 the Vue names so the two clients read the same. Every glyph inherits the
 current foreground style, which is how the accent propagates into an active tab
 or a status row.
 */
public enum IconName: String, CaseIterable, Sendable {
  case arrowRight = "arrow-right"
  case arrowUp = "arrow-up"
  case mcp
  case arrowLeft = "arrow-left"
  case chevronDown = "chevron-down"
  case chevronRight = "chevron-right"
  case chevronUpDown = "chevron-up-down"
  case check
  case close
  case eye
  case eyeOff = "eye-off"
  case spinner
  case folder
  case search
  case filter
  case more
  case gitBranch = "git-branch"
  case chat
  case grid
  case plus
  case list
  case gear
  case history
  case refresh
  case upload
  case alert
  case terminal
  case mic
}

public struct AppIcon: View {
  public let name: IconName
  public let size: CGFloat
  /// Solid glyphs (an expanded folder) rather than outlined.
  public let filled: Bool

  public init(_ name: IconName, size: CGFloat = 16, filled: Bool = false) {
    self.name = name
    self.size = size
    self.filled = filled
  }

  public var body: some View {
    let geometry = IconGeometry.for(name)
    let scale = min(size / geometry.viewBox.width, size / geometry.viewBox.height)
    Group {
      if filled {
        IconShape(name: name).fill()
      } else {
        IconShape(name: name)
          .stroke(
            style: StrokeStyle(
              lineWidth: geometry.strokeWidth * scale,
              lineCap: geometry.lineCap,
              lineJoin: geometry.lineJoin
            )
          )
          .fill()
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

/// `AppIcon(.spinner)` turning at the CSS keyframe's 0.9s, and standing still
/// when the system asks for reduced motion — the CSS does the same.
public struct Spinner: View {
  public let size: CGFloat

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var turning = false

  public init(size: CGFloat = 18) {
    self.size = size
  }

  public var body: some View {
    AppIcon(.spinner, size: size)
      .rotationEffect(.degrees(turning ? 360 : 0))
      .animation(
        reduceMotion ? nil : .linear(duration: 0.9).repeatForever(autoreverses: false),
        value: turning
      )
      .onAppear { turning = true }
  }
}

struct IconShape: Shape {
  let name: IconName

  func path(in rect: CGRect) -> Path {
    let geometry = IconGeometry.for(name)
    let box = geometry.viewBox
    let scale = min(rect.width / box.width, rect.height / box.height)
    let transform = CGAffineTransform(
      translationX: rect.midX - scale * box.midX,
      y: rect.midY - scale * box.midY
    ).scaledBy(x: scale, y: scale)

    var path = Path()
    if !geometry.d.isEmpty {
      path.addPath(SVGPath.path(from: geometry.d))
    }
    for circle in geometry.circles {
      path.addEllipse(
        in: CGRect(
          x: circle.x - circle.r,
          y: circle.y - circle.r,
          width: circle.r * 2,
          height: circle.r * 2
        )
      )
    }
    for box in geometry.rects {
      path.addRect(box)
    }
    return path.applying(transform)
  }
}

struct IconCircle {
  let x: CGFloat
  let y: CGFloat
  let r: CGFloat
}

struct IconGeometry {
  var d: String = ""
  var circles: [IconCircle] = []
  var rects: [CGRect] = []
  var viewBox = CGRect(x: 0, y: 0, width: 24, height: 24)
  var strokeWidth: CGFloat = 2
  var lineCap: CGLineCap = .square
  var lineJoin: CGLineJoin = .miter

  static func `for`(_ name: IconName) -> IconGeometry {
    switch name {
    case .arrowRight:
      return IconGeometry(d: "M5 12h14M13 6l6 6-6 6")
    case .arrowUp:
      return IconGeometry(d: "M12 19V5M6 11l6-6 6 6")
    case .arrowLeft:
      return IconGeometry(d: "M19 12H5M11 6l-6 6 6 6")
    case .chevronDown:
      return IconGeometry(d: "M6 9l6 6 6-6")
    case .chevronRight:
      return IconGeometry(d: "M9 6l6 6-6 6")
    case .chevronUpDown:
      return IconGeometry(d: "M7 15l5 5 5-5M7 9l5-5 5 5")
    case .check:
      return IconGeometry(d: "M20 6L9 17l-5-5")
    case .close:
      return IconGeometry(d: "M18 6L6 18M6 6l12 12")
    case .eye:
      return IconGeometry(
        d: "M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12z",
        circles: [IconCircle(x: 12, y: 12, r: 3)]
      )
    case .eyeOff:
      return IconGeometry(
        d: "M17.9 17.9A10.7 10.7 0 0 1 12 19C5 19 1 12 1 12a19.6 19.6 0 0 1 5.1-5.9"
          + "M9.9 4.2A10.9 10.9 0 0 1 12 4c7 0 11 8 11 8a19.6 19.6 0 0 1-2.2 3.2"
          + "M9.9 9.9a3 3 0 1 0 4.2 4.2"
          + "M2 2l20 20"
      )
    case .spinner:
      return IconGeometry(
        d: "M12 2v4M12 18v4M4.9 4.9l2.9 2.9M16.2 16.2l2.9 2.9"
          + "M2 12h4M18 12h4M4.9 19.1l2.9-2.9M16.2 7.8l2.9-2.9"
      )
    case .folder:
      return IconGeometry(d: "M3 5h6l2 2h10v12H3z")
    case .search:
      return IconGeometry(d: "M20 20l-3.5-3.5", circles: [IconCircle(x: 11, y: 11, r: 7)])
    case .filter:
      return IconGeometry(d: "M3 6h18M3 12h12M3 18h6")
    case .more:
      return IconGeometry(circles: [
        IconCircle(x: 12, y: 5, r: 1),
        IconCircle(x: 12, y: 12, r: 1),
        IconCircle(x: 12, y: 19, r: 1),
      ])
    case .gitBranch:
      return IconGeometry(
        d: "M18 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM6 9v6M18 9v1a5 5 0 0 1-5 5H9",
        circles: [IconCircle(x: 6, y: 6, r: 3), IconCircle(x: 6, y: 18, r: 3)]
      )
    case .chat:
      return IconGeometry(d: "M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z")
    case .grid:
      return IconGeometry(rects: [
        CGRect(x: 3, y: 3, width: 7, height: 7),
        CGRect(x: 14, y: 3, width: 7, height: 7),
        CGRect(x: 3, y: 14, width: 7, height: 7),
        CGRect(x: 14, y: 14, width: 7, height: 7),
      ])
    case .plus:
      return IconGeometry(d: "M12 5v14M5 12h14")
    case .list:
      return IconGeometry(d: "M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01")
    case .gear:
      return IconGeometry(
        d: "M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M16.9 16.9l2.1 2.1"
          + "M4.9 19.1l2.1-2.1M16.9 7.1l2.1-2.1",
        circles: [IconCircle(x: 12, y: 12, r: 3)]
      )
    case .history:
      return IconGeometry(d: "M3 12a9 9 0 1 0 3-6.7L3 8M3 3v5h5M12 7v5l4 2")
    case .refresh:
      return IconGeometry(d: "M21 12a9 9 0 1 1-3-6.7L21 8M21 3v5h-5")
    case .upload:
      return IconGeometry(d: "M12 19V5M6 11l6-6 6 6M4 21h16")
    case .alert:
      return IconGeometry(d: "M12 3L2 20h20L12 3zM12 10v4M12 17v.5")
    case .terminal:
      return IconGeometry(d: "M4 6l6 6-6 6M13 18h7")
    case .mic:
      return IconGeometry(d: "M9 4h6v9H9zM5 11a7 7 0 0 0 14 0M12 18v3")
    case .mcp:
      // The Model Context Protocol mark, kept at the artwork's own 195 grid
      // rather than re-traced — the curves are the logo, and they need round
      // ends and a stroke scaled to that grid.
      return IconGeometry(
        d: "M25 97.8528L92.8823 29.9706C102.255 20.598 117.451 20.598 126.823 29.9706"
          + "C136.196 39.3431 136.196 54.5391 126.823 63.9117L75.5581 115.177"
          + "M76.2653 114.47L126.823 63.9117C136.196 54.5391 151.392 54.5391 160.765 63.9117"
          + "C170.491 73.6378 170.491 88.8338 161.118 98.2063L99.7248 159.6"
          + "C96.6006 162.724 96.6006 167.789 99.7248 170.913L112.331 183.52",
        viewBox: CGRect(x: 18, y: 15, width: 160, height: 178),
        strokeWidth: 15,
        lineCap: .round,
        lineJoin: .round
      )
    }
  }
}
