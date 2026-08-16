import Foundation

public enum DeepLink: Equatable, Sendable {
  case project(path: String)
  case session(id: String, path: String)
  case settings
  case projects
  case active

  public static func parse(_ url: URL) -> DeepLink? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    guard let scheme = components.scheme, scheme.lowercased() == "ocean" else { return nil }

    let host = components.host ?? ""
    let path = components.path

    let actionPath: String
    if host == "open" {
      actionPath = path
    } else if host.isEmpty && path.hasPrefix("/open/") {
      actionPath = String(path.dropFirst(5))
    } else if host.isEmpty && path == "/open" {
      actionPath = ""
    } else {
      return nil
    }

    let normalizedAction = actionPath.hasPrefix("/") ? String(actionPath.dropFirst()) : actionPath

    let queryItems = components.queryItems ?? []
    func queryParam(_ name: String) -> String? {
      guard let value = queryItems.first(where: { $0.name == name })?.value else { return nil }
      let trimmed = value.trimmingCharacters(in: .whitespaces)
      return trimmed.isEmpty ? nil : trimmed
    }

    switch normalizedAction {
    case "project":
      guard let path = queryParam("path") else { return nil }
      return .project(path: path)
    case "session":
      guard let id = queryParam("id"), let path = queryParam("path") else { return nil }
      return .session(id: id, path: path)
    case "settings":
      return .settings
    case "projects":
      return .projects
    case "active":
      return .active
    default:
      return nil
    }
  }
}
