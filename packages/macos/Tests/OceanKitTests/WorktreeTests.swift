import Testing

@testable import OceanKit

@Suite("Worktree & MCP tests")
struct WorktreeTests {
  private func makeClient() -> OpenCodeClient {
    OpenCodeClient(credentials: ServerCredentials(url: "127.0.0.1:4100", password: "secret"))
  }

  @Test func listWorktreesUrlHitsWorktreeEndpointWithEscapedProjectID() throws {
    let client = makeClient()
    let projectID = "proj/123"
    let path = WorktreeRequestBuilder.listPath(projectID: projectID)
    let targetURL = try client.url(path)
    #expect(targetURL.absoluteString == "http://127.0.0.1:4100/api/worktree/proj%2F123")
  }

  @Test func createWorktreeUrlHitsWorktreeEndpointWithEscapedProjectID() throws {
    let client = makeClient()
    let projectID = "prj_abc:45"
    let path = WorktreeRequestBuilder.createPath(projectID: projectID)
    let targetURL = try client.url(path)
    #expect(targetURL.absoluteString == "http://127.0.0.1:4100/api/worktree/prj_abc%3A45")
  }

  @Test func decodesRawWorktreeArray() throws {
    let raw = """
      [
        {"directory": "/Users/test/project-copy", "strategy": "copy"},
        {"directory": "/Users/test/project-link", "strategy": "link"}
      ]
      """
    let json = try JSONValue.parse(Data(raw.utf8))
    let worktrees = try #require(WorktreeRequestBuilder.parseListResponse(json))
    #expect(worktrees.count == 2)
    #expect(worktrees[0].directory == "/Users/test/project-copy")
    #expect(worktrees[0].strategy == "copy")
    #expect(worktrees[0].id == "/Users/test/project-copy")
    #expect(worktrees[1].directory == "/Users/test/project-link")
    #expect(worktrees[1].strategy == "link")
  }

  @Test func nilReturnedForNullResponse() {
    let json: JSONValue = .null
    let worktrees = WorktreeRequestBuilder.parseListResponse(json)
    #expect(worktrees == nil)
  }

  @Test func createWorktreeBodyEncoding() throws {
    let body = WorktreeRequestBuilder.createBody(
      strategy: "copy",
      from: "main",
      directory: "/tmp/wt1",
      name: "wt1"
    )
    let encoded = try body.encoded()
    let decoded = try JSONValue.parse(encoded)

    #expect(decoded["strategy"].string == "copy")
    #expect(decoded["directory"].string == "/tmp/wt1")
    #expect(decoded["from"].string == "main")
    #expect(decoded["name"].string == "wt1")
  }

  @Test func worktreeErrorMappingExtractsUserMessage() throws {
    let rawError = """
      {
        "name": "WorktreeError",
        "data": {
          "message": "dirty tree",
          "forceRequired": true
        }
      }
      """
    let json = try JSONValue.parse(Data(rawError.utf8))
    let error = try #require(WorktreeRequestBuilder.error(from: json))

    #expect(error.userMessage.contains("dirty tree"))
    #expect(error.message == "dirty tree")
  }

  @Test func apiCacheTtlExpiryAndInvalidateAll() {
    let cache = APICache()
    let key = "GET|/api/worktree/p1|"
    let testData = Data("hello".utf8)

    cache.put(key, data: testData, ttl: 0.05)
    #expect(cache.get(key) == testData)

    Thread.sleep(forTimeInterval: 0.08)
    #expect(cache.get(key) == nil)

    cache.put(key, data: testData, ttl: 10.0)
    #expect(cache.get(key) == testData)

    cache.invalidateAll()
    #expect(cache.get(key) == nil)
  }

  @Test func mcpUrlsFormatPutAndDeleteCorrectly() throws {
    let client = makeClient()
    let serverName = "my/custom mcp"

    let addReq = McpRequestBuilder.addRequest(name: serverName)
    let putUrl = try client.url(addReq.path)
    #expect(putUrl.absoluteString == "http://127.0.0.1:4100/api/mcp/my%2Fcustom%20mcp")
    #expect(addReq.method == "PUT")

    let removeReq = McpRequestBuilder.removeRequest(name: serverName)
    let deleteUrl = try client.url(removeReq.path)
    #expect(deleteUrl.absoluteString == "http://127.0.0.1:4100/api/mcp/my%2Fcustom%20mcp")
    #expect(removeReq.method == "DELETE")
  }
}
