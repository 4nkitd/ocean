import Testing
import OceanKit
@testable import OceanSession

@Suite("MCP store & server model")
struct McpStoreTests {
  @Test func mcpServerJsonParsingConnected() throws {
    let wire = """
    {
      "name": "git-mcp",
      "status": {
        "status": "connected"
      }
    }
    """
    let json = try JSONValue.parse(Data(wire.utf8))
    let server = try #require(McpServer(json: json))

    #expect(server.name == "git-mcp")
    #expect(server.status == .connected)
    #expect(server.error == nil)
  }

  @Test func mcpServerJsonParsingFailedWithError() throws {
    let wire = """
    {
      "name": "filesystem",
      "status": {
        "status": "failed",
        "error": "command npx not found"
      }
    }
    """
    let json = try JSONValue.parse(Data(wire.utf8))
    let server = try #require(McpServer(json: json))

    #expect(server.name == "filesystem")
    #expect(server.status == .failed)
    #expect(server.error == "command npx not found")
  }

  @Test func mcpServerJsonParsingDisabled() throws {
    let wire = """
    {
      "name": "puppeteer",
      "status": {
        "status": "disabled"
      }
    }
    """
    let json = try JSONValue.parse(Data(wire.utf8))
    let server = try #require(McpServer(json: json))

    #expect(server.name == "puppeteer")
    #expect(server.status == .disabled)
  }

  @MainActor
  @Test func mcpStoreOptimisticUpdateState() {
    let store = McpStore()
    #expect(store.servers == nil)
    #expect(!store.loading)
    #expect(store.pending.isEmpty)
  }
}
