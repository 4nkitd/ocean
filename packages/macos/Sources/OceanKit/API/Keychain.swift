import Foundation
import Security

/// A Security framework call that did not return `errSecSuccess`.
public struct KeychainError: Error, Hashable, Sendable, CustomStringConvertible {
  public let status: OSStatus
  public let operation: String

  public init(status: OSStatus, operation: String) {
    self.status = status
    self.operation = operation
  }

  public var description: String {
    let reason = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
    return "Keychain \(operation) failed: \(reason)"
  }
}

extension KeychainError: LocalizedError {
  public var errorDescription: String? { description }
}

/**
 Where remembered servers live.

 The Vue client keeps credentials in `localStorage`, which is the best a browser
 offers. A Mac app has the keychain, so passwords go there instead and nothing
 in the app's own container ever holds one. Everything else about a server —
 its address, the username, when it was last reached — is not secret and stays
 in `UserDefaults`, owned by `ConnectionStore`.

 One generic-password item per address: the account is the normalised URL and
 the value is the encoded `ServerCredentials`, so a saved server reconnects
 without the form.
 */
public struct Keychain: Sendable {
  public static let defaultService = "ai.opencode.ocean.server"
  public static let shared = Keychain()

  public let service: String

  /// `service` is a parameter so tests can use a namespace of their own rather
  /// than trampling the user's real entries.
  public init(service: String = Keychain.defaultService) {
    self.service = service
  }

  private func query(for url: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: url,
    ]
  }

  /// Store, or replace, the credentials for this address.
  public func save(_ credentials: ServerCredentials) throws {
    let url = normaliseBaseUrl(credentials.url)
    guard !url.isEmpty else { return }
    var stored = credentials
    stored.url = url
    let body = try JSONEncoder().encode(stored)

    var attributes = query(for: url)
    // Available whenever the Mac is unlocked, and never synced to another
    // device: a server on someone's LAN is meaningless on their phone.
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
    attributes[kSecValueData as String] = body

    let status = SecItemAdd(attributes as CFDictionary, nil)
    if status == errSecDuplicateItem {
      let update = SecItemUpdate(
        query(for: url) as CFDictionary, [kSecValueData as String: body] as CFDictionary)
      guard update == errSecSuccess else {
        throw KeychainError(status: update, operation: "update")
      }
      return
    }
    guard status == errSecSuccess else { throw KeychainError(status: status, operation: "add") }
  }

  /// The stored credentials for an address, password included.
  public func load(_ url: String) -> ServerCredentials? {
    let url = normaliseBaseUrl(url)
    guard !url.isEmpty else { return nil }
    var request = query(for: url)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
      let body = result as? Data
    else { return nil }
    return try? JSONDecoder().decode(ServerCredentials.self, from: body)
  }

  /// Drop one address. Missing is not an error — forgetting twice is fine.
  public func forget(_ url: String) {
    let url = normaliseBaseUrl(url)
    guard !url.isEmpty else { return }
    SecItemDelete(query(for: url) as CFDictionary)
  }

  /// Every remembered server, newest first is not knowable here — the store
  /// orders them by its own recents list.
  public func all() -> [ServerCredentials] {
    let request: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecReturnData as String: true,
      kSecReturnAttributes as String: true,
      kSecMatchLimit as String: kSecMatchLimitAll,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
      let items = result as? [[String: Any]]
    else { return [] }

    return items.compactMap { item in
      guard let body = item[kSecValueData as String] as? Data else { return nil }
      return try? JSONDecoder().decode(ServerCredentials.self, from: body)
    }
  }

  /// Wipe every entry in this service. Only used to reset a test namespace.
  public func removeAll() {
    SecItemDelete(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
      ] as CFDictionary)
  }
}
