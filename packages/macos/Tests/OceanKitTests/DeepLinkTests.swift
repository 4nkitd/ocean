import Testing
@testable import OceanKit

@Suite("DeepLink parsing")
struct DeepLinkTests {
  @Test func parseProjectURL() {
    let url = URL(string: "ocean://open/project?path=/Users/test/project")!
    let parsed = DeepLink.parse(url)
    #expect(parsed == .project(path: "/Users/test/project"))
  }

  @Test func parseSessionURL() {
    let url = URL(string: "ocean://open/session?id=sess-123&path=/Users/test/project")!
    let parsed = DeepLink.parse(url)
    #expect(parsed == .session(id: "sess-123", path: "/Users/test/project"))
  }

  @Test func parseSettingsURL() {
    let url = URL(string: "ocean://open/settings")!
    let parsed = DeepLink.parse(url)
    #expect(parsed == .settings)
  }

  @Test func parseProjectsURL() {
    let url = URL(string: "ocean://open/projects")!
    let parsed = DeepLink.parse(url)
    #expect(parsed == .projects)
  }

  @Test func parseActiveURL() {
    let url = URL(string: "ocean://open/active")!
    let parsed = DeepLink.parse(url)
    #expect(parsed == .active)
  }

  @Test func parseGarbageURLReturnsNil() {
    #expect(DeepLink.parse(URL(string: "https://example.com")!) == nil)
    #expect(DeepLink.parse(URL(string: "ocean://unknown/route")!) == nil)
    #expect(DeepLink.parse(URL(string: "ocean://open/unknown")!) == nil)
    #expect(DeepLink.parse(URL(string: "not-a-url")!) == nil)
  }

  @Test func parseMissingParamsReturnsNil() {
    #expect(DeepLink.parse(URL(string: "ocean://open/project")!) == nil)
    #expect(DeepLink.parse(URL(string: "ocean://open/project?path=")!) == nil)
    #expect(DeepLink.parse(URL(string: "ocean://open/session?id=sess-123")!) == nil)
    #expect(DeepLink.parse(URL(string: "ocean://open/session?path=/Users/test")!) == nil)
    #expect(DeepLink.parse(URL(string: "ocean://open/session?id=&path=/Users/test")!) == nil)
  }
}
