import Testing

@testable import OceanKit

/**
 Tests that talk to a real `opencode serve` (v2).

 They are opt-in and self-skipping: set `OCEAN_TEST_PASSWORD` (and optionally
 `OCEAN_TEST_URL`, which defaults to the usual local port) and they run; leave
 it unset, or stop the server, and every one of them returns without an
 assertion. The suite must not be permanently coupled to a local process, and
 the password does not belong in the repository.

     OCEAN_TEST_PASSWORD=… swift test
 */
enum Live {
  static var credentials: ServerCredentials? {
    let environment = ProcessInfo.processInfo.environment
    guard let password = environment["OCEAN_TEST_PASSWORD"], !password.isEmpty else { return nil }
    return ServerCredentials(
      url: environment["OCEAN_TEST_URL"] ?? "http://127.0.0.1:4100",
      username: "opencode",
      password: password
    )
  }

  /// `nil` when there is nothing to talk to, which is the whole skip mechanism.
  static func client() async -> OpenCodeClient? {
    guard let credentials else { return nil }
    let client = OpenCodeClient(credentials: credentials)
    guard let health = try? await client.health(), health.healthy else { return nil }
    return client
  }

  /// This repository, which is a real git worktree the server can be scoped to.
  static let repository: String = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .path
}

@Suite("Live: connection", .serialized)
struct LiveConnectionTests {
  @Test func health() async throws {
    guard let client = await Live.client() else { return }
    let health = try await client.health()
    #expect(health.healthy)
    #expect(health.version?.isEmpty == false)
  }

  @Test func appInfo() async throws {
    guard let client = await Live.client() else { return }
    let info = try await client.getAppInfo()
    #expect(info.version?.isEmpty == false)
    #expect(info.path?.cwd?.hasPrefix("/") == true)
    // Mined from the config document paths; every real install has one.
    #expect(info.home?.hasPrefix("/") == true)
  }

  @Test func rejectsAWrongPassword() async throws {
    guard let credentials = Live.credentials, await Live.client() != nil else { return }
    var wrong = credentials
    wrong.password = "definitely-not-the-password"
    let client = OpenCodeClient(credentials: wrong)
    await #expect(throws: ApiError.self) { try await client.health() }
    do {
      _ = try await client.health()
    } catch let error as ApiError {
      #expect(error.kind == .auth)
    }
  }

  @Test func reportsAnUnreachableServerAsNetwork() async throws {
    let client = OpenCodeClient(
      credentials: ServerCredentials(url: "http://127.0.0.1:1", password: "x"))
    do {
      _ = try await client.health()
      Issue.record("expected a network failure")
    } catch let error as ApiError {
      #expect(error.kind == .network)
    }
  }
}

@Suite("Live: projects and sessions", .serialized)
struct LiveProjectTests {
  @Test func listsProjects() async throws {
    guard let client = await Live.client() else { return }
    let projects = try await client.listProjects()
    #expect(!projects.isEmpty)
    for project in projects {
      #expect(project.worktree.hasPrefix("/"))
      #expect(project.worktree != "/")
    }
  }

  @Test func listsSessionsAndTheirMessages() async throws {
    guard let client = await Live.client() else { return }
    let sessions = try await client.listSessions()
    #expect(!sessions.isEmpty)
    #expect(sessions.allSatisfy { $0.parentID == nil })

    guard let newest = sessions.first else { return }
    #expect(newest.timeCreated > 0)

    let messages = try await client.listMessages(newest.id)
    for message in messages {
      #expect(!message.info.id.isEmpty)
      #expect(message.info.sessionID == newest.id)
    }

    // One message on its own, which is a different route with the same shape.
    if let first = messages.first {
      let one = try await client.getMessage(newest.id, first.info.id)
      #expect(one?.info.id == first.info.id)
      #expect(one?.info.role == first.info.role)
    }

    let resolved = try await client.getSession(newest.id)
    #expect(resolved?.id == newest.id)
  }

  @Test func createsAndDeletesASession() async throws {
    guard let client = await Live.client() else { return }
    let session = try await client.createSession(
      directory: Live.repository, title: "OceanKit live test")
    #expect(session.id.hasPrefix("ses_"))
    #expect(session.title == "OceanKit live test")

    // The blocking-request routes, on a session that cannot possibly be stuck.
    #expect(try await client.listPermissions(session.id).isEmpty)
    #expect(try await client.listQuestions(session.id).isEmpty)
    #expect(try await client.listForms(session.id).isEmpty)
    #expect(try await client.listInbox(session.id).isEmpty)

    try await client.deleteSession(session.id)
    let sessions = try await client.listSessions()
    #expect(!sessions.contains { $0.id == session.id })
  }

  @Test func readsActiveSessions() async throws {
    guard let client = await Live.client() else { return }
    // Usually empty; the point is that the envelope and the id lookup decode.
    let statuses = try await client.getSessionStatuses()
    #expect(statuses != nil)
    _ = try await client.listActiveSessions()
    _ = try await client.listPendingPermissions(Live.repository)
  }
}

@Suite("Live: agents, models, commands", .serialized)
struct LiveCatalogueTests {
  @Test func listsModelsWithTheirCapabilities() async throws {
    guard let client = await Live.client() else { return }
    let models = try await client.listModels()
    #expect(!models.isEmpty)
    for model in models {
      #expect(!model.id.isEmpty)
      #expect(!model.providerID.isEmpty)
    }
    // The server reports which modalities a model accepts; without this the
    // composer cannot know whether to offer the attach button.
    #expect(models.contains { !$0.capabilities.input.isEmpty })
    #expect(models.contains { $0.capabilities.acceptsImages })
    #expect(models.contains { !$0.variants.isEmpty })
  }

  @Test func listsAgents() async throws {
    guard let client = await Live.client() else { return }
    let agents = try await client.listAgents()
    #expect(!agents.isEmpty)
    #expect(agents.allSatisfy { !$0.hidden })
    #expect(agents.contains { $0.mode == "primary" })
  }

  @Test func readsTheDefaults() async throws {
    guard let client = await Live.client() else { return }
    let defaults = try await client.getDefaults()
    #expect(defaults.model?.modelID.isEmpty == false)
    #expect(defaults.model?.providerID.isEmpty == false)
    #expect(defaults.agent?.isEmpty == false)
  }

  @Test func listsCommands() async throws {
    guard let client = await Live.client() else { return }
    let commands = try await client.listCommands()
    #expect(!commands.isEmpty)
    #expect(commands.allSatisfy { !$0.name.isEmpty })
    #expect(commands.contains { $0.template.contains("$ARGUMENTS") })
  }

  @Test func listsMcpServers() async throws {
    guard let client = await Live.client() else { return }
    guard let servers = try await client.listMcp() else { return }
    #expect(servers.map(\.name) == servers.map(\.name).sorted { $0.lowercased() < $1.lowercased() })
    for server in servers where server.status == .failed {
      #expect(server.error?.isEmpty == false)
    }
  }
}

@Suite("Live: files and vcs", .serialized)
struct LiveFileTests {
  @Test func listsAndReadsFiles() async throws {
    guard let client = await Live.client() else { return }
    let root = Live.repository

    let entries = try await client.listDirectory(root, directory: root)
    #expect(!entries.isEmpty)
    #expect(entries.allSatisfy { $0.path.hasPrefix("/") })
    #expect(entries.contains { $0.name == "packages" && $0.type == .directory })

    let found = try await client.findFiles("Package.swift", directory: root)
    #expect(found.contains("\(root)/packages/macos/Package.swift"))

    let file = try await client.readFile("\(root)/packages/macos/Package.swift", directory: root)
    #expect(file.content.contains("swift-tools-version"))
  }

  @Test func readsTheWorkingTree() async throws {
    guard let client = await Live.client() else { return }
    let root = Live.repository

    let info = try await client.getVcsInfo(root)
    #expect(info?.branch?.isEmpty == false)
    #expect((info?.ahead ?? -1) >= 0)
    #expect((info?.behind ?? -1) >= 0)

    #expect(try await client.getVcsBranch(root) == info?.branch)

    let status = try await client.getVcsStatus(root)
    let asFileStatus = try await client.fileStatus(root)
    #expect(status.count == asFileStatus.count)

    let diff = try await client.getVcsDiff(root)
    #expect(diff.allSatisfy { !$0.file.isEmpty })
  }

  @Test func readsCommitHistoryThroughTheShell() async throws {
    guard let client = await Live.client() else { return }
    let root = Live.repository

    let commits = try await client.getVcsCommits(root, limit: 5)
    #expect(!commits.isEmpty)
    #expect(commits.count <= 5)
    guard let newest = commits.first else { return }
    #expect(newest.hash.count == 40)
    #expect(newest.shortHash == String(newest.hash.prefix(7)))
    #expect(newest.date > 0)
    #expect(!newest.author.isEmpty)

    let detail = try await client.getCommitDetail(root, newest.hash)
    #expect(detail?.commit.hash == newest.hash)
    #expect(detail?.files.isEmpty == false)

    if let path = detail?.files.first?.path {
      let patch = try await client.getCommitFileDiff(root, newest.hash, path)
      #expect(patch.contains("diff --git") || patch.contains("@@"))
    }
    #expect(try await client.getCommitDetail(root, "not-a-hash") == nil)
  }
}

@Suite("Live: shell", .serialized)
struct LiveShellTests {
  @Test func runsAOneShotCommand() async throws {
    guard let client = await Live.client() else { return }
    let result = try await client.runShell(Live.repository, "echo hello", timeout: 20)
    #expect(result.output.contains("hello"))
    #expect(result.exit == 0)
    #expect(result.status == .exited)
  }

  @Test func reportsANonZeroExit() async throws {
    guard let client = await Live.client() else { return }
    let result = try await client.runShell(Live.repository, "exit 3", timeout: 20)
    #expect(result.exit == 3)
  }

  @Test func pagesOutputByByteCursor() async throws {
    guard let client = await Live.client() else { return }
    let root = Live.repository
    let started = try await client.startShell(root, "echo one; echo two", timeout: 30)
    #expect(!started.id.isEmpty)

    var command = started
    for _ in 0..<40 where command.status == .running {
      try await Task.sleep(nanoseconds: 100_000_000)
      guard let polled = try await client.getShell(root, started.id) else { break }
      command = polled
    }
    #expect(command.status == .exited)
    #expect(command.exit == 0)

    let first = try await client.readShellOutput(root, started.id)
    #expect(first.output == "one\ntwo\n")
    #expect(first.cursor == 8)
    #expect(!first.truncated)

    // Resuming from the cursor must not repeat what has already been read.
    let second = try await client.readShellOutput(root, started.id, cursor: first.cursor)
    #expect(second.output.isEmpty)
    #expect(second.cursor == first.cursor)

    let middle = try await client.readShellOutput(root, started.id, cursor: 4)
    #expect(middle.output == "two\n")

    await client.removeShell(root, started.id)
    #expect(try await client.getShell(root, started.id) == nil)
  }
}

@Suite("Live: event stream", .serialized)
struct LiveEventTests {
  @Test func connectsAndYieldsAFrame() async throws {
    guard let client = await Live.client() else { return }
    let stream = EventStream(client: client)
    let events = await stream.events()
    await stream.start()
    defer { Task { await stream.stop() } }

    let first = await withTaskGroup(of: ServerEvent?.self) { group in
      group.addTask {
        for await event in events { return event }
        return nil
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: 15_000_000_000)
        return nil
      }
      let result = await group.next() ?? nil
      group.cancelAll()
      return result
    }

    let event = try #require(first, "the stream produced nothing in 15s")
    #expect(!event.type.isEmpty)
    #expect(await stream.isConnected)
    #expect(await stream.lastError == nil)
  }

  @Test func fansOutToEveryConsumer() async throws {
    guard let client = await Live.client() else { return }
    let stream = EventStream(client: client)
    let one = await stream.events()
    let two = await stream.events()
    await stream.start()
    defer { Task { await stream.stop() } }

    async let firstOfOne = firstEvent(of: one)
    async let firstOfTwo = firstEvent(of: two)
    let (a, b) = await (firstOfOne, firstOfTwo)
    #expect(a != nil)
    #expect(b != nil)
  }

  @Test func reportsConnectedThenDisconnected() async throws {
    guard let client = await Live.client() else { return }
    let stream = EventStream(client: client)
    await stream.start()
    for _ in 0..<50 where await stream.status != .connected {
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    #expect(await stream.status == .connected)
    await stream.stop()
    #expect(await stream.status == .disconnected)
  }

  private func firstEvent(of stream: AsyncStream<ServerEvent>) async -> ServerEvent? {
    await withTaskGroup(of: ServerEvent?.self) { group in
      group.addTask {
        for await event in stream { return event }
        return nil
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: 15_000_000_000)
        return nil
      }
      let result = await group.next() ?? nil
      group.cancelAll()
      return result
    }
  }
}
