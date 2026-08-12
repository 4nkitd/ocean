/**
 * File-type badges.
 *
 * The design gives every file a small square badge carrying a 2–3 character
 * type code, tinted by how prominent that type is: source files take the accent,
 * data and config files a neutral fill, and noise (lockfiles, binaries) the
 * dimmest step. That ranking is the point — it's what makes a long tree
 * skimmable — so it lives here rather than being derived per screen.
 */

export type BadgeTone = "accent" | "accent-soft" | "neutral" | "dim"

export interface FileTypeBadge {
  code: string
  tone: BadgeTone
}

/** Extension → badge. Order within a tone doesn't matter; membership does. */
const BADGES: Record<string, FileTypeBadge> = {
  // Source — the accent tier.
  ts: { code: "TS", tone: "accent" },
  tsx: { code: "TSX", tone: "accent" },
  js: { code: "JS", tone: "accent" },
  jsx: { code: "JSX", tone: "accent" },
  mjs: { code: "JS", tone: "accent" },
  cjs: { code: "JS", tone: "accent" },
  vue: { code: "VUE", tone: "accent" },
  svelte: { code: "SVX", tone: "accent" },
  go: { code: "GO", tone: "accent" },
  rs: { code: "RS", tone: "accent" },
  py: { code: "PY", tone: "accent" },
  rb: { code: "RB", tone: "accent" },
  java: { code: "JAV", tone: "accent" },
  kt: { code: "KT", tone: "accent" },
  swift: { code: "SWF", tone: "accent" },
  c: { code: "C", tone: "accent" },
  h: { code: "H", tone: "accent" },
  cpp: { code: "CPP", tone: "accent" },
  php: { code: "PHP", tone: "accent" },

  // Structured data — the soft accent tier.
  json: { code: "{ }", tone: "accent-soft" },
  jsonc: { code: "{ }", tone: "accent-soft" },
  yaml: { code: "YML", tone: "accent-soft" },
  yml: { code: "YML", tone: "accent-soft" },
  toml: { code: "TML", tone: "accent-soft" },

  // Markup, styles, docs — neutral.
  md: { code: "MD", tone: "neutral" },
  mdx: { code: "MDX", tone: "neutral" },
  html: { code: "HTM", tone: "neutral" },
  css: { code: "CSS", tone: "neutral" },
  scss: { code: "SCS", tone: "neutral" },
  sh: { code: "SH", tone: "neutral" },
  bash: { code: "SH", tone: "neutral" },
  zsh: { code: "SH", tone: "neutral" },
  sql: { code: "SQL", tone: "neutral" },
  xml: { code: "XML", tone: "neutral" },
  svg: { code: "SVG", tone: "neutral" },

  // Noise — dim.
  txt: { code: "TXT", tone: "dim" },
  log: { code: "LOG", tone: "dim" },
  lock: { code: "LK", tone: "dim" },
  lockb: { code: "LK", tone: "dim" },
  env: { code: "EN", tone: "dim" },
  png: { code: "IMG", tone: "dim" },
  jpg: { code: "IMG", tone: "dim" },
  jpeg: { code: "IMG", tone: "dim" },
  gif: { code: "IMG", tone: "dim" },
  webp: { code: "IMG", tone: "dim" },
  ico: { code: "IMG", tone: "dim" },
  pdf: { code: "PDF", tone: "dim" },
  woff: { code: "FNT", tone: "dim" },
  woff2: { code: "FNT", tone: "dim" },
}

/** Files whose whole name, not extension, decides the badge. */
const BY_NAME: Record<string, FileTypeBadge> = {
  "package.json": { code: "{ }", tone: "accent-soft" },
  "tsconfig.json": { code: "TS", tone: "accent" },
  dockerfile: { code: "DK", tone: "neutral" },
  makefile: { code: "MK", tone: "neutral" },
  ".gitignore": { code: "GIT", tone: "dim" },
  "bun.lockb": { code: "LK", tone: "dim" },
  "package-lock.json": { code: "LK", tone: "dim" },
}

export function fileExtension(filename: string): string {
  const name = filename.split("/").pop() ?? filename
  const dot = name.lastIndexOf(".")
  if (dot <= 0) return ""
  return name.slice(dot + 1).toLowerCase()
}

export function badgeFor(filename: string): FileTypeBadge {
  const name = (filename.split("/").pop() ?? filename).toLowerCase()
  const byName = BY_NAME[name]
  if (byName) return byName

  const extension = fileExtension(name)
  const byExtension = BADGES[extension]
  if (byExtension) return byExtension

  // Dotfiles with no extension: `.env.local` reads as `EN`.
  if (name.startsWith(".")) {
    const stem = name.slice(1).split(".")[0] ?? ""
    return { code: stem.slice(0, 2).toUpperCase() || "··", tone: "dim" }
  }

  return { code: extension.slice(0, 3).toUpperCase() || "··", tone: "dim" }
}

/** Language label for the file viewer's badge row and the highlighter. */
export function languageFor(filename: string): string {
  const extension = fileExtension(filename)
  const languages: Record<string, string> = {
    ts: "typescript",
    tsx: "typescript",
    mts: "typescript",
    js: "javascript",
    jsx: "javascript",
    mjs: "javascript",
    cjs: "javascript",
    vue: "vue",
    json: "json",
    jsonc: "json",
    md: "markdown",
    mdx: "markdown",
    css: "css",
    scss: "css",
    html: "html",
    xml: "html",
    svg: "html",
    py: "python",
    go: "go",
    rs: "rust",
    rb: "ruby",
    sh: "shell",
    bash: "shell",
    zsh: "shell",
    yaml: "yaml",
    yml: "yaml",
    toml: "toml",
    sql: "sql",
  }
  return languages[extension] ?? "text"
}

/** True when the viewer should refuse to render the bytes as text. */
export function isBinary(filename: string): boolean {
  const binary = new Set([
    "png", "jpg", "jpeg", "gif", "webp", "ico", "pdf", "woff", "woff2",
    "ttf", "otf", "zip", "tar", "gz", "mp4", "mov", "mp3", "wav", "lockb",
    "so", "dylib", "dll", "exe", "wasm",
  ])
  return binary.has(fileExtension(filename))
}
