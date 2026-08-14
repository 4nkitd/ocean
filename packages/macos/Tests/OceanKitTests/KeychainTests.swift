import Testing

@testable import OceanKit

/**
 A real round trip through the Security framework, in a service of this test's
 own so the user's saved servers are never touched.

 The keychain refuses a process it does not trust — an unsigned binary against a
 locked login keychain, most often — and that is an environment problem rather
 than a failure of this code, so every test returns early when the probe write
 fails. `swift test` printing nothing here means the keychain was unavailable,
 not that the code is untested.
 */
@Suite("Keychain", .serialized)
struct KeychainTests {
  /// `nil` when this machine will not let the test binary write.
  private func usable() -> Keychain? {
    let keychain = Keychain(service: "ocean.tests.\(UUID().uuidString)")
    do {
      try keychain.save(ServerCredentials(url: "http://probe.local", password: "x"))
    } catch {
      return nil
    }
    keychain.removeAll()
    return keychain
  }

  @Test func savesAndLoadsUnderTheNormalisedAddress() throws {
    guard let keychain = usable() else { return }
    defer { keychain.removeAll() }

    try keychain.save(
      ServerCredentials(
        url: "127.0.0.1:4100", password: "58cb4becf73777b8364d550f5a902cd4", remember: true))

    // The same server typed two ways is one entry.
    let loaded = try #require(keychain.load("127.0.0.1:4100/"))
    #expect(loaded.url == "http://127.0.0.1:4100")
    #expect(loaded.username == "opencode")
    #expect(loaded.password == "58cb4becf73777b8364d550f5a902cd4")
    #expect(loaded.remember)
  }

  @Test func savingTwiceReplacesRatherThanDuplicates() throws {
    guard let keychain = usable() else { return }
    defer { keychain.removeAll() }

    try keychain.save(ServerCredentials(url: "127.0.0.1:4100", password: "old"))
    try keychain.save(ServerCredentials(url: "127.0.0.1:4100", password: "new"))

    #expect(keychain.load("127.0.0.1:4100")?.password == "new")
    #expect(keychain.all().count == 1)
  }

  @Test func forgettingIsIdempotent() throws {
    guard let keychain = usable() else { return }
    defer { keychain.removeAll() }

    try keychain.save(ServerCredentials(url: "127.0.0.1:4100", password: "x"))
    keychain.forget("127.0.0.1:4100")
    #expect(keychain.load("127.0.0.1:4100") == nil)
    keychain.forget("127.0.0.1:4100")
  }

  @Test func listsEveryRememberedServer() throws {
    guard let keychain = usable() else { return }
    defer { keychain.removeAll() }

    try keychain.save(ServerCredentials(url: "127.0.0.1:4100", password: "a"))
    try keychain.save(ServerCredentials(url: "box.local:4096", password: "b"))
    #expect(Set(keychain.all().map(\.url)) == ["http://127.0.0.1:4100", "http://box.local:4096"])
  }

  @Test func anEmptyAddressIsNotStored() throws {
    guard let keychain = usable() else { return }
    defer { keychain.removeAll() }

    try keychain.save(ServerCredentials(url: "   ", password: "x"))
    #expect(keychain.all().isEmpty)
    #expect(keychain.load("") == nil)
  }
}
