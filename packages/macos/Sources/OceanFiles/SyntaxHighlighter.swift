import Foundation

public enum TokenKind: String, Sendable, Codable, Hashable {
  case keyword
  case string
  case comment
  case function
  case number
  case plain
}

public struct Token: Sendable, Hashable, Codable {
  public let text: String
  public let kind: TokenKind

  public init(text: String, kind: TokenKind) {
    self.text = text
    self.kind = kind
  }
}

public enum SyntaxHighlighter {
  public static func fileExtension(_ filename: String) -> String {
    let name = filename.split(separator: "/").last.map(String.init) ?? filename
    guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
    return String(name[name.index(after: dot)...]).lowercased()
  }

  public static func languageFor(_ filename: String) -> String {
    let ext = fileExtension(filename)
    let languages: [String: String] = [
      "ts": "typescript", "tsx": "typescript", "mts": "typescript",
      "js": "javascript", "jsx": "javascript", "mjs": "javascript", "cjs": "javascript",
      "vue": "vue", "json": "json", "jsonc": "json",
      "md": "markdown", "mdx": "markdown",
      "css": "css", "scss": "css",
      "html": "html", "xml": "html", "svg": "html",
      "py": "python", "go": "go", "rs": "rust", "rb": "ruby",
      "sh": "shell", "bash": "shell", "zsh": "shell",
      "yaml": "yaml", "yml": "yaml", "toml": "toml", "sql": "sql"
    ]
    return languages[ext] ?? "text"
  }

  public static func isBinary(_ filename: String) -> Bool {
    let binaryExts: Set<String> = [
      "png", "jpg", "jpeg", "gif", "webp", "ico", "pdf", "woff", "woff2",
      "ttf", "otf", "zip", "tar", "gz", "mp4", "mov", "mp3", "wav", "lockb",
      "so", "dylib", "dll", "exe", "wasm"
    ]
    return binaryExts.contains(fileExtension(filename))
  }

  public static func tokenize(_ source: String, language: String) -> [[Token]] {
    let lines = source.components(separatedBy: .newlines)
    if source.count > 400_000 || lines.count > 4_000 {
      return lines.map { [Token(text: $0, kind: .plain)] }
    }

    let lang = resolveAlias(language)
    if lang == "markdown" {
      return scanMarkdown(lines)
    }
    if lang == "html" {
      return scanHtml(lines)
    }

    guard let spec = specs[lang] else {
      return lines.map { [Token(text: $0, kind: .plain)] }
    }
    return scanWithSpec(lines, spec)
  }

  // MARK: - Internal Specs

  private struct LanguageSpec {
    let keywords: Set<String>
    let lineComments: [String]
    let blockComment: (open: String, close: String)?
    let quotes: [String]
    let multilineQuotes: [String]?
    let rawQuotes: [String]?
    let identStartExtra: String?
    let identPartExtra: String?
    let callFunctions: Bool
    let keyBeforeColon: Bool
    let keyBeforeEquals: Bool
    let stringKeys: Bool
    let dollarVars: Bool
    let foldKeywordCase: Bool

    init(
      keywords: Set<String>,
      lineComments: [String] = [],
      blockComment: (open: String, close: String)? = nil,
      quotes: [String] = ["\"", "'"],
      multilineQuotes: [String]? = nil,
      rawQuotes: [String]? = nil,
      identStartExtra: String? = nil,
      identPartExtra: String? = nil,
      callFunctions: Bool = false,
      keyBeforeColon: Bool = false,
      keyBeforeEquals: Bool = false,
      stringKeys: Bool = false,
      dollarVars: Bool = false,
      foldKeywordCase: Bool = false
    ) {
      self.keywords = keywords
      self.lineComments = lineComments
      self.blockComment = blockComment
      self.quotes = quotes
      self.multilineQuotes = multilineQuotes
      self.rawQuotes = rawQuotes
      self.identStartExtra = identStartExtra
      self.identPartExtra = identPartExtra
      self.callFunctions = callFunctions
      self.keyBeforeColon = keyBeforeColon
      self.keyBeforeEquals = keyBeforeEquals
      self.stringKeys = stringKeys
      self.dollarVars = dollarVars
      self.foldKeywordCase = foldKeywordCase
    }
  }

  private static func words(_ str: String) -> Set<String> {
    Set(str.split(whereSeparator: \.isWhitespace).map(String.init))
  }

  private static let jsKeywords = words("""
    const let var function return if else for while do switch case break continue new class extends
    implements interface type enum import export from as async await try catch finally throw typeof
    instanceof in of this super null undefined true false void delete yield static public private
    protected readonly abstract declare namespace satisfies keyof infer never unknown any string
    number boolean object symbol bigint default get set debugger constructor
  """)

  private static let specs: [String: LanguageSpec] = [
    "typescript": LanguageSpec(
      keywords: jsKeywords,
      lineComments: ["//"],
      blockComment: ("/*", "*/"),
      quotes: ["\"", "'"],
      multilineQuotes: ["`"],
      callFunctions: true
    ),
    "json": LanguageSpec(
      keywords: words("true false null"),
      lineComments: ["//"],
      blockComment: ("/*", "*/"),
      quotes: ["\""],
      stringKeys: true
    ),
    "css": LanguageSpec(
      keywords: words("""
        important inherit initial unset none auto var calc from to and not only
        @media @import @supports @keyframes @font-face @charset @layer @container @page
      """),
      lineComments: [],
      blockComment: ("/*", "*/"),
      quotes: ["\"", "'"],
      identStartExtra: "@-",
      identPartExtra: "-",
      callFunctions: true,
      keyBeforeColon: true
    ),
    "python": LanguageSpec(
      keywords: words("""
        def class return yield lambda import from as if elif else for while break continue pass
        try except finally raise with global nonlocal assert del in is not and or None True False
        async await self match case print len range int str float bool list dict set tuple
      """),
      lineComments: ["#"],
      quotes: ["\"", "'"],
      multilineQuotes: ["\"\"\"", "'''"],
      callFunctions: true
    ),
    "go": LanguageSpec(
      keywords: words("""
        package import func var const type struct interface map chan go defer if else for range
        return switch case default break continue fallthrough select nil true false make new len
        cap append copy delete panic recover string int int8 int16 int32 int64 uint uint8 uint32
        uint64 float32 float64 bool byte rune error any
      """),
      lineComments: ["//"],
      blockComment: ("/*", "*/"),
      quotes: ["\"", "'"],
      multilineQuotes: ["`"],
      rawQuotes: ["`"],
      callFunctions: true
    ),
    "rust": LanguageSpec(
      keywords: words("""
        fn let mut const static struct enum impl trait pub use mod match if else for while loop
        return break continue as ref where type dyn move async await unsafe crate super extern
        self Self in true false Some None Ok Err i8 i16 i32 i64 u8 u16 u32 u64 usize isize f32 f64
        bool char str String Vec Option Result Box
      """),
      lineComments: ["//"],
      blockComment: ("/*", "*/"),
      quotes: ["\""],
      callFunctions: true
    ),
    "ruby": LanguageSpec(
      keywords: words("""
        def end class module if elsif else unless while until for do then return yield require
        require_relative include extend attr_accessor attr_reader attr_writer begin rescue ensure
        raise self nil true false and or not in case when next break redo retry lambda proc new
        puts print module_function private public protected
      """),
      lineComments: ["#"],
      quotes: ["\"", "'"],
      identPartExtra: "?!",
      callFunctions: true
    ),
    "shell": LanguageSpec(
      keywords: words("""
        if then else elif fi for while until do done case esac function return export local
        readonly source alias unset declare set trap shift in exit echo cd test
      """),
      lineComments: ["#"],
      quotes: ["\"", "'"],
      rawQuotes: ["'"],
      dollarVars: true
    ),
    "yaml": LanguageSpec(
      keywords: words("true false null yes no on off ~"),
      lineComments: ["#"],
      quotes: ["\"", "'"],
      identPartExtra: "-.",
      keyBeforeColon: true
    ),
    "toml": LanguageSpec(
      keywords: words("true false"),
      lineComments: ["#"],
      quotes: ["\"", "'"],
      multilineQuotes: ["\"\"\"", "'''"],
      identPartExtra: "-.",
      keyBeforeEquals: true
    ),
    "sql": LanguageSpec(
      keywords: words("""
        select from where insert into values update set delete create table alter drop index view
        join inner left right outer full on group by order having limit offset distinct as and or
        not null is in between like exists union all case when then else end primary key foreign
        references default constraint unique check cascade returning with recursive begin commit
        rollback transaction int integer text varchar boolean timestamp date serial uuid jsonb
      """),
      lineComments: ["--"],
      blockComment: ("/*", "*/"),
      quotes: ["'", "\""],
      callFunctions: true,
      foldKeywordCase: true
    )
  ]

  private static func resolveAlias(_ language: String) -> String {
    let aliases: [String: String] = [
      "javascript": "typescript",
      "jsonc": "json",
      "scss": "css",
      "xml": "html",
      "svg": "html",
      "vue": "html"
    ]
    return aliases[language] ?? language
  }

  // MARK: - Generic Spec Scanner

  private enum Carry {
    case comment
    case string(close: String, escapes: Bool)
  }

  private static func scanWithSpec(_ lines: [String], _ spec: LanguageSpec) -> [[Token]] {
    var carry: Carry? = nil
    var result: [[Token]] = []
    for line in lines {
      let (tokens, nextCarry) = scanLine(line, spec, carry)
      result.append(tokens)
      carry = nextCarry
    }
    return result
  }

  private static func scanLine(_ line: String, _ spec: LanguageSpec, _ initialCarry: Carry?) -> ([Token], Carry?) {
    if initialCarry == nil && line.count > 2_000 {
      return (line.isEmpty ? [] : [Token(text: line, kind: .plain)], nil)
    }

    var tokens: [Token] = []
    var plainFrom = line.startIndex
    var i = line.startIndex
    var carry = initialCarry

    func push(_ kind: TokenKind, _ text: String) {
      guard !text.isEmpty else { return }
      tokens.append(Token(text: text, kind: kind))
    }

    func flushPlain(upto: String.Index) {
      if upto > plainFrom {
        push(.plain, String(line[plainFrom..<upto]))
      }
    }

    if case .comment = carry {
      if let close = spec.blockComment?.close, let range = line.range(of: close) {
        let end = range.upperBound
        push(.comment, String(line[line.startIndex..<end]))
        i = end
        plainFrom = end
        carry = nil
      } else {
        return (line.isEmpty ? [] : [Token(text: line, kind: .comment)], carry)
      }
    } else if case .string(let close, let escapes) = carry {
      let (endIndex, done) = consumeString(line, from: line.startIndex, close: close, escapes: escapes)
      push(.string, String(line[line.startIndex..<endIndex]))
      if !done {
        return (tokens, carry)
      }
      i = endIndex
      plainFrom = endIndex
      carry = nil
    }

    while i < line.endIndex {
      let rest = line[i...]

      // 1. Line comment
      var matchedLineComment = false
      for marker in spec.lineComments {
        if rest.hasPrefix(marker) {
          flushPlain(upto: i)
          push(.comment, String(rest))
          i = line.endIndex
          plainFrom = i
          matchedLineComment = true
          break
        }
      }
      if matchedLineComment { break }

      // 2. Block comment
      if let (open, close) = spec.blockComment, rest.hasPrefix(open) {
        flushPlain(upto: i)
        let searchStart = line.index(i, offsetBy: open.count, limitedBy: line.endIndex) ?? line.endIndex
        if let closeRange = line.range(of: close, range: searchStart..<line.endIndex) {
          let end = closeRange.upperBound
          push(.comment, String(line[i..<end]))
          i = end
          plainFrom = end
          continue
        } else {
          push(.comment, String(rest))
          return (tokens, .comment)
        }
      }

      // 3. Multi-line string
      if let multilineQuotes = spec.multilineQuotes {
        var matchedMulti: String? = nil
        for q in multilineQuotes where rest.hasPrefix(q) {
          matchedMulti = q
          break
        }
        if let multi = matchedMulti {
          flushPlain(upto: i)
          let escapes = !(spec.rawQuotes?.contains(multi) ?? false)
          let startIdx = line.index(i, offsetBy: multi.count, limitedBy: line.endIndex) ?? line.endIndex
          let (endIdx, done) = consumeString(line, from: startIdx, close: multi, escapes: escapes)
          push(.string, String(line[i..<endIdx]))
          if !done {
            return (tokens, .string(close: multi, escapes: escapes))
          }
          i = endIdx
          plainFrom = endIdx
          continue
        }
      }

      // 4. Single-line string
      var matchedQuote: String? = nil
      for q in spec.quotes where rest.hasPrefix(q) {
        matchedQuote = q
        break
      }
      if let quote = matchedQuote {
        flushPlain(upto: i)
        let escapes = !(spec.rawQuotes?.contains(quote) ?? false)
        let startIdx = line.index(i, offsetBy: quote.count, limitedBy: line.endIndex) ?? line.endIndex
        let (endIdx, done) = consumeString(line, from: startIdx, close: quote, escapes: escapes)
        let text = String(line[i..<endIdx])
        let isKey = spec.stringKeys && done && nextMeaningfulChar(line, from: endIdx) == ":"
        push(isKey ? .function : .string, text)
        i = endIdx
        plainFrom = endIdx
        continue
      }

      // 5. Dollar vars (shell)
      if spec.dollarVars && line[i] == "$" {
        let endIdx = consumeDollar(line, from: i)
        if line.distance(from: i, to: endIdx) > 1 {
          flushPlain(upto: i)
          push(.function, String(line[i..<endIdx]))
          i = endIdx
          plainFrom = endIdx
          continue
        }
      }

      // 6. Number
      let ch = line[i]
      if ch.isNumber && !isIdentPart(prevChar(line, before: i), spec: spec) {
        flushPlain(upto: i)
        let endIdx = consumeNumber(line, from: i)
        push(.number, String(line[i..<endIdx]))
        i = endIdx
        plainFrom = endIdx
        continue
      }

      // 7. Identifier
      if isIdentStart(ch, spec: spec) {
        var endIdx = line.index(after: i)
        while endIdx < line.endIndex && isIdentPart(line[endIdx], spec: spec) {
          endIdx = line.index(after: endIdx)
        }
        let word = String(line[i..<endIdx])
        let kind = classifyWord(word, line: line, endIdx: endIdx, startIdx: i, spec: spec)
        if kind != .plain {
          flushPlain(upto: i)
          push(kind, word)
          plainFrom = endIdx
        }
        i = endIdx
        continue
      }

      i = line.index(after: i)
    }

    flushPlain(upto: line.endIndex)
    return (tokens, nil)
  }

  private static func consumeString(_ line: String, from: String.Index, close: String, escapes: Bool) -> (end: String.Index, done: Bool) {
    var i = from
    while i < line.endIndex {
      if escapes && line[i] == "\\" {
        i = line.index(i, offsetBy: 2, limitedBy: line.endIndex) ?? line.endIndex
        continue
      }
      if line[i...].hasPrefix(close) {
        let end = line.index(i, offsetBy: close.count, limitedBy: line.endIndex) ?? line.endIndex
        return (end, true)
      }
      i = line.index(after: i)
    }
    return (line.endIndex, false)
  }

  private static func consumeDollar(_ line: String, from: String.Index) -> String.Index {
    var i = line.index(after: from)
    guard i < line.endIndex else { return i }
    if line[i] == "{" {
      if let range = line.range(of: "}", range: i..<line.endIndex) {
        return range.upperBound
      }
      return line.endIndex
    }
    while i < line.endIndex && (line[i].isLetter || line[i].isNumber || line[i] == "_") {
      i = line.index(after: i)
    }
    return i
  }

  private static func consumeNumber(_ line: String, from: String.Index) -> String.Index {
    var i = from
    let rest = line[i...]
    if rest.hasPrefix("0x") || rest.hasPrefix("0X") || rest.hasPrefix("0b") {
      i = line.index(i, offsetBy: 2, limitedBy: line.endIndex) ?? line.endIndex
    }
    while i < line.endIndex && (line[i].isHexDigit || line[i] == "_") {
      i = line.index(after: i)
    }
    if i < line.endIndex && line[i] == "." {
      let next = line.index(after: i)
      if next < line.endIndex && line[next].isNumber {
        i = next
        while i < line.endIndex && (line[i].isNumber || line[i] == "_") {
          i = line.index(after: i)
        }
      }
    }
    while i < line.endIndex && (line[i].isLetter || line[i] == "%") {
      i = line.index(after: i)
    }
    return i
  }

  private static func isIdentStart(_ ch: Character, spec: LanguageSpec) -> Bool {
    if ch.isLetter || ch == "_" || ch == "$" { return true }
    if let extra = spec.identStartExtra, extra.contains(ch) { return true }
    return false
  }

  private static func isIdentPart(_ ch: Character?, spec: LanguageSpec) -> Bool {
    guard let ch = ch else { return false }
    if ch.isLetter || ch.isNumber || ch == "_" || ch == "$" { return true }
    if let extra = spec.identPartExtra, extra.contains(ch) { return true }
    return false
  }

  private static func prevChar(_ line: String, before index: String.Index) -> Character? {
    guard index > line.startIndex else { return nil }
    return line[line.index(before: index)]
  }

  private static func nextMeaningfulChar(_ line: String, from index: String.Index) -> Character? {
    var i = index
    while i < line.endIndex && (line[i] == " " || line[i] == "\t") {
      i = line.index(after: i)
    }
    return i < line.endIndex ? line[i] : nil
  }

  private static func classifyWord(_ word: String, line: String, endIdx: String.Index, startIdx: String.Index, spec: LanguageSpec) -> TokenKind {
    let lookup = spec.foldKeywordCase ? word.lowercased() : word
    if spec.keywords.contains(lookup) { return .keyword }

    let after = nextMeaningfulChar(line, from: endIdx)
    if spec.keyBeforeColon && after == ":" {
      return .keyword
    }
    if spec.keyBeforeEquals && after == "=" {
      let prefix = line[line.startIndex..<startIdx].trimmingCharacters(in: .whitespaces)
      if prefix.isEmpty { return .keyword }
    }
    if spec.callFunctions && after == "(" {
      return .function
    }
    return .plain
  }

  // MARK: - HTML Scanner

  private static func scanHtml(_ lines: [String]) -> [[Token]] {
    var inComment = false
    var inTag = false
    var result: [[Token]] = []

    for line in lines {
      var tokens: [Token] = []
      var plainFrom = line.startIndex
      var i = line.startIndex

      func push(_ kind: TokenKind, _ text: String) {
        guard !text.isEmpty else { return }
        tokens.append(Token(text: text, kind: kind))
      }

      func flushPlain(upto: String.Index) {
        if upto > plainFrom { push(.plain, String(line[plainFrom..<upto])) }
      }

      if line.count > 2_000 && !inComment && !inTag {
        result.append(line.isEmpty ? [] : [Token(text: line, kind: .plain)])
        continue
      }

      while i < line.endIndex {
        if inComment {
          if let range = line.range(of: "-->", range: i..<line.endIndex) {
            push(.comment, String(line[i..<range.upperBound]))
            i = range.upperBound
            plainFrom = i
            inComment = false
            continue
          } else {
            push(.comment, String(line[i...]))
            i = line.endIndex
            plainFrom = i
            break
          }
        }

        if inTag {
          let ch = line[i]
          if ch == ">" {
            i = line.index(after: i)
            inTag = false
            continue
          }
          if ch == "\"" || ch == "'" {
            flushPlain(upto: i)
            let quoteStr = String(ch)
            let startIdx = line.index(after: i)
            let (endIdx, _) = consumeString(line, from: startIdx, close: quoteStr, escapes: false)
            push(.string, String(line[i..<endIdx]))
            i = endIdx
            plainFrom = endIdx
            continue
          }
          if ch.isLetter || ch == "_" || ch == ":" {
            var endIdx = line.index(after: i)
            while endIdx < line.endIndex && (line[endIdx].isLetter || line[endIdx].isNumber || line[endIdx] == "_" || line[endIdx] == ":" || line[endIdx] == "." || line[endIdx] == "-") {
              endIdx = line.index(after: endIdx)
            }
            flushPlain(upto: i)
            push(.function, String(line[i..<endIdx]))
            i = endIdx
            plainFrom = endIdx
            continue
          }
          i = line.index(after: i)
          continue
        }

        if line[i...].hasPrefix("<!--") {
          flushPlain(upto: i)
          plainFrom = i
          inComment = true
          continue
        }

        if line[i] == "<" {
          var endIdx = line.index(after: i)
          if endIdx < line.endIndex && (line[endIdx] == "/" || line[endIdx] == "!") {
            endIdx = line.index(after: endIdx)
          }
          let nameStart = endIdx
          while endIdx < line.endIndex && (line[endIdx].isLetter || line[endIdx].isNumber || line[endIdx] == "_" || line[endIdx] == ":" || line[endIdx] == "." || line[endIdx] == "-") {
            endIdx = line.index(after: endIdx)
          }
          if endIdx > nameStart {
            flushPlain(upto: i)
            push(.keyword, String(line[i..<endIdx]))
            plainFrom = endIdx
            i = endIdx
            inTag = true
            continue
          }
        }

        i = line.index(after: i)
      }

      flushPlain(upto: line.endIndex)
      result.append(tokens)
    }

    return result
  }

  // MARK: - Markdown Scanner

  private static func scanMarkdown(_ lines: [String]) -> [[Token]] {
    var inFence = false
    var result: [[Token]] = []

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
        inFence = !inFence
        result.append([Token(text: line, kind: .keyword)])
        continue
      }
      if inFence || line.count > 2_000 {
        result.append(line.isEmpty ? [] : [Token(text: line, kind: .plain)])
        continue
      }
      if trimmed.hasPrefix("#") {
        result.append([Token(text: line, kind: .keyword)])
        continue
      }
      if trimmed.hasPrefix(">") {
        result.append([Token(text: line, kind: .comment)])
        continue
      }
      result.append(scanMarkdownInline(line))
    }
    return result
  }

  private static func scanMarkdownInline(_ line: String) -> [Token] {
    var tokens: [Token] = []
    var plainFrom = line.startIndex
    var i = line.startIndex

    func push(_ kind: TokenKind, _ text: String) {
      guard !text.isEmpty else { return }
      tokens.append(Token(text: text, kind: kind))
    }

    func flushPlain(upto: String.Index) {
      if upto > plainFrom { push(.plain, String(line[plainFrom..<upto])) }
    }

    while i < line.endIndex {
      let ch = line[i]
      if ch == "`" {
        let nextIdx = line.index(after: i)
        if let closeRange = line.range(of: "`", range: nextIdx..<line.endIndex) {
          let end = closeRange.upperBound
          flushPlain(upto: i)
          push(.string, String(line[i..<end]))
          i = end
          plainFrom = i
          continue
        }
      }
      if ch == "*" && line.index(after: i) < line.endIndex && line[line.index(after: i)] == "*" {
        let startSearch = line.index(i, offsetBy: 2)
        if let closeRange = line.range(of: "**", range: startSearch..<line.endIndex) {
          let end = closeRange.upperBound
          flushPlain(upto: i)
          push(.keyword, String(line[i..<end]))
          i = end
          plainFrom = i
          continue
        }
      }
      i = line.index(after: i)
    }

    flushPlain(upto: line.endIndex)
    return tokens
  }
}
