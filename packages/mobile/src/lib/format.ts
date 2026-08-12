/** Presentation helpers shared across screens. */

/**
 * `2h ago`, `now`, `yesterday`.
 *
 * Deliberately terse — these sit in tight metadata rows where a full timestamp
 * would wrap. Anything past a week falls back to a date.
 */
export function relativeTime(timestamp: number | null | undefined): string {
  if (!timestamp) return ""
  const ms = Date.now() - timestamp
  if (ms < 0) return "now"

  const minutes = Math.floor(ms / 60_000)
  if (minutes < 1) return "now"
  if (minutes < 60) return `${minutes}m ago`

  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`

  const days = Math.floor(hours / 24)
  if (days === 1) return "yesterday"
  if (days < 7) return `${days} days ago`

  return new Date(timestamp).toLocaleDateString(undefined, { month: "short", day: "numeric" })
}

/** The compact form used in the projects list: `now`, `3h`, `1d`. */
export function shortRelativeTime(timestamp: number | null | undefined): string {
  if (!timestamp) return ""
  const ms = Date.now() - timestamp
  const minutes = Math.floor(ms / 60_000)
  if (minutes < 1) return "now"
  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h`
  const days = Math.floor(hours / 24)
  if (days < 30) return `${days}d`
  return `${Math.floor(days / 30)}mo`
}

/**
 * Collapse the user's home directory to `~`.
 *
 * The server reports absolute paths; the design shows `~/dev/opencode`. We
 * don't know the server's home directory, so this infers it from the shape of
 * the path — the two forms macOS and Linux use.
 */
export function displayPath(path: string): string {
  if (!path) return ""
  const match = /^(\/Users\/[^/]+|\/home\/[^/]+)(\/.*)?$/.exec(path)
  if (match) return `~${match[2] ?? ""}`
  return path
}

/** Last segment of a path — the project or file name. */
export function basename(path: string): string {
  if (!path) return ""
  const parts = path.replace(/\/+$/, "").split("/")
  return parts[parts.length - 1] ?? path
}

/** Everything but the last segment. Used as the secondary line under a filename. */
export function dirname(path: string): string {
  if (!path) return ""
  const parts = path.replace(/\/+$/, "").split("/")
  parts.pop()
  return parts.join("/")
}

/**
 * Two-letter monogram for a project tile: `opencode` → `OC`, `takt-api` → `TK`.
 * Word boundaries first, then the first two letters.
 */
export function initials(name: string): string {
  const words = name.split(/[-_.\s]+/).filter(Boolean)
  if (words.length >= 2) return (words[0]![0]! + words[1]![0]!).toUpperCase()
  return name.slice(0, 2).toUpperCase()
}

/** `4.2 kb`, matching the file viewer's badge. */
export function formatBytes(bytes: number | null | undefined): string {
  if (bytes === null || bytes === undefined) return ""
  if (bytes < 1024) return `${bytes} b`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} kb`
  return `${(bytes / (1024 * 1024)).toFixed(1)} mb`
}

/** `12.4k`, for token counts. */
export function compactNumber(value: number | null | undefined): string {
  if (!value) return "0"
  if (value < 1000) return String(value)
  if (value < 1_000_000) return `${(value / 1000).toFixed(1).replace(/\.0$/, "")}k`
  return `${(value / 1_000_000).toFixed(1).replace(/\.0$/, "")}m`
}

/** Path relative to a root, for display inside a project. */
export function relativeTo(root: string, path: string): string {
  if (!root) return path
  const prefix = root.endsWith("/") ? root : `${root}/`
  return path.startsWith(prefix) ? path.slice(prefix.length) : path
}
