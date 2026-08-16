import Foundation

public final class APICache: @unchecked Sendable {
  public static let shared = APICache()
  private var store: [String: (data: Data, expires: Date)] = [:]
  private let lock = NSLock()

  public init() {}

  public func get(_ key: String) -> Data? {
    lock.lock()
    defer { lock.unlock() }
    guard let item = store[key] else { return nil }
    if Date() > item.expires {
      store.removeValue(forKey: key)
      return nil
    }
    return item.data
  }

  public func put(_ key: String, data: Data, ttl: TimeInterval) {
    lock.lock()
    defer { lock.unlock() }
    let expires = Date().addingTimeInterval(ttl)
    store[key] = (data: data, expires: expires)
  }

  public func invalidateAll() {
    lock.lock()
    defer { lock.unlock() }
    store.removeAll()
  }
}
