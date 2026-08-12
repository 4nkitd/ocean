/**
 * A dependency-free syntax highlighter, sized for a phone.
 *
 * Why not a library: highlight.js and shiki are both larger than this whole
 * app, and neither produces the design's palette without a custom theme. The
 * design's theme is deliberately mono-red — keyword, string, function, comment,
 * number are the only distinctions it makes — so five token kinds is the entire
 * requirement, and five kinds can be recognised by one left-to-right scan.
 *
 * The scan never backtracks. Every branch either consumes at least one
 * character or falls through to `i++`, and the only string search used is
 * `indexOf` / `startsWith` at a fixed offset. There is no regular expression
 * applied to a whole line anywhere, which is what makes a 5,000-line file safe
 * to open on a phone: the cost is strictly linear in characters.
 */

export type TokenKind = "keyword" | "string" | "comment" | "function" | "number" | "plain"

export interface Token {
  text: string
  kind: TokenKind
}

/**
 * Highlighting a very large file buys nothing — the reader is skimming, and
 * tokenising 20k lines to paint them red costs more than the phone has to
 * spare. Past these limits the source is returned as plain tokens, which still
 * renders, still scrolls, and still shows line numbers.
 */
export const MAX_HIGHLIGHT_LINES = 4_000
const MAX_HIGHLIGHT_CHARS = 400_000
/** A single enormous line is usually minified output; nobody reads it coloured. */
const MAX_LINE_LENGTH = 2_000

// ── language descriptions ──────────────────────────────────────────────────

interface LanguageSpec {
  keywords: Set<string>
  lineComments: string[]
  blockComment?: [string, string]
  /** Delimiters that must close on the same line. */
  quotes: string[]
  /** Delimiters that may span lines (template literals, docstrings, raw strings). */
  multilineQuotes?: string[]
  /** Delimiters inside which a backslash is literal. */
  rawQuotes?: string[]
  /** Extra characters that may begin an identifier (`@` for CSS at-rules). */
  identStartExtra?: string
  /** Extra characters that may continue one (`-` for CSS custom properties). */
  identPartExtra?: string
  /** `name(` reads as a call. */
  callFunctions?: boolean
  /** `name:` followed by a space reads as a key — CSS properties, YAML keys. */
  keyBeforeColon?: boolean
  /** `name =` at the head of a line reads as a key — TOML. */
  keyBeforeEquals?: boolean
  /** `"name":` reads as a key rather than a value — JSON. */
  stringKeys?: boolean
  /** `$name` and `${name}` read as a reference — shell. */
  dollarVars?: boolean
  /** SQL is written in either case and means the same thing. */
  foldKeywordCase?: boolean
}

function words(list: string): Set<string> {
  return new Set(list.split(/\s+/).filter(Boolean))
}

const JS_KEYWORDS = words(`
  const let var function return if else for while do switch case break continue new class extends
  implements interface type enum import export from as async await try catch finally throw typeof
  instanceof in of this super null undefined true false void delete yield static public private
  protected readonly abstract declare namespace satisfies keyof infer never unknown any string
  number boolean object symbol bigint default get set debugger constructor
`)

const SPECS: Record<string, LanguageSpec> = {
  typescript: {
    keywords: JS_KEYWORDS,
    lineComments: ["//"],
    blockComment: ["/*", "*/"],
    quotes: ['"', "'"],
    multilineQuotes: ["`"],
    callFunctions: true,
  },
  json: {
    keywords: words("true false null"),
    lineComments: ["//"],
    blockComment: ["/*", "*/"],
    quotes: ['"'],
    stringKeys: true,
  },
  css: {
    keywords: words(`
      important inherit initial unset none auto var calc from to and not only
      @media @import @supports @keyframes @font-face @charset @layer @container @page
    `),
    lineComments: [],
    blockComment: ["/*", "*/"],
    quotes: ['"', "'"],
    identStartExtra: "@-",
    identPartExtra: "-",
    callFunctions: true,
    keyBeforeColon: true,
  },
  python: {
    keywords: words(`
      def class return yield lambda import from as if elif else for while break continue pass
      try except finally raise with global nonlocal assert del in is not and or None True False
      async await self match case print len range int str float bool list dict set tuple
    `),
    lineComments: ["#"],
    quotes: ['"', "'"],
    multilineQuotes: ['"""', "'''"],
    callFunctions: true,
  },
  go: {
    keywords: words(`
      package import func var const type struct interface map chan go defer if else for range
      return switch case default break continue fallthrough select nil true false make new len
      cap append copy delete panic recover string int int8 int16 int32 int64 uint uint8 uint32
      uint64 float32 float64 bool byte rune error any
    `),
    lineComments: ["//"],
    blockComment: ["/*", "*/"],
    quotes: ['"', "'"],
    multilineQuotes: ["`"],
    rawQuotes: ["`"],
    callFunctions: true,
  },
  rust: {
    keywords: words(`
      fn let mut const static struct enum impl trait pub use mod match if else for while loop
      return break continue as ref where type dyn move async await unsafe crate super extern
      self Self in true false Some None Ok Err i8 i16 i32 i64 u8 u16 u32 u64 usize isize f32 f64
      bool char str String Vec Option Result Box
    `),
    lineComments: ["//"],
    blockComment: ["/*", "*/"],
    quotes: ['"'],
    callFunctions: true,
  },
  ruby: {
    keywords: words(`
      def end class module if elsif else unless while until for do then return yield require
      require_relative include extend attr_accessor attr_reader attr_writer begin rescue ensure
      raise self nil true false and or not in case when next break redo retry lambda proc new
      puts print module_function private public protected
    `),
    lineComments: ["#"],
    quotes: ['"', "'"],
    identPartExtra: "?!",
    callFunctions: true,
  },
  shell: {
    keywords: words(`
      if then else elif fi for while until do done case esac function return export local
      readonly source alias unset declare set trap shift in exit echo cd test
    `),
    lineComments: ["#"],
    quotes: ['"', "'"],
    rawQuotes: ["'"],
    dollarVars: true,
  },
  yaml: {
    keywords: words("true false null yes no on off ~"),
    lineComments: ["#"],
    quotes: ['"', "'"],
    identPartExtra: "-.",
    keyBeforeColon: true,
  },
  toml: {
    keywords: words("true false"),
    lineComments: ["#"],
    quotes: ['"', "'"],
    multilineQuotes: ['"""', "'''"],
    identPartExtra: "-.",
    keyBeforeEquals: true,
  },
  sql: {
    keywords: words(`
      select from where insert into values update set delete create table alter drop index view
      join inner left right outer full on group by order having limit offset distinct as and or
      not null is in between like exists union all case when then else end primary key foreign
      references default constraint unique check cascade returning with recursive begin commit
      rollback transaction int integer text varchar boolean timestamp date serial uuid jsonb
    `),
    lineComments: ["--"],
    blockComment: ["/*", "*/"],
    quotes: ["'", '"'],
    callFunctions: true,
    foldKeywordCase: true,
  },
}

/** `languageFor()` returns these names; they share another language's rules. */
const ALIASES: Record<string, string> = {
  javascript: "typescript",
  jsonc: "json",
  scss: "css",
  xml: "html",
  svg: "html",
  vue: "html",
}

// ── entry point ────────────────────────────────────────────────────────────

/**
 * Tokenise `source` into one array of tokens per line. Concatenating a line's
 * `text` values reproduces the line exactly, which is what lets the renderer
 * bind them as text nodes — nothing here escapes anything, and nothing here is
 * ever handed to `v-html`.
 */
export function tokenize(source: string, language: string): Token[][] {
  const lines = source.split(/\r\n|\r|\n/)

  if (source.length > MAX_HIGHLIGHT_CHARS || lines.length > MAX_HIGHLIGHT_LINES) {
    return lines.map(plainLine)
  }

  const name = ALIASES[language] ?? language
  if (name === "markdown") return scanMarkdown(lines)
  if (name === "html") return scanHtml(lines)

  const spec = SPECS[name]
  if (!spec) return lines.map(plainLine)
  return scanWithSpec(lines, spec)
}

function plainLine(line: string): Token[] {
  return line ? [{ text: line, kind: "plain" }] : []
}

// ── the generic scanner ────────────────────────────────────────────────────

type Carry =
  | null
  | { kind: "comment" }
  | { kind: "string"; close: string; escapes: boolean }

function scanWithSpec(lines: string[], spec: LanguageSpec): Token[][] {
  let carry: Carry = null
  const out: Token[][] = []
  for (const line of lines) {
    const result = scanLine(line, spec, carry)
    out.push(result.tokens)
    carry = result.carry
  }
  return out
}

function scanLine(line: string, spec: LanguageSpec, carry: Carry): { tokens: Token[]; carry: Carry } {
  // The length guard is skipped mid-construct, because bailing out there would
  // lose track of where the comment or string ends.
  if (!carry && line.length > MAX_LINE_LENGTH) return { tokens: plainLine(line), carry: null }

  const tokens: Token[] = []
  let plainFrom = 0
  let i = 0

  const push = (kind: TokenKind, text: string) => {
    if (text) tokens.push({ text, kind })
  }
  const flushPlain = (upto: number) => {
    if (upto > plainFrom) push("plain", line.slice(plainFrom, upto))
  }

  if (carry?.kind === "comment") {
    const close = spec.blockComment![1]
    const end = line.indexOf(close)
    if (end === -1) return { tokens: line ? [{ text: line, kind: "comment" }] : [], carry }
    push("comment", line.slice(0, end + close.length))
    i = end + close.length
    plainFrom = i
    carry = null
  } else if (carry?.kind === "string") {
    const closed = consumeString(line, 0, carry.close, carry.escapes)
    push("string", line.slice(0, closed.end))
    if (!closed.done) return { tokens, carry }
    i = closed.end
    plainFrom = i
    carry = null
  }

  while (i < line.length) {
    const ch = line[i]!

    // 1. line comment — runs to the end, so nothing after it needs scanning.
    let matchedLineComment = false
    for (const marker of spec.lineComments) {
      if (line.startsWith(marker, i)) {
        flushPlain(i)
        push("comment", line.slice(i))
        i = line.length
        plainFrom = i
        matchedLineComment = true
        break
      }
    }
    if (matchedLineComment) break

    // 2. block comment.
    if (spec.blockComment && line.startsWith(spec.blockComment[0], i)) {
      flushPlain(i)
      const [open, close] = spec.blockComment
      const end = line.indexOf(close, i + open.length)
      if (end === -1) {
        push("comment", line.slice(i))
        return { tokens, carry: { kind: "comment" } }
      }
      push("comment", line.slice(i, end + close.length))
      i = end + close.length
      plainFrom = i
      continue
    }

    // 3. multi-line string delimiters are checked first: `"""` also matches `"`.
    const multi = spec.multilineQuotes?.find((q) => line.startsWith(q, i))
    if (multi) {
      flushPlain(i)
      const escapes = !spec.rawQuotes?.includes(multi)
      const closed = consumeString(line, i + multi.length, multi, escapes)
      push("string", line.slice(i, closed.end))
      if (!closed.done) return { tokens, carry: { kind: "string", close: multi, escapes } }
      i = closed.end
      plainFrom = i
      continue
    }

    // 4. single-line string. An unterminated one ends at the newline rather
    //    than swallowing the rest of the file, which is what a real parser
    //    would report as an error and what a reader expects to see.
    const quote = spec.quotes.find((q) => line.startsWith(q, i))
    if (quote) {
      flushPlain(i)
      const escapes = !spec.rawQuotes?.includes(quote)
      const closed = consumeString(line, i + quote.length, quote, escapes)
      const text = line.slice(i, closed.end)
      const isKey = spec.stringKeys && closed.done && nextMeaningful(line, closed.end) === ":"
      push(isKey ? "function" : "string", text)
      i = closed.end
      plainFrom = i
      continue
    }

    // 5. shell variable reference.
    if (spec.dollarVars && ch === "$") {
      const end = consumeDollar(line, i)
      if (end > i + 1) {
        flushPlain(i)
        push("function", line.slice(i, end))
        i = end
        plainFrom = i
        continue
      }
    }

    // 6. number — but only where one can start, so `utf8` stays one identifier.
    if (ch >= "0" && ch <= "9" && !isIdentPart(line[i - 1] ?? "", spec)) {
      flushPlain(i)
      const end = consumeNumber(line, i)
      push("number", line.slice(i, end))
      i = end
      plainFrom = i
      continue
    }

    // 7. identifier.
    if (isIdentStart(ch, spec)) {
      let end = i + 1
      while (end < line.length && isIdentPart(line[end]!, spec)) end++
      const word = line.slice(i, end)
      const kind = classifyWord(word, line, end, i, spec)
      if (kind !== "plain") {
        flushPlain(i)
        push(kind, word)
        plainFrom = end
      }
      i = end
      continue
    }

    i++
  }

  flushPlain(line.length)
  return { tokens, carry: null }
}

function classifyWord(
  word: string,
  line: string,
  end: number,
  start: number,
  spec: LanguageSpec,
): TokenKind {
  const lookup = spec.foldKeywordCase ? word.toLowerCase() : word
  if (spec.keywords.has(lookup)) return "keyword"

  const after = nextMeaningful(line, end)

  // A key is a keyword: it names the shape, the value is the content.
  if (spec.keyBeforeColon && after === ":") {
    const following = line[skipSpaces(line, end) + 1] ?? " "
    if (following === " " || following === "" || following === "\t") return "keyword"
  }
  if (spec.keyBeforeEquals && after === "=" && line.slice(0, start).trim() === "") return "keyword"
  if (spec.callFunctions && after === "(") return "function"

  return "plain"
}

/** Index of the next non-space character, or `line.length`. */
function skipSpaces(line: string, from: number): number {
  let i = from
  while (i < line.length && (line[i] === " " || line[i] === "\t")) i++
  return i
}

function nextMeaningful(line: string, from: number): string {
  return line[skipSpaces(line, from)] ?? ""
}

/**
 * Walk to the closing delimiter. `from` is the first character *inside* the
 * string; the returned `end` is one past the closing delimiter, or the end of
 * the line when it never closes.
 */
function consumeString(
  line: string,
  from: number,
  close: string,
  escapes: boolean,
): { end: number; done: boolean } {
  let i = from
  while (i < line.length) {
    if (escapes && line[i] === "\\") {
      i += 2
      continue
    }
    if (line.startsWith(close, i)) return { end: i + close.length, done: true }
    i++
  }
  return { end: line.length, done: false }
}

function consumeDollar(line: string, from: number): number {
  let i = from + 1
  if (line[i] === "{") {
    const end = line.indexOf("}", i)
    return end === -1 ? line.length : end + 1
  }
  while (i < line.length && /[A-Za-z0-9_]/.test(line[i]!)) i++
  return i
}

function consumeNumber(line: string, from: number): number {
  let i = from
  if (line[i] === "0" && (line[i + 1] === "x" || line[i + 1] === "X" || line[i + 1] === "b")) i += 2
  while (i < line.length && /[0-9a-fA-F_]/.test(line[i]!)) i++
  if (line[i] === "." && /[0-9]/.test(line[i + 1] ?? "")) {
    i++
    while (i < line.length && /[0-9_]/.test(line[i]!)) i++
  }
  if ((line[i] === "e" || line[i] === "E") && /[0-9+-]/.test(line[i + 1] ?? "")) {
    i += 2
    while (i < line.length && /[0-9]/.test(line[i]!)) i++
  }
  // Suffixes and units: `12px`, `4rem`, `10n`, `1_000i64`, `50%`.
  while (i < line.length && /[A-Za-z%]/.test(line[i]!)) i++
  return i
}

function isIdentStart(ch: string, spec: LanguageSpec): boolean {
  if (!ch) return false
  return /[A-Za-z_$]/.test(ch) || (spec.identStartExtra?.includes(ch) ?? false)
}

function isIdentPart(ch: string, spec: LanguageSpec): boolean {
  if (!ch) return false
  return /[A-Za-z0-9_$]/.test(ch) || (spec.identPartExtra?.includes(ch) ?? false)
}

// ── markup, which needs its own state machine ──────────────────────────────

/**
 * HTML has two modes — text and "inside a tag" — and the mode survives a line
 * break, so it cannot reuse the generic scanner's carry.
 */
function scanHtml(lines: string[]): Token[][] {
  let inComment = false
  let inTag = false
  const out: Token[][] = []

  for (const line of lines) {
    const tokens: Token[] = []
    let plainFrom = 0
    let i = 0
    const push = (kind: TokenKind, text: string) => {
      if (text) tokens.push({ text, kind })
    }
    const flushPlain = (upto: number) => {
      if (upto > plainFrom) push("plain", line.slice(plainFrom, upto))
    }

    if (line.length > MAX_LINE_LENGTH && !inComment && !inTag) {
      out.push(plainLine(line))
      continue
    }

    while (i < line.length) {
      if (inComment) {
        const end = line.indexOf("-->", i)
        if (end === -1) {
          push("comment", line.slice(i))
          i = line.length
          plainFrom = i
          break
        }
        push("comment", line.slice(i, end + 3))
        i = end + 3
        plainFrom = i
        inComment = false
        continue
      }

      if (inTag) {
        const ch = line[i]!
        if (ch === ">") {
          // The bracket itself, and any `=` or whitespace before it, stay in
          // the plain run so the tokens still reassemble into the source line.
          i++
          inTag = false
          continue
        }
        if (ch === '"' || ch === "'") {
          flushPlain(i)
          const closed = consumeString(line, i + 1, ch, false)
          push("string", line.slice(i, closed.end))
          i = closed.end
          plainFrom = i
          continue
        }
        if (/[A-Za-z_:]/.test(ch)) {
          let end = i + 1
          while (end < line.length && /[A-Za-z0-9_:.-]/.test(line[end]!)) end++
          flushPlain(i)
          push("function", line.slice(i, end))
          i = end
          plainFrom = i
          continue
        }
        i++
        continue
      }

      if (line.startsWith("<!--", i)) {
        flushPlain(i)
        plainFrom = i
        inComment = true
        continue
      }
      if (line[i] === "<") {
        let end = i + 1
        if (line[end] === "/" || line[end] === "!") end++
        const nameStart = end
        while (end < line.length && /[A-Za-z0-9_:.-]/.test(line[end]!)) end++
        if (end > nameStart) {
          flushPlain(i)
          push("keyword", line.slice(i, end))
          plainFrom = end
          i = end
          inTag = true
          continue
        }
      }
      i++
    }

    flushPlain(line.length)
    out.push(tokens)
  }

  return out
}

/**
 * Markdown is line-oriented, so it is classified a line at a time. Only the
 * structures the design's palette can express are recognised: headings and
 * emphasis as keyword, code and links as string, quotes as comment.
 */
function scanMarkdown(lines: string[]): Token[][] {
  let inFence = false
  const out: Token[][] = []

  for (const line of lines) {
    const trimmed = line.trimStart()

    if (trimmed.startsWith("```") || trimmed.startsWith("~~~")) {
      inFence = !inFence
      out.push([{ text: line, kind: "keyword" }])
      continue
    }
    if (inFence || line.length > MAX_LINE_LENGTH) {
      out.push(plainLine(line))
      continue
    }
    if (trimmed.startsWith("#")) {
      out.push([{ text: line, kind: "keyword" }])
      continue
    }
    if (trimmed.startsWith(">")) {
      out.push([{ text: line, kind: "comment" }])
      continue
    }
    out.push(scanMarkdownInline(line))
  }

  return out
}

function scanMarkdownInline(line: string): Token[] {
  const tokens: Token[] = []
  let plainFrom = 0
  let i = 0
  const push = (kind: TokenKind, text: string) => {
    if (text) tokens.push({ text, kind })
  }
  const flushPlain = (upto: number) => {
    if (upto > plainFrom) push("plain", line.slice(plainFrom, upto))
  }

  while (i < line.length) {
    const ch = line[i]!

    if (ch === "`") {
      const end = line.indexOf("`", i + 1)
      if (end !== -1) {
        flushPlain(i)
        push("string", line.slice(i, end + 1))
        i = end + 1
        plainFrom = i
        continue
      }
    }
    if (ch === "*" && line[i + 1] === "*") {
      const end = line.indexOf("**", i + 2)
      if (end !== -1) {
        flushPlain(i)
        push("keyword", line.slice(i, end + 2))
        i = end + 2
        plainFrom = i
        continue
      }
    }
    if (ch === "(" && line[i - 1] === "]") {
      const end = line.indexOf(")", i + 1)
      if (end !== -1) {
        flushPlain(i)
        push("function", line.slice(i, end + 1))
        i = end + 1
        plainFrom = i
        continue
      }
    }
    i++
  }

  flushPlain(line.length)
  return tokens
}
