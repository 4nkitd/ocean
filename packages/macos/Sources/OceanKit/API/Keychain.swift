import Foundation

/**
 Simple JSON file storage for saved server credentials.

 Saved to `~/.config/opencode/ocean_credentials.json` (or fallback to `Application Support/Ocean`).
 Stores credentials as a JSON dictionary keyed by normalised server URL.
 */
public struct Keychain: Sendable {
  public static let shared = Keychain()

  private let fileURL: URL

  public init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
    } else {
      let home = FileManager.default.homeDirectoryForCurrentUser
      let configDir = home.appendingPathComponent(".config/opencode", isDirectory: true)
      try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
      self.fileURL = configDir.appendingPathComponent("ocean_credentials.json")
    }
  }

  public init(service: String) {
    let tmpDir = FileManager.default.temporaryDirectory
    self.fileURL = tmpDir.appendingPathComponent("keychain_\(service).json")
  }

  private func readStore() -> [String: ServerCredentials] {
    guard let data = try? Data(contentsOf: fileURL),
          let dict = try? JSONDecoder().decode([String: ServerCredentials].self, from: data)
    else {
      return [:]
    }
    return dict
  }

  private func writeStore(_ dict: [String: ServerCredentials]) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    guard let data = try? encoder.encode(dict) else { return }
    try? data.write(to: fileURL, options: .atomic)
  }

  /// Store, or replace, the credentials for this address.
  public func save(_ credentials: ServerCredentials) throws {
    let url = normaliseBaseUrl(credentials.url)
    guard !url.isEmpty else { return }
    var stored = credentials
    stored.url = url

    var current = readStore()
    current[url] = stored
    writeStore(current)
  }

  /// The stored credentials for an address, password included.
  public func load(_ url: String) -> ServerCredentials? {
    let url = normaliseBaseUrl(url)
    guard !url.isEmpty else { return nil }
    return readStore()[url]
  }

  /// Drop one address. Missing is not an error — forgetting twice is fine.
  public func forget(_ url: String) {
    let url = normaliseBaseUrl(url)
    guard !url.isEmpty else { return }
    var current = readStore()
    current.removeValue(forKey: url)
    writeStore(current)
  }

  /// The addresses this Mac has been asked to remember.
  public func savedURLs() -> [String] {
    Array(readStore().keys).sorted()
  }

  /// Every remembered server, password included.
  public func all() -> [ServerCredentials] {
    Array(readStore().values)
  }

  /// Wipe every entry in the file.
  public func wipeAll() {
    try? FileManager.default.removeItem(at: fileURL)
  }

  public func removeAll() {
    wipeAll()
  }
}
