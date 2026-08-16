import Testing

@testable import OceanKit

/// Request builder helper to construct paths and HTTP methods for new v2 API endpoints.
enum ApiSurfaceRequestBuilder {
  static func renameSessionRequest(id: String, title: String) -> (path: String, method: String, body: JSONValue) {
    (path: "/session/\(pathEscape(id))/rename", method: "POST", body: .object(["title": .string(title)]))
  }

  static func forkSessionRequest(id: String, boundary: JSONValue? = nil) -> (path: String, method: String, body: JSONValue) {
    let payloadBoundary = boundary ?? .object(["type": .string("through")])
    return (path: "/session/\(pathEscape(id))/fork", method: "POST", body: .object(["boundary": payloadBoundary]))
  }

  static func compactSessionRequest(id: String) -> (path: String, method: String) {
    (path: "/session/\(pathEscape(id))/compact", method: "POST")
  }

  static func exportSessionRequest(id: String) -> (path: String, method: String) {
    (path: "/session/\(pathEscape(id))/export", method: "GET")
  }

  static func stageRevertRequest(id: String, messageID: String, files: Bool? = nil) -> (path: String, method: String, body: JSONValue) {
    var body: [String: JSONValue] = ["messageID": .string(messageID)]
    if let files { body["files"] = .bool(files) }
    return (path: "/session/\(pathEscape(id))/revert/stage", method: "POST", body: .object(body))
  }

  static func commitRevertRequest(id: String) -> (path: String, method: String) {
    (path: "/session/\(pathEscape(id))/revert/commit", method: "POST")
  }

  static func clearRevertRequest(id: String) -> (path: String, method: String) {
    (path: "/session/\(pathEscape(id))/revert/clear", method: "POST")
  }

  static func listSavedPermissionsRequest() -> (path: String, method: String) {
    (path: "/permission/saved", method: "GET")
  }

  static func removeSavedPermissionRequest(id: String) -> (path: String, method: String) {
    (path: "/permission/saved/\(pathEscape(id))", method: "DELETE")
  }

  static func listSkillsRequest() -> (path: String, method: String) {
    (path: "/skill", method: "GET")
  }

  static func activateSkillRequest(sessionID: String, skillID: String) -> (path: String, method: String, body: JSONValue) {
    (path: "/session/\(pathEscape(sessionID))/skill", method: "POST", body: .object(["skill": .string(skillID)]))
  }

  static func listReferencesRequest() -> (path: String, method: String) {
    (path: "/reference", method: "GET")
  }

  static func listProvidersRequest() -> (path: String, method: String) {
    (path: "/provider", method: "GET")
  }

  static func getProviderRequest(id: String) -> (path: String, method: String) {
    (path: "/provider/\(pathEscape(id))", method: "GET")
  }

  static func listMcpResourcesRequest() -> (path: String, method: String) {
    (path: "/mcp/resource", method: "GET")
  }
}

@Suite("API surface: builder patterns and model decoding")
struct ApiSurfaceTests {
  private func makeClient() -> OpenCodeClient {
    OpenCodeClient(credentials: ServerCredentials(url: "127.0.0.1:4100", password: "secret"))
  }

  @Test func renameSessionRequestUrlAndMethod() throws {
    let client = makeClient()
    let req = ApiSurfaceRequestBuilder.renameSessionRequest(id: "ses_abc/1", title: "New Title")
    let targetURL = try client.url(req.path)
    #expect(targetURL.absoluteString == "http://127.0.0.1:4100/api/session/ses_abc%2F1/rename")
    #expect(req.method == "POST")
    #expect(req.body["title"].string == "New Title")
  }

  @Test func forkSessionRequestUrlAndMethod() throws {
    let client = makeClient()
    let req = ApiSurfaceRequestBuilder.forkSessionRequest(id: "ses_xyz:2")
    let targetURL = try client.url(req.path)
    #expect(targetURL.absoluteString == "http://127.0.0.1:4100/api/session/ses_xyz%3A2/fork")
    #expect(req.method == "POST")
    #expect(req.body["boundary"]["type"].string == "through")
  }

  @Test func compactSessionRequestUrlAndMethod() throws {
    let client = makeClient()
    let req = ApiSurfaceRequestBuilder.compactSessionRequest(id: "ses_123")
    let targetURL = try client.url(req.path)
    #expect(targetURL.absoluteString == "http://127.0.0.1:4100/api/session/ses_123/compact")
    #expect(req.method == "POST")
  }

  @Test func exportSessionRequestUrlAndMethod() throws {
    let client = makeClient()
    let req = ApiSurfaceRequestBuilder.exportSessionRequest(id: "ses_123")
    let targetURL = try client.url(req.path)
    #expect(targetURL.absoluteString == "http://127.0.0.1:4100/api/session/ses_123/export")
    #expect(req.method == "GET")
  }

  @Test func stageRevertRequestUrlAndMethod() throws {
    let client = makeClient()
    let req = ApiSurfaceRequestBuilder.stageRevertRequest(id: "ses_123", messageID: "msg_999", files: true)
    let targetURL = try client.url(req.path)
    #expect(targetURL.absoluteString == "http://127.0.0.1:4100/api/session/ses_123/revert/stage")
    #expect(req.method == "POST")
    #expect(req.body["messageID"].string == "msg_999")
    #expect(req.body["files"].isTrue)
  }

  @Test func commitRevertRequestUrlAndMethod() throws {
    let client = makeClient()
    let req = ApiSurfaceRequestBuilder.commitRevertRequest(id: "ses_123")
    let targetURL = try client.url(req.path)
    #expect(targetURL.absoluteString == "http://127.0.0.1:4100/api/session/ses_123/revert/commit")
    #expect(req.method == "POST")
  }

  @Test func clearRevertRequestUrlAndMethod() throws {
    let client = makeClient()
    let req = ApiSurfaceRequestBuilder.clearRevertRequest(id: "ses_123")
    let targetURL = try client.url(req.path)
    #expect(targetURL.absoluteString == "http://127.0.0.1:4100/api/session/ses_123/revert/clear")
    #expect(req.method == "POST")
  }

  @Test func listSavedPermissionsRequestUrlAndMethod() throws {
    let client = makeClient()
    let req = ApiSurfaceRequestBuilder.listSavedPermissionsRequest()
    let targetURL = try client.url(req.path)
    #expect(targetURL.absoluteString == "http://127.0.0.1:4100/api/permission/saved")
    #expect(req.method == "GET")
  }

  @Test func removeSavedPermissionRequestUrlAndMethod() throws {
    let client = makeClient()
    let req = ApiSurfaceRequestBuilder.removeSavedPermissionRequest(id: "psv_789")
    let targetURL = try client.url(req.path)
    #expect(targetURL.absoluteString == "http://127.0.0.1:4100/api/permission/saved/psv_789")
    #expect(req.method == "DELETE")
  }

  @Test func listSkillsRequestUrlAndMethod() throws {
    let client = makeClient()
    let req = ApiSurfaceRequestBuilder.listSkillsRequest()
    let targetURL = try client.url(req.path)
    #expect(targetURL.absoluteString == "http://127.0.0.1:4100/api/skill")
    #expect(req.method == "GET")
  }

  @Test func activateSkillRequestUrlAndMethod() throws {
    let client = makeClient()
    let req = ApiSurfaceRequestBuilder.activateSkillRequest(sessionID: "ses_123", skillID: "wacli")
    let targetURL = try client.url(req.path)
    #expect(targetURL.absoluteString == "http://127.0.0.1:4100/api/session/ses_123/skill")
    #expect(req.method == "POST")
    #expect(req.body["skill"].string == "wacli")
  }

  @Test func listReferencesRequestUrlAndMethod() throws {
    let client = makeClient()
    let req = ApiSurfaceRequestBuilder.listReferencesRequest()
    let targetURL = try client.url(req.path)
    #expect(targetURL.absoluteString == "http://127.0.0.1:4100/api/reference")
    #expect(req.method == "GET")
  }

  @Test func listProvidersRequestUrlAndMethod() throws {
    let client = makeClient()
    let req = ApiSurfaceRequestBuilder.listProvidersRequest()
    let targetURL = try client.url(req.path)
    #expect(targetURL.absoluteString == "http://127.0.0.1:4100/api/provider")
    #expect(req.method == "GET")
  }

  @Test func getProviderRequestUrlAndMethod() throws {
    let client = makeClient()
    let req = ApiSurfaceRequestBuilder.getProviderRequest(id: "opencode-go")
    let targetURL = try client.url(req.path)
    #expect(targetURL.absoluteString == "http://127.0.0.1:4100/api/provider/opencode-go")
    #expect(req.method == "GET")
  }

  @Test func listMcpResourcesRequestUrlAndMethod() throws {
    let client = makeClient()
    let req = ApiSurfaceRequestBuilder.listMcpResourcesRequest()
    let targetURL = try client.url(req.path)
    #expect(targetURL.absoluteString == "http://127.0.0.1:4100/api/mcp/resource")
    #expect(req.method == "GET")
  }

  @Test func decodesSavedPermission() throws {
    let raw = """
      {
        "id": "psv_123",
        "projectID": "global",
        "action": "external_directory",
        "resource": "/Users/test/*"
      }
      """
    let json = try JSONValue.parse(Data(raw.utf8))
    let perm = try #require(SavedPermission(json: json))
    #expect(perm.id == "psv_123")
    #expect(perm.projectID == "global")
    #expect(perm.action == "external_directory")
    #expect(perm.resource == "/Users/test/*")
  }

  @Test func decodesSkillInfo() throws {
    let raw = """
      {
        "id": "opencode",
        "name": "OpenCode",
        "description": "Helper skill",
        "slash": true,
        "location": "/path/SKILL.md",
        "content": "Skill content"
      }
      """
    let json = try JSONValue.parse(Data(raw.utf8))
    let skill = try #require(SkillInfo(json: json))
    #expect(skill.id == "opencode")
    #expect(skill.name == "OpenCode")
    #expect(skill.description == "Helper skill")
    #expect(skill.slash == true)
    #expect(skill.content == "Skill content")
  }

  @Test func decodesReferenceInfo() throws {
    let raw = """
      {
        "name": "docs",
        "path": "/Users/test/docs",
        "description": "Local docs",
        "hidden": false
      }
      """
    let json = try JSONValue.parse(Data(raw.utf8))
    let ref = try #require(ReferenceInfo(json: json))
    #expect(ref.name == "docs")
    #expect(ref.path == "/Users/test/docs")
    #expect(ref.id == "docs")
  }

  @Test func decodesProviderInfo() throws {
    let raw = """
      {
        "id": "google",
        "integrationID": "google",
        "name": "Google",
        "package": "aisdk:@ai-sdk/google"
      }
      """
    let json = try JSONValue.parse(Data(raw.utf8))
    let prov = try #require(ProviderInfo(json: json))
    #expect(prov.id == "google")
    #expect(prov.integrationID == "google")
    #expect(prov.name == "Google")
    #expect(prov.package == "aisdk:@ai-sdk/google")
  }

  @Test func decodesMcpResourceCatalog() throws {
    let raw = """
      {
        "resources": [
          {
            "server": "github",
            "name": "repo-issue",
            "uri": "github://issue/1",
            "description": "Issue #1",
            "mimeType": "application/json"
          }
        ],
        "templates": [
          {
            "server": "github",
            "name": "issue-template",
            "uriTemplate": "github://issue/{id}",
            "description": "Issue template"
          }
        ]
      }
      """
    let json = try JSONValue.parse(Data(raw.utf8))
    let catalog = McpResourceCatalog(json: json)
    #expect(catalog.resources.count == 1)
    #expect(catalog.resources[0].server == "github")
    #expect(catalog.resources[0].uri == "github://issue/1")
    #expect(catalog.resources[0].id == "github:github://issue/1")
    #expect(catalog.templates.count == 1)
    #expect(catalog.templates[0].uriTemplate == "github://issue/{id}")
  }

  @Test func decodesSessionExportInfo() throws {
    let raw = """
      {
        "info": {
          "id": "ses_exp1",
          "title": "Exported Session",
          "time": {"created": 1000, "updated": 2000}
        },
        "messages": []
      }
      """
    let json = try JSONValue.parse(Data(raw.utf8))
    let exportInfo = SessionExportInfo(json: json)
    #expect(exportInfo.info?.id == "ses_exp1")
    #expect(exportInfo.info?.title == "Exported Session")
    #expect(exportInfo.messages.isEmpty)
  }

  @Test func decodesSessionRevertInfo() throws {
    let raw = """
      {
        "messageID": "msg_revert1",
        "partID": "p1",
        "snapshot": "snap_1"
      }
      """
    let json = try JSONValue.parse(Data(raw.utf8))
    let revertInfo = try #require(SessionRevertInfo(json: json))
    #expect(revertInfo.messageID == "msg_revert1")
    #expect(revertInfo.partID == "p1")
    #expect(revertInfo.snapshot == "snap_1")
  }
}
