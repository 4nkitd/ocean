/**
 * Failure modes the UI distinguishes.
 *
 * Screens render different states for "wrong password" and "server unreachable",
 * so the client has to preserve which one happened rather than collapsing
 * everything into a generic Error.
 */
export type ApiErrorKind =
  | "network" // DNS failure, refused connection, TLS problem, CORS block
  | "auth" // 401/403 — credentials missing or rejected
  | "notfound" // 404, or a web UI where the v2 API should be
  | "server" // 5xx
  | "timeout"
  | "aborted" // caller cancelled; not shown to the user
  | "parse" // reached the server but the body wasn't what we expected
  | "unsupported" // this server build doesn't offer the capability

export class ApiError extends Error {
  readonly kind: ApiErrorKind
  readonly status: number | null
  readonly url: string | null

  constructor(kind: ApiErrorKind, message: string, status: number | null = null, url: string | null = null) {
    super(message)
    this.name = "ApiError"
    this.kind = kind
    this.status = status
    this.url = url
  }

  /** True when retrying the same request might succeed. */
  get retryable(): boolean {
    return this.kind === "network" || this.kind === "timeout" || this.kind === "server"
  }

  /** Copy safe to show the user. Never leaks a URL with credentials in it. */
  get userMessage(): string {
    switch (this.kind) {
      case "network":
        return "Could not reach the server. Check the address, and that `opencode serve` is still running."
      case "auth":
        return "Wrong or missing password. Every v2 server needs one — the username is always `opencode`."
      case "notfound":
        return "Nothing answers the v2 API there. Check the address, or turn the relay on if this app is not on localhost."
      case "server":
        return `The server returned an error${this.status ? ` (${this.status})` : ""}.`
      case "timeout":
        return "The server did not respond in time."
      case "parse":
        return "The server responded with something this client could not read."
      case "unsupported":
        return this.message
      case "aborted":
        return "Cancelled."
    }
  }
}

export function isApiError(value: unknown): value is ApiError {
  return value instanceof ApiError
}

/** Turn any thrown value into copy suitable for an error state. */
export function toUserMessage(value: unknown): string {
  if (isApiError(value)) return value.userMessage
  if (value instanceof Error) return value.message
  return String(value)
}
