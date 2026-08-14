import Testing

@testable import OceanKit

/// Everything the client does before and after the socket: building the URL,
/// getting past the envelope, and reading `git` back out of the shell endpoint.
///
/// Swift Testing rather than XCTest: this machine has Command Line Tools, which
/// ship `Testing.framework` and no XCTest at all.
@Suite("Client: URLs and auth")
struct ClientUrlTests {
  private func client(_ url: String = "127.0.0.1:4100", password: String = "secret")
    -> OpenCodeClient
  {
    OpenCodeClient(credentials: ServerCredentials(url: url, password: password))
  }

  @Test func normaliseBaseUrlFillsInTheSchemeAndTrimsSlashes() {
    #expect(normaliseBaseUrl("127.0.0.1:4100") == "http://127.0.0.1:4100")
    #expect(normaliseBaseUrl("  192.168.1.24:4096/  ") == "http://192.168.1.24:4096")
    #expect(normaliseBaseUrl("https://box.local/opencode//") == "https://box.local/opencode")
    #expect(normaliseBaseUrl("HTTPS://Box.local") == "HTTPS://Box.local")
    #expect(normaliseBaseUrl("") == "")
  }

  @Test func isValidServerUrlNeedsAHost() {
    #expect(isValidServerUrl("127.0.0.1:4100"))
    #expect(isValidServerUrl("https://box.local"))
    #expect(!isValidServerUrl(""))
    #expect(!isValidServerUrl("   "))
  }

  @Test func displayHostDropsTheScheme() {
    #expect(client().displayHost == "127.0.0.1:4100")
    #expect(client("https://box.local").displayHost == "box.local")
  }

  @Test func basicAuthHeaderMatchesWhatTheServerExpects() {
    // The username is always `opencode`; this is the header a live server takes.
    let live = OpenCodeClient(
      credentials: ServerCredentials(url: "127.0.0.1:4100", password: "hunter2"))
    #expect(live.authHeader == "Basic " + Data("opencode:hunter2".utf8).base64EncodedString())
  }

  @Test func authHeaderIsOmittedWithoutBasicAuth() {
    let anonymous = OpenCodeClient(
      credentials: ServerCredentials(url: "127.0.0.1:4100", useBasicAuth: false))
    #expect(anonymous.authHeader == nil)
  }

  @Test func urlPutsEveryRouteUnderTheApiPrefix() throws {
    let url = try client().url("/session/ses_1/message", ["order": "asc", "limit": "200"])
    #expect(
      url.absoluteString == "http://127.0.0.1:4100/api/session/ses_1/message?limit=200&order=asc")
  }

  @Test func urlEncodesTheLocationScopingBrackets() throws {
    let url = try client().url("/vcs", at("/Users/ravi/dev/ocean"))
    #expect(
      url.absoluteString
        == "http://127.0.0.1:4100/api/vcs?location%5Bdirectory%5D=%2FUsers%2Fravi%2Fdev%2Focean")
  }

  @Test func emptyQueryValuesAreDropped() throws {
    let url = try client().url("/model", ["directory": "", "type": "file"])
    #expect(url.absoluteString == "http://127.0.0.1:4100/api/model?type=file")
  }

  @Test func atIsEmptyWithoutADirectory() {
    #expect(at(nil).isEmpty)
    #expect(at("").isEmpty)
    #expect(at("/tmp") == ["location[directory]": "/tmp"])
  }

  @Test func eventRequestAsksForTheStreamAndCarriesAuth() throws {
    let request = try client().eventRequest()
    #expect(request.url?.absoluteString == "http://127.0.0.1:4100/api/event")
    #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
    #expect(request.value(forHTTPHeaderField: "Authorization") != nil)
  }
}

@Suite("Client: envelopes")
struct EnvelopeTests {
  @Test func stripsBothEnvelopeShapes() throws {
    let scoped = try JSONValue.parse(Data(#"{"location":{"directory":"/x"},"data":[1,2]}"#.utf8))
    #expect(unwrapEnvelope(scoped) == .array([.number(1), .number(2)]))

    let session = try JSONValue.parse(Data(#"{"data":{"id":"ses_1"}}"#.utf8))
    #expect(unwrapEnvelope(session)["id"].string == "ses_1")
  }

  @Test func aBareArrayIsNotAnEnvelope() throws {
    // `/api/project` answers with the list itself, no wrapper.
    let projects = try JSONValue.parse(Data(#"[{"id":"p1","canonical":"/x"}]"#.utf8))
    #expect(unwrapEnvelope(projects).array.count == 1)
  }

  @Test func onlyTheOuterEnvelopeIsStripped() throws {
    let nested = try JSONValue.parse(Data(#"{"data":{"data":"inner"}}"#.utf8))
    #expect(unwrapEnvelope(nested)["data"].string == "inner")
  }
}

@Suite("Client: paths")
struct PathTests {
  @Test func relativeToTheLocation() {
    #expect(relativeTo("/a/b", "/a/b/c/d.swift") == "c/d.swift")
    #expect(relativeTo("/a/b", "/a/b") == "")
    #expect(relativeTo("/a/b/", "/a/b/c") == "c")
    #expect(relativeTo("/a/b", "/a/bc/d") == "a/bc/d")
    // A root of `/` and a root of `""` both leave the path relative rather than
    // collapsing it to nothing — an empty relative path addresses `/fs/read/`
    // and reads no file at all.
    #expect(relativeTo("/", "/a/b") == "a/b")
    #expect(relativeTo("", "/a/b") == "a/b")
  }

  @Test func absoluteInTheLocation() {
    #expect(absoluteIn("/a/b", "c/d") == "/a/b/c/d")
    #expect(absoluteIn("/a/b/", "c") == "/a/b/c")
    #expect(absoluteIn("/a/b", "/already/absolute") == "/already/absolute")
    #expect(absoluteIn("", "c/d") == "c/d")
    #expect(absoluteIn("/", "c") == "/c")
  }
}

@Suite("Client: shell and git plumbing")
struct ShellTextTests {
  @Test func quoteShellArgumentSurvivesAnEmbeddedQuote() {
    #expect(quoteShellArgument("don't") == #"'don'\''t'"#)
    #expect(quoteShellArgument("plain") == "'plain'")
  }

  @Test func firstAndLastLineSkipBlanks() {
    let output = "\n  first  \nmiddle\n\n  last \n\n"
    #expect(firstLine(output) == "first")
    #expect(lastLine(output) == "last")
    #expect(firstLine("   \n\n") == nil)
  }

  @Test func recognisesCommitHashes() {
    #expect(isCommitHash("d3710cd"))
    #expect(isCommitHash("d3710cdd3710cdd3710cdd3710cdd3710cdd3710"))
    #expect(!isCommitHash("abc"))
    #expect(!isCommitHash("zzzzzzz"))
    #expect(!isCommitHash("d3710cdd3710cdd3710cdd3710cdd3710cdd37101"))
  }

  @Test func parseCommitDetailPairsNameStatusWithNumstat() throws {
    let us = "\u{1f}"
    let rs = "\u{1e}"
    let output = [
      "abc1234def5678\(us)Ravi\(us)1700000000\(us)Ship the thing\(us)HEAD -> main, origin/main",
      "",
      "M\tSources/App.swift",
      "A\tSources/New.swift",
      "R100\tSources/Old.swift\tSources/Moved.swift",
      "D\tSources/Gone.swift",
      rs,
      "12\t3\tSources/App.swift",
      "40\t0\tSources/New.swift",
      "1\t1\tSources/Moved.swift",
      "-\t-\tassets/logo.png",
    ].joined(separator: "\n")

    let detail = try #require(parseCommitDetail(output))
    #expect(detail.commit.hash == "abc1234def5678")
    #expect(detail.commit.shortHash == "abc1234")
    #expect(detail.commit.author == "Ravi")
    #expect(detail.commit.subject == "Ship the thing")
    #expect(detail.commit.date == 1_700_000_000_000)
    #expect(detail.commit.refs == ["HEAD -> main", "origin/main"])

    #expect(
      detail.files.map(\.path) == [
        "Sources/App.swift", "Sources/New.swift", "Sources/Moved.swift", "Sources/Gone.swift",
      ])
    #expect(detail.files[0].status == .modified)
    #expect(detail.files[0].added == 12)
    #expect(detail.files[0].removed == 3)
    #expect(detail.files[1].status == .added)
    // A rename is reported old-then-new; the new path is the file.
    #expect(detail.files[2].status == .modified)
    #expect(detail.files[3].status == .deleted)
    #expect(detail.files[3].added == 0)
  }

  @Test func parseCommitDetailRejectsOutputWithNoHeader() {
    #expect(parseCommitDetail("fatal: bad object deadbeef\n") == nil)
  }
}

@Suite("Client: config")
struct ConfigTests {
  @Test func homeFromConfigMinesTheConfigPaths() {
    // The real shape of `GET /api/config`.
    let entries = [
      ConfigEntry(type: "claude", path: "/Users/ankityadav/.claude"),
      ConfigEntry(type: "document", path: "/Users/ankityadav/.config/opencode/opencode.json"),
    ]
    #expect(homeFromConfig(entries, cwd: "/Users/ankityadav/dev/x") == "/Users/ankityadav")
  }

  @Test func homeFromConfigFallsBackToTheWorkingDirectory() {
    #expect(homeFromConfig([], cwd: "/Users/ravi/dev/x") == "/Users/ravi")
    #expect(homeFromConfig([], cwd: "/home/ravi/dev/x") == "/home/ravi")
    #expect(homeFromConfig([], cwd: "/opt/thing") == nil)
    #expect(homeFromConfig([], cwd: nil) == nil)
  }
}
