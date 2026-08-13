/**
 * Unified-diff parsing.
 *
 * Patches reach the client from two unrelated places — `GET /api/vcs/diff`
 * for working-tree changes, and `git show` through the server's shell endpoint
 * for a commit's files — so the parsing lives here rather than inside a view.
 *
 * The one hard rule: this never throws. A patch the parser cannot make sense of
 * produces an empty hunk list, which the Diff screen renders as "no changes in
 * this file". A phone screen that shows nothing is recoverable; one that dies
 * inside a render is not.
 */
import type { DiffHunk, FileDiff } from "@/api/types"

/** `@@ -5,7 +5,9 @@` — the counts are ignored; line numbers are derived by walking. */
const HUNK_HEADER = /^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/

/**
 * Every file in a patch. `git diff` without a pathspec returns several, and the
 * Diff screen has to pick the one it asked for rather than the first.
 */
export function parseUnifiedDiffFiles(patch: string): FileDiff[] {
  if (typeof patch !== "string" || patch.length === 0) return []

  const files: FileDiff[] = []
  let file: FileDiff | null = null
  let hunk: DiffHunk | null = null
  let oldNumber = 0
  let newNumber = 0

  // A patch ends with a newline; splitting would otherwise invent a trailing
  // empty context line and push every following line number out by one.
  const body = patch.replace(/\r?\n$/, "")

  for (const raw of body.split("\n")) {
    const line = raw.endsWith("\r") ? raw.slice(0, -1) : raw

    if (line.startsWith("diff --git")) {
      file = emptyFile(pathFromGitHeader(line))
      files.push(file)
      hunk = null
      continue
    }

    if (line.startsWith("+++ ")) {
      const path = cleanPath(line.slice(4))
      if (!file) {
        file = emptyFile(path)
        files.push(file)
      } else if (path && path !== "/dev/null") {
        file.path = path
      }
      hunk = null
      continue
    }

    if (line.startsWith("--- ")) {
      hunk = null
      continue
    }

    const header = HUNK_HEADER.exec(line)
    if (header) {
      // A bare `git diff` fragment with no `diff --git` preamble is still a
      // diff worth rendering; the caller supplies the path in that case.
      if (!file) {
        file = emptyFile("")
        files.push(file)
      }
      oldNumber = Number(header[1])
      newNumber = Number(header[2])
      // The design's hunk band is exactly `@@ … @@`, without git's trailing
      // section context, so the header is trimmed at the closing marker.
      const close = line.indexOf("@@", 2)
      hunk = { header: close === -1 ? line : line.slice(0, close + 2), lines: [] }
      file.hunks.push(hunk)
      continue
    }

    if (!file || !hunk) continue

    const marker = line[0] ?? ""

    if (marker === "\\") {
      // "\ No newline at end of file" annotates the line above it and belongs
      // to neither side's numbering.
      hunk.lines.push({ kind: "context", text: line, oldNumber: null, newNumber: null })
      continue
    }

    if (marker === "+") {
      hunk.lines.push({ kind: "add", text: line.slice(1), oldNumber: null, newNumber })
      newNumber += 1
      file.added += 1
      continue
    }

    if (marker === "-") {
      hunk.lines.push({ kind: "del", text: line.slice(1), oldNumber, newNumber: null })
      oldNumber += 1
      file.removed += 1
      continue
    }

    if (marker === " " || line.length === 0) {
      // Some tools strip the trailing space from an empty context line.
      hunk.lines.push({ kind: "context", text: line.slice(1), oldNumber, newNumber })
      oldNumber += 1
      newNumber += 1
      continue
    }

    // Anything else — a binary notice, a stray log line, truncated output —
    // closes the hunk instead of corrupting it.
    hunk = null
  }

  return files.filter((entry) => entry.hunks.length > 0 || entry.path !== "")
}

/**
 * The diff for one file. `path` selects among multi-file patches and is kept as
 * the result's path, because the caller's spelling of it (absolute, or relative
 * to the worktree) is the one the rest of the screen is keyed on.
 */
export function parseUnifiedDiff(patch: string, path = ""): FileDiff {
  const files = parseUnifiedDiffFiles(patch)
  if (files.length === 0) return { path, hunks: [], added: 0, removed: 0 }

  const match = path ? files.find((entry) => samePath(entry.path, path)) : undefined
  const chosen = match ?? files[0]!
  return { ...chosen, path: path || chosen.path }
}

/** Totals for a hunk list, for callers that assembled hunks themselves. */
export function countChanges(hunks: DiffHunk[]): { added: number; removed: number } {
  let added = 0
  let removed = 0
  for (const hunk of hunks) {
    for (const line of hunk.lines) {
      if (line.kind === "add") added += 1
      else if (line.kind === "del") removed += 1
    }
  }
  return { added, removed }
}

/**
 * `+21 −4`. The minus is U+2212, not a hyphen — the design sets these counts in
 * mono beside each other and the hyphen sits too high and too short to read as
 * the pair of the plus.
 */
export function formatChangeCounts(
  added: number | null | undefined,
  removed: number | null | undefined,
): string {
  const parts: string[] = []
  if (added !== null && added !== undefined) parts.push(`+${added}`)
  if (removed !== null && removed !== undefined) parts.push(`−${removed}`)
  return parts.join(" ")
}

/** `2 hunks`, `1 hunk` — the Diff header's third term. */
export function formatHunkCount(count: number): string {
  return `${count} ${count === 1 ? "hunk" : "hunks"}`
}

// ── internals ─────────────────────────────────────────────────────────────

function emptyFile(path: string): FileDiff {
  return { path, hunks: [], added: 0, removed: 0 }
}

function pathFromGitHeader(line: string): string {
  const match = /^diff --git a\/(.+?) b\/(.+)$/.exec(line)
  if (match) return match[2]!
  return cleanPath(line.replace(/^diff --git\s*/, "").split(" ").pop() ?? "")
}

/** Strip git's `a/`/`b/` prefix and the tab-separated timestamp some tools add. */
function cleanPath(value: string): string {
  const withoutMeta = value.split("\t")[0]!.trim()
  return withoutMeta.replace(/^[ab]\//, "")
}

/**
 * Paths inside a patch are worktree-relative; the caller may hold an absolute
 * one. Suffix matching is enough to pair them, and cheaper than resolving.
 */
function samePath(a: string, b: string): boolean {
  if (!a || !b) return false
  if (a === b) return true
  return a.endsWith(`/${b}`) || b.endsWith(`/${a}`)
}
