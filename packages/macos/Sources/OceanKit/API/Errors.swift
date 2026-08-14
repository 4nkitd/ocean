import Foundation

/**
 Failure modes the UI distinguishes.

 Screens render different states for "wrong password" and "server unreachable",
 so the client has to preserve which one happened rather than collapsing
 everything into a generic error.
 */
public enum ApiErrorKind: String, Codable, Hashable, Sendable {
  /// DNS failure, refused connection, TLS problem.
  case network
  /// 401/403 — credentials missing or rejected.
  case auth
  /// 404, or a web UI where the v2 API should be.
  case notfound
  /// 5xx.
  case server
  case timeout
  /// Caller cancelled; not shown to the user.
  case aborted
  /// Reached the server but the body wasn't what we expected.
  case parse
  /// This server build doesn't offer the capability.
  case unsupported
}

public struct ApiError: Error, Hashable, Sendable, CustomStringConvertible {
  public let kind: ApiErrorKind
  public let message: String
  public let status: Int?
  public let url: String?

  public init(_ kind: ApiErrorKind, _ message: String, status: Int? = nil, url: String? = nil) {
    self.kind = kind
    self.message = message
    self.status = status
    self.url = url
  }

  /// True when retrying the same request might succeed.
  public var retryable: Bool {
    kind == .network || kind == .timeout || kind == .server
  }

  /// Copy safe to show the user. Never leaks a URL with credentials in it.
  public var userMessage: String {
    switch kind {
    case .network:
      return "Could not reach the server. Check the address, and that `opencode serve` is still running."
    case .auth:
      return "Wrong or missing password. Every v2 server needs one — the username is always `opencode`."
    case .notfound:
      return "Nothing answers the v2 API there. Check the address, or turn the relay on if this app is not on localhost."
    case .server:
      return status.map { "The server returned an error (\($0))." } ?? "The server returned an error."
    case .timeout:
      return "The server did not respond in time."
    case .parse:
      return "The server responded with something this client could not read."
    case .unsupported:
      return message
    case .aborted:
      return "Cancelled."
    }
  }

  public var description: String { message }
}

extension ApiError: LocalizedError {
  public var errorDescription: String? { message }
}

/// Turn any thrown value into copy suitable for an error state.
public func toUserMessage(_ value: Error) -> String {
  if let api = value as? ApiError { return api.userMessage }
  if value is CancellationError { return ApiError(.aborted, "Cancelled").userMessage }
  if let url = value as? URLError { return apiError(from: url, url: nil).userMessage }
  return value.localizedDescription
}

/// Map a `URLError` onto the kinds the UI branches on.
func apiError(from error: URLError, url: String?) -> ApiError {
  switch error.code {
  case .cancelled:
    return ApiError(.aborted, "Request cancelled", url: url)
  case .timedOut:
    return ApiError(.timeout, "Request timed out", url: url)
  case .userAuthenticationRequired:
    return ApiError(.auth, "Authentication failed", status: 401, url: url)
  default:
    return ApiError(.network, error.localizedDescription, url: url)
  }
}
