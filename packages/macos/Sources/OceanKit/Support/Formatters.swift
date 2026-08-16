import Foundation

public enum Formatters {
  /// Collapses a full path using `~` for home directory if applicable.
  public static func displayPath(_ path: String, home: String? = nil) -> String {
    guard !path.isEmpty else { return "" }
    if let home = home, !home.isEmpty, path.hasPrefix(home) {
      return "~" + path.dropFirst(home.count)
    }
    // Fallback: check standard macOS / Linux home paths if no home provided
    if path.hasPrefix("/Users/") {
      let parts = path.split(separator: "/", omittingEmptySubsequences: false)
      if parts.count >= 3 {
        let userHome = "/Users/\(parts[2])"
        return "~" + path.dropFirst(userHome.count)
      }
    } else if path.hasPrefix("/home/") {
      let parts = path.split(separator: "/", omittingEmptySubsequences: false)
      if parts.count >= 3 {
        let userHome = "/home/\(parts[2])"
        return "~" + path.dropFirst(userHome.count)
      }
    }
    return path
  }

  /// Returns the last component of a path.
  public static func basename(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if trimmed.isEmpty { return "/" }
    return String(trimmed.split(separator: "/").last ?? "/")
  }

  /// Extracts 1 to 2 capital initials from a project name.
  public static func initials(_ name: String) -> String {
    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return "P" }

    let parts = clean.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
    if parts.count >= 2 {
      let first = parts[0].first?.uppercased() ?? ""
      let second = parts[1].first?.uppercased() ?? ""
      return first + second
    } else if clean.count >= 2 {
      let first = clean.prefix(1).uppercased()
      let second = clean.dropFirst().prefix(1).uppercased()
      return first + second
    } else {
      return clean.uppercased()
    }
  }

  /// Relative time string: "just now", "5m ago", "2h ago", "3d ago".
  public static func relativeTime(_ timestampMs: Int) -> String {
    guard timestampMs > 0 else { return "never" }
    let now = Date().timeIntervalSince1970 * 1000
    let diffSec = max(0, Int((now - Double(timestampMs)) / 1000))
    if diffSec < 45 {
      return "just now"
    } else if diffSec < 3600 {
      let mins = max(1, diffSec / 60)
      return "\(mins)m ago"
    } else if diffSec < 86400 {
      let hours = max(1, diffSec / 3600)
      return "\(hours)h ago"
    } else {
      let days = max(1, diffSec / 86400)
      return "\(days)d ago"
    }
  }

  /// Compact relative time string for cards: "just now", "5m", "2h", "3d".
  public static func shortRelativeTime(_ timestampMs: Int?) -> String? {
    guard let timestampMs = timestampMs, timestampMs > 0 else { return nil }
    let now = Date().timeIntervalSince1970 * 1000
    let diffSec = max(0, Int((now - Double(timestampMs)) / 1000))
    if diffSec < 45 {
      return "just now"
    } else if diffSec < 3600 {
      let mins = max(1, diffSec / 60)
      return "\(mins)m"
    } else if diffSec < 86400 {
      let hours = max(1, diffSec / 3600)
      return "\(hours)h"
    } else {
      let days = max(1, diffSec / 86400)
      return "\(days)d"
    }
  }

  /// Compact number formatter: 200000 -> "200k", 1500 -> "1.5k", 500 -> "500".
  public static func compactNumber(_ number: Int) -> String {
    let doubleVal = Double(number)
    if number >= 1_000_000 {
      let formatted = String(format: "%.1fm", doubleVal / 1_000_000)
      return formatted.hasSuffix(".0m") ? "\(number / 1_000_000)m" : formatted
    } else if number >= 1_000 {
      let formatted = String(format: "%.1fk", doubleVal / 1_000)
      return formatted.hasSuffix(".0k") ? "\(number / 1_000)k" : formatted
    } else {
      return "\(number)"
    }
  }
}
