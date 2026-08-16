import Foundation
import OceanKit

public enum GitDiffParser {
  private static let hunkHeaderRegex = try! NSRegularExpression(pattern: "^@@ -(\\d+)(?:,\\d+)? \\+(\\d+)(?:,\\d+)? @@")

  public static func parseUnifiedDiffFiles(_ patch: String) -> [FileDiff] {
    guard !patch.isEmpty else { return [] }

    var files: [FileDiff] = []
    var currentFile: FileDiff? = nil
    var currentHunk: DiffHunk? = nil
    var oldNumber = 0
    var newNumber = 0

    let body = patch.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
    let lines = body.components(separatedBy: .newlines)

    for raw in lines {
      let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw

      if line.hasPrefix("diff --git") {
        let path = pathFromGitHeader(line)
        let file = FileDiff(path: path, hunks: [], added: 0, removed: 0)
        currentFile = file
        files.append(file)
        currentHunk = nil
        continue
      }

      if line.hasPrefix("+++ ") {
        let path = cleanPath(String(line.dropFirst(4)))
        if currentFile == nil {
          let file = FileDiff(path: path, hunks: [], added: 0, removed: 0)
          currentFile = file
          files.append(file)
        } else if !path.isEmpty && path != "/dev/null" {
          if let idx = files.indices.last {
            files[idx].path = path
            currentFile = files[idx]
          }
        }
        currentHunk = nil
        continue
      }

      if line.hasPrefix("--- ") {
        currentHunk = nil
        continue
      }

      if let match = firstRegexMatch(hunkHeaderRegex, in: line) {
        if currentFile == nil {
          let file = FileDiff(path: "", hunks: [], added: 0, removed: 0)
          currentFile = file
          files.append(file)
        }
        oldNumber = Int(match[1]) ?? 0
        newNumber = Int(match[2]) ?? 0

        let headerText: String
        if let closeRange = line.range(of: "@@", options: [], range: line.index(line.startIndex, offsetBy: 2)..<line.endIndex) {
          headerText = String(line[..<closeRange.upperBound])
        } else {
          headerText = line
        }

        currentHunk = DiffHunk(header: headerText, lines: [])
        if let idx = files.indices.last {
          files[idx].hunks.append(currentHunk!)
          currentFile = files[idx]
        }
        continue
      }

      guard currentFile != nil, let fileIdx = files.indices.last, !files[fileIdx].hunks.isEmpty else {
        continue
      }

      let hunkIdx = files[fileIdx].hunks.count - 1
      let marker = line.first.map(String.init) ?? ""

      if marker == "\\" {
        let diffLine = DiffLine(kind: .context, text: line, oldNumber: nil, newNumber: nil)
        files[fileIdx].hunks[hunkIdx].lines.append(diffLine)
        continue
      }

      if marker == "+" {
        let text = String(line.dropFirst())
        let diffLine = DiffLine(kind: .add, text: text, oldNumber: nil, newNumber: newNumber)
        files[fileIdx].hunks[hunkIdx].lines.append(diffLine)
        newNumber += 1
        files[fileIdx].added += 1
        continue
      }

      if marker == "-" {
        let text = String(line.dropFirst())
        let diffLine = DiffLine(kind: .del, text: text, oldNumber: oldNumber, newNumber: nil)
        files[fileIdx].hunks[hunkIdx].lines.append(diffLine)
        oldNumber += 1
        files[fileIdx].removed += 1
        continue
      }

      if marker == " " || line.isEmpty {
        let text = line.isEmpty ? "" : String(line.dropFirst())
        let diffLine = DiffLine(kind: .context, text: text, oldNumber: oldNumber, newNumber: newNumber)
        files[fileIdx].hunks[hunkIdx].lines.append(diffLine)
        oldNumber += 1
        newNumber += 1
        continue
      }

      currentHunk = nil
    }

    return files.filter { !$0.hunks.isEmpty || !$0.path.isEmpty }
  }

  public static func parseUnifiedDiff(_ patch: String, path: String = "") -> FileDiff {
    let files = parseUnifiedDiffFiles(patch)
    if files.isEmpty {
      return FileDiff(path: path, hunks: [], added: 0, removed: 0)
    }

    if !path.isEmpty {
      if let match = files.first(where: { samePath($0.path, path) }) {
        return FileDiff(path: path, hunks: match.hunks, added: match.added, removed: match.removed)
      }
    }
    let chosen = files[0]
    return FileDiff(path: path.isEmpty ? chosen.path : path, hunks: chosen.hunks, added: chosen.added, removed: chosen.removed)
  }

  public static func formatChangeCounts(_ added: Int?, _ removed: Int?) -> String {
    var parts: [String] = []
    if let added = added {
      parts.append("+\(added)")
    }
    if let removed = removed {
      parts.append("−\(removed)")
    }
    return parts.joined(separator: " ")
  }

  public static func formatHunkCount(_ count: Int) -> String {
    return "\(count) \(count == 1 ? "hunk" : "hunks")"
  }

  // MARK: - Internals

  private static func pathFromGitHeader(_ line: String) -> String {
    let components = line.components(separatedBy: " ")
    guard let last = components.last else { return "" }
    return cleanPath(last)
  }

  private static func cleanPath(_ value: String) -> String {
    let clean = value.components(separatedBy: "\t")[0].trimmingCharacters(in: .whitespaces)
    if clean.hasPrefix("a/") || clean.hasPrefix("b/") {
      return String(clean.dropFirst(2))
    }
    return clean
  }

  private static func samePath(_ a: String, _ b: String) -> Bool {
    if a.isEmpty || b.isEmpty { return false }
    if a == b { return true }
    return a.hasSuffix("/" + b) || b.hasSuffix("/" + a)
  }

  private static func firstRegexMatch(_ regex: NSRegularExpression, in text: String) -> [String]? {
    let nsText = text as NSString
    guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) else {
      return nil
    }
    var results: [String] = []
    for i in 0..<match.numberOfRanges {
      results.append(nsText.substring(with: match.range(at: i)))
    }
    return results
  }
}
