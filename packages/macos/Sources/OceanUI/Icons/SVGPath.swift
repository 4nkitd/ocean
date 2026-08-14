import CoreGraphics
import Foundation
import SwiftUI

/**
 A reader for the `d` attribute of an SVG path.

 The icon set is a straight port of `../mobile/src/components/ui/AppIcon.vue`,
 and the cheapest way to keep it a *port* rather than a re-drawing is to carry
 the same path strings across and read them here. Hand-transcribing 28 glyphs
 into `Path` calls would drift the first time someone fixes a curve upstream.

 Supports the subset the icon set actually uses — M L H V C S Q T A Z, absolute
 and relative — and stops at the first thing it cannot read rather than
 guessing.
 */
enum SVGPath {
  static func path(from d: String) -> Path {
    var parser = Parser(d)
    return parser.run()
  }
}

private struct Parser {
  private let s: [Character]
  private var i = 0
  private var path = Path()
  private var current = CGPoint.zero
  private var subpathStart = CGPoint.zero
  private var lastCubicControl: CGPoint?
  private var lastQuadControl: CGPoint?

  init(_ d: String) { s = Array(d) }

  mutating func run() -> Path {
    var command: Character = " "
    while true {
      skipSeparators()
      guard i < s.count else { break }
      if s[i].isLetter {
        command = s[i]
        i += 1
      }
      guard step(command, &command) else { break }
    }
    return path
  }

  /// Returns false when the command could not be completed, which ends parsing.
  private mutating func step(_ command: Character, _ next: inout Character) -> Bool {
    let relative = command.isLowercase
    switch command.lowercased().first ?? " " {
    case "m":
      guard let p = point(relative) else { return false }
      path.move(to: p)
      current = p
      subpathStart = p
      lastCubicControl = nil
      lastQuadControl = nil
      // A second coordinate pair after a moveto is a lineto, per the spec.
      next = relative ? "l" : "L"

    case "l":
      guard let p = point(relative) else { return false }
      path.addLine(to: p)
      current = p
      lastCubicControl = nil
      lastQuadControl = nil

    case "h":
      guard let x = number() else { return false }
      let p = CGPoint(x: relative ? current.x + x : x, y: current.y)
      path.addLine(to: p)
      current = p
      lastCubicControl = nil
      lastQuadControl = nil

    case "v":
      guard let y = number() else { return false }
      let p = CGPoint(x: current.x, y: relative ? current.y + y : y)
      path.addLine(to: p)
      current = p
      lastCubicControl = nil
      lastQuadControl = nil

    case "c":
      guard let c1 = point(relative), let c2 = point(relative), let p = point(relative) else {
        return false
      }
      path.addCurve(to: p, control1: c1, control2: c2)
      current = p
      lastCubicControl = c2
      lastQuadControl = nil

    case "s":
      guard let c2 = point(relative), let p = point(relative) else { return false }
      let c1 = reflect(lastCubicControl)
      path.addCurve(to: p, control1: c1, control2: c2)
      current = p
      lastCubicControl = c2
      lastQuadControl = nil

    case "q":
      guard let c = point(relative), let p = point(relative) else { return false }
      path.addQuadCurve(to: p, control: c)
      current = p
      lastQuadControl = c
      lastCubicControl = nil

    case "t":
      guard let p = point(relative) else { return false }
      let c = reflect(lastQuadControl)
      path.addQuadCurve(to: p, control: c)
      current = p
      lastQuadControl = c
      lastCubicControl = nil

    case "a":
      guard
        let rx = number(), let ry = number(), let rotation = number(),
        let largeArc = number(), let sweep = number(), let p = point(relative)
      else { return false }
      appendArc(
        to: p, rx: rx, ry: ry, rotation: rotation,
        largeArc: largeArc != 0, sweep: sweep != 0
      )
      current = p
      lastCubicControl = nil
      lastQuadControl = nil

    case "z":
      path.closeSubpath()
      current = subpathStart
      lastCubicControl = nil
      lastQuadControl = nil

    default:
      return false
    }
    return true
  }

  private func reflect(_ control: CGPoint?) -> CGPoint {
    guard let control else { return current }
    return CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
  }

  // MARK: arcs

  /// Endpoint parameterisation → centre parameterisation → cubics, as in the
  /// SVG implementation notes. Core Graphics has no elliptical-arc-to.
  private mutating func appendArc(
    to end: CGPoint, rx: CGFloat, ry: CGFloat, rotation: CGFloat,
    largeArc: Bool, sweep: Bool
  ) {
    let startPoint = current
    if startPoint == end { return }

    var rx = abs(rx)
    var ry = abs(ry)
    if rx == 0 || ry == 0 {
      path.addLine(to: end)
      return
    }

    let phi = rotation * .pi / 180
    let cosPhi = cos(phi)
    let sinPhi = sin(phi)

    let dx = (startPoint.x - end.x) / 2
    let dy = (startPoint.y - end.y) / 2
    let x1p = cosPhi * dx + sinPhi * dy
    let y1p = -sinPhi * dx + cosPhi * dy

    let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lambda > 1 {
      let scale = sqrt(lambda)
      rx *= scale
      ry *= scale
    }

    let numerator = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
    let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    let coefficient = (largeArc == sweep ? -1.0 : 1.0) * sqrt(denominator == 0 ? 0 : numerator / denominator)

    let cxp = coefficient * rx * y1p / ry
    let cyp = -coefficient * ry * x1p / rx
    let cx = cosPhi * cxp - sinPhi * cyp + (startPoint.x + end.x) / 2
    let cy = sinPhi * cxp + cosPhi * cyp + (startPoint.y + end.y) / 2

    let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    var delta = angle(
      (x1p - cxp) / rx, (y1p - cyp) / ry,
      (-x1p - cxp) / rx, (-y1p - cyp) / ry
    )
    if !sweep, delta > 0 { delta -= 2 * .pi }
    if sweep, delta < 0 { delta += 2 * .pi }

    let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
    let step = delta / CGFloat(segments)

    for index in 0..<segments {
      let a = theta1 + CGFloat(index) * step
      let b = a + step
      let alpha = 4.0 / 3.0 * tan((b - a) / 4)

      let p1 = ellipse(cx, cy, rx, ry, cosPhi, sinPhi, a)
      let p2 = ellipse(cx, cy, rx, ry, cosPhi, sinPhi, b)
      let d1 = ellipseDerivative(rx, ry, cosPhi, sinPhi, a)
      let d2 = ellipseDerivative(rx, ry, cosPhi, sinPhi, b)

      path.addCurve(
        to: p2,
        control1: CGPoint(x: p1.x + alpha * d1.x, y: p1.y + alpha * d1.y),
        control2: CGPoint(x: p2.x - alpha * d2.x, y: p2.y - alpha * d2.y)
      )
    }
  }

  private func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
    let dot = ux * vx + uy * vy
    let length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
    guard length > 0 else { return 0 }
    let sign: CGFloat = (ux * vy - uy * vx) < 0 ? -1 : 1
    return sign * acos(min(1, max(-1, dot / length)))
  }

  private func ellipse(
    _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat,
    _ cosPhi: CGFloat, _ sinPhi: CGFloat, _ theta: CGFloat
  ) -> CGPoint {
    CGPoint(
      x: cx + rx * cos(theta) * cosPhi - ry * sin(theta) * sinPhi,
      y: cy + rx * cos(theta) * sinPhi + ry * sin(theta) * cosPhi
    )
  }

  private func ellipseDerivative(
    _ rx: CGFloat, _ ry: CGFloat, _ cosPhi: CGFloat, _ sinPhi: CGFloat, _ theta: CGFloat
  ) -> CGPoint {
    CGPoint(
      x: -rx * sin(theta) * cosPhi - ry * cos(theta) * sinPhi,
      y: -rx * sin(theta) * sinPhi + ry * cos(theta) * cosPhi
    )
  }

  // MARK: scanning

  private mutating func skipSeparators() {
    while i < s.count, s[i] == "," || s[i].isWhitespace { i += 1 }
  }

  private mutating func point(_ relative: Bool) -> CGPoint? {
    guard let x = number(), let y = number() else { return nil }
    return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
  }

  private mutating func number() -> CGFloat? {
    skipSeparators()
    var j = i
    if j < s.count, s[j] == "+" || s[j] == "-" { j += 1 }
    var sawDigit = false
    while j < s.count, isDigit(s[j]) {
      j += 1
      sawDigit = true
    }
    if j < s.count, s[j] == "." {
      j += 1
      while j < s.count, isDigit(s[j]) {
        j += 1
        sawDigit = true
      }
    }
    if sawDigit, j < s.count, s[j] == "e" || s[j] == "E" {
      var k = j + 1
      if k < s.count, s[k] == "+" || s[k] == "-" { k += 1 }
      var sawExponent = false
      while k < s.count, isDigit(s[k]) {
        k += 1
        sawExponent = true
      }
      if sawExponent { j = k }
    }
    guard sawDigit, let value = Double(String(s[i..<j])) else { return nil }
    i = j
    return CGFloat(value)
  }

  private func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
}
