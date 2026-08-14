import Testing

@testable import OceanKit

/// The parts of the connection that do not need a socket: what is remembered,
/// what is forgotten, and who hears about an event.
@Suite("Connection store", .serialized)
@MainActor
struct ConnectionStoreTests {
  private let suite = "ocean.tests.\(UUID().uuidString)"

  private func fixture() -> (ConnectionStore, UserDefaults, Keychain) {
    let defaults = UserDefaults(suiteName: suite)!
    let keychain = Keychain(service: suite)
    return (ConnectionStore(defaults: defaults, keychain: keychain), defaults, keychain)
  }

  private func clean(_ defaults: UserDefaults, _ keychain: Keychain) {
    keychain.removeAll()
    defaults.removePersistentDomain(forName: suite)
  }

  @Test func aFreshStoreIsDetached() {
    let (store, defaults, keychain) = fixture()
    defer { clean(defaults, keychain) }

    #expect(store.status == .disconnected)
    #expect(!store.isConnected)
    #expect(store.client == nil)
    #expect(store.serverLabel == "")
    #expect(!store.streamConnected)
    #expect(store.workingDirectory == nil)
    #expect(!store.isGitRepo)
    #expect(store.steps.map(\.id) == [.reach, .auth, .version, .repo])
    #expect(store.steps.allSatisfy { $0.state == .pending })
    #expect(throws: ApiError.self) { try store.requireClient() }
  }

  @Test func readsRecentsBackOnLaunch() throws {
    let (_, defaults, keychain) = fixture()
    defer { clean(defaults, keychain) }

    let saved = [
      RecentServer(url: "http://127.0.0.1:4100", username: "opencode", lastConnected: 2),
      RecentServer(url: "http://box.local:4096", username: "opencode", lastConnected: 1),
    ]
    defaults.set(try JSONEncoder().encode(saved), forKey: "ocean.macos.recents")

    let reopened = ConnectionStore(defaults: defaults, keychain: keychain)
    #expect(reopened.recents.map(\.url) == ["http://127.0.0.1:4100", "http://box.local:4096"])
  }

  @Test func forgettingTakesTheRecentAndThePasswordWithIt() throws {
    let (_, defaults, keychain) = fixture()
    defer { clean(defaults, keychain) }

    let url = "http://127.0.0.1:4100"
    do {
      try keychain.save(ServerCredentials(url: url, password: "secret", remember: true))
    } catch {
      return  // no usable keychain here; KeychainTests reports it
    }
    defaults.set(
      try JSONEncoder().encode([RecentServer(url: url, lastConnected: 1)]),
      forKey: "ocean.macos.recents")
    defaults.set(url, forKey: "ocean.macos.lastServer")

    let store = ConnectionStore(defaults: defaults, keychain: keychain)
    #expect(store.recents.count == 1)
    #expect(store.savedServer(url) != nil)

    store.forgetServer(url)
    #expect(store.recents.isEmpty)
    #expect(store.savedServer(url) == nil)
    #expect(defaults.string(forKey: "ocean.macos.lastServer") == nil)
    // And it stays forgotten across a relaunch.
    #expect(ConnectionStore(defaults: defaults, keychain: keychain).recents.isEmpty)
  }

  @Test func restoringWithNothingRememberedDoesNotConnect() async {
    let (store, defaults, keychain) = fixture()
    defer { clean(defaults, keychain) }
    #expect(await store.restoreSession() == false)
  }

  /// Recents hold no password, so switching to one has to route through the
  /// connect form rather than silently failing the handshake.
  @Test func switchingToAnUnrememberedServerFails() async {
    let (store, defaults, keychain) = fixture()
    defer { clean(defaults, keychain) }
    #expect(await store.switchServer("http://never.seen:4100") == false)
  }

  @Test func listenersHearEventsUntilTheSubscriptionGoesAway() {
    let (store, defaults, keychain) = fixture()
    defer { clean(defaults, keychain) }

    let heard = Recorder()
    let subscription = store.onServerEvent { heard.types.append($0.type) }

    store.deliver(ServerEvent(type: "session.updated"))
    #expect(heard.types == ["session.updated"])

    subscription.cancel()
    store.deliver(ServerEvent(type: "session.deleted"))
    #expect(heard.types == ["session.updated"])
  }

  @Test func everyListenerHearsEveryEvent() {
    let (store, defaults, keychain) = fixture()
    defer { clean(defaults, keychain) }

    let first = Recorder()
    let second = Recorder()
    let a = store.onServerEvent { first.types.append($0.type) }
    let b = store.onServerEvent { second.types.append($0.type) }

    store.deliver(ServerEvent(type: "message.part.updated"))
    #expect(first.types == ["message.part.updated"])
    #expect(second.types == ["message.part.updated"])
    a.cancel()
    b.cancel()
  }

  @Test func disconnectingClearsEverythingAndStopsAutoAttach() {
    let (store, defaults, keychain) = fixture()
    defer { clean(defaults, keychain) }

    defaults.set("http://127.0.0.1:4100", forKey: "ocean.macos.lastServer")
    store.disconnect()

    #expect(store.status == .disconnected)
    #expect(store.client == nil)
    #expect(store.appInfo == nil)
    #expect(store.username == nil)
    #expect(!store.authFailed)
    #expect(store.steps.allSatisfy { $0.state == .pending })
    #expect(defaults.string(forKey: "ocean.macos.lastServer") == nil)
  }
}

@MainActor
private final class Recorder {
  var types: [String] = []
}
