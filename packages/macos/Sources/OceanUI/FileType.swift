import Foundation

/**
 File-type badges, ported from `../mobile/src/lib/filetype.ts`.

 The design gives every file a small square badge carrying a 2–3 character type
 code, tinted by how prominent that type is: source files take the accent, data
 and config a neutral fill, and noise (lockfiles, binaries) the dimmest step.
 That ranking is the point — it is what makes a long tree skimmable.

 Only the badge half of the Vue module is here. `languageFor` and `isBinary`
 belong to the file viewer, not to a UI primitive, so they live wherever
 OceanFiles wants them.
 */
public enum FileTypeTone: Sendable {
  case accent
  case accentSoft
  case neutral
  case dim
}

public struct FileTypeBadge: Sendable, Equatable {
  public let code: String
  public let tone: FileTypeTone

  public init(code: String, tone: FileTypeTone) {
    self.code = code
    self.tone = tone
  }
}

public enum FileType {
  /// Extension → badge. Order within a tone doesn't matter; membership does.
  private static let badges: [String: FileTypeBadge] = [
    "ts": FileTypeBadge(code: "TS", tone: .accent),
    "tsx": FileTypeBadge(code: "TSX", tone: .accent),
    "js": FileTypeBadge(code: "JS", tone: .accent),
    "jsx": FileTypeBadge(code: "JSX", tone: .accent),
    "mjs": FileTypeBadge(code: "JS", tone: .accent),
    "cjs": FileTypeBadge(code: "JS", tone: .accent),
    "vue": FileTypeBadge(code: "VUE", tone: .accent),
    "svelte": FileTypeBadge(code: "SVX", tone: .accent),
    "go": FileTypeBadge(code: "GO", tone: .accent),
    "rs": FileTypeBadge(code: "RS", tone: .accent),
    "py": FileTypeBadge(code: "PY", tone: .accent),
    "rb": FileTypeBadge(code: "RB", tone: .accent),
    "java": FileTypeBadge(code: "JAV", tone: .accent),
    "kt": FileTypeBadge(code: "KT", tone: .accent),
    "swift": FileTypeBadge(code: "SWF", tone: .accent),
    "c": FileTypeBadge(code: "C", tone: .accent),
    "h": FileTypeBadge(code: "H", tone: .accent),
    "cpp": FileTypeBadge(code: "CPP", tone: .accent),
    "php": FileTypeBadge(code: "PHP", tone: .accent),

    "json": FileTypeBadge(code: "{ }", tone: .accentSoft),
    "jsonc": FileTypeBadge(code: "{ }", tone: .accentSoft),
    "yaml": FileTypeBadge(code: "YML", tone: .accentSoft),
    "yml": FileTypeBadge(code: "YML", tone: .accentSoft),
    "toml": FileTypeBadge(code: "TML", tone: .accentSoft),

    "md": FileTypeBadge(code: "MD", tone: .neutral),
    "mdx": FileTypeBadge(code: "MDX", tone: .neutral),
    "html": FileTypeBadge(code: "HTM", tone: .neutral),
    "css": FileTypeBadge(code: "CSS", tone: .neutral),
    "scss": FileTypeBadge(code: "SCS", tone: .neutral),
    "sh": FileTypeBadge(code: "SH", tone: .neutral),
    "bash": FileTypeBadge(code: "SH", tone: .neutral),
    "zsh": FileTypeBadge(code: "SH", tone: .neutral),
    "sql": FileTypeBadge(code: "SQL", tone: .neutral),
    "xml": FileTypeBadge(code: "XML", tone: .neutral),
    "svg": FileTypeBadge(code: "SVG", tone: .neutral),

    "txt": FileTypeBadge(code: "TXT", tone: .dim),
    "log": FileTypeBadge(code: "LOG", tone: .dim),
    "lock": FileTypeBadge(code: "LK", tone: .dim),
    "lockb": FileTypeBadge(code: "LK", tone: .dim),
    "env": FileTypeBadge(code: "EN", tone: .dim),
    "png": FileTypeBadge(code: "IMG", tone: .dim),
    "jpg": FileTypeBadge(code: "IMG", tone: .dim),
    "jpeg": FileTypeBadge(code: "IMG", tone: .dim),
    "gif": FileTypeBadge(code: "IMG", tone: .dim),
    "webp": FileTypeBadge(code: "IMG", tone: .dim),
    "ico": FileTypeBadge(code: "IMG", tone: .dim),
    "pdf": FileTypeBadge(code: "PDF", tone: .dim),
    "woff": FileTypeBadge(code: "FNT", tone: .dim),
    "woff2": FileTypeBadge(code: "FNT", tone: .dim),
  ]

  /// Files whose whole name, not extension, decides the badge.
  private static let byName: [String: FileTypeBadge] = [
    "package.json": FileTypeBadge(code: "{ }", tone: .accentSoft),
    "tsconfig.json": FileTypeBadge(code: "TS", tone: .accent),
    "dockerfile": FileTypeBadge(code: "DK", tone: .neutral),
    "makefile": FileTypeBadge(code: "MK", tone: .neutral),
    ".gitignore": FileTypeBadge(code: "GIT", tone: .dim),
    "bun.lockb": FileTypeBadge(code: "LK", tone: .dim),
    "package-lock.json": FileTypeBadge(code: "LK", tone: .dim),
  ]

  public static func fileExtension(_ filename: String) -> String {
    let name = filename.split(separator: "/").last.map(String.init) ?? filename
    guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
    return String(name[name.index(after: dot)...]).lowercased()
  }

  public static func badge(for filename: String) -> FileTypeBadge {
    let name = (filename.split(separator: "/").last.map(String.init) ?? filename).lowercased()
    if let byName = byName[name] { return byName }
    if let byExtension = badges[fileExtension(name)] { return byExtension }

    // Dotfiles with no extension: `.env.local` reads as `EN`.
    if name.hasPrefix(".") {
      let stem = name.dropFirst().split(separator: ".").first.map(String.init) ?? ""
      let code = String(stem.prefix(2)).uppercased()
      return FileTypeBadge(code: code.isEmpty ? "··" : code, tone: .dim)
    }

    let code = String(fileExtension(name).prefix(3)).uppercased()
    return FileTypeBadge(code: code.isEmpty ? "··" : code, tone: .dim)
  }
}
