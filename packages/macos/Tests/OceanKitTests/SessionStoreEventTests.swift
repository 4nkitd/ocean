import Testing
import OceanKit
@testable import OceanSession

@Suite("SessionStore event & helper logic")
@MainActor
struct SessionStoreEventTests {
  @Test func extractTodosFromTodowriteInput() throws {
    let jsonWire = """
    {
      "todos": [
        {"id": "todo-1", "content": "Fix question routes", "status": "completed"},
        {"id": "todo-2", "content": "Write test suite", "status": "in_progress"},
        {"id": "todo-3", "content": "Self verify", "status": "pending"}
      ]
    }
    """
    let json = try JSONValue.parse(Data(jsonWire.utf8))
    let todos = SessionStore.extractTodos(from: json)

    #expect(todos.count == 3)
    #expect(todos[0].id == "todo-1")
    #expect(todos[0].content == "Fix question routes")
    #expect(todos[0].status == TodoStatus.completed)

    #expect(todos[1].id == "todo-2")
    #expect(todos[1].content == "Write test suite")
    #expect(todos[1].status == TodoStatus.in_progress)

    #expect(todos[2].id == "todo-3")
    #expect(todos[2].content == "Self verify")
    #expect(todos[2].status == TodoStatus.pending)
  }

  @Test func extractTodosReturnsEmptyArrayForInvalidInput() throws {
    let emptyJson = try JSONValue.parse(Data("{}".utf8))
    #expect(SessionStore.extractTodos(from: emptyJson).isEmpty)

    let invalidJson = try JSONValue.parse(Data(#"{"todos": "not-an-array"}"#.utf8))
    #expect(SessionStore.extractTodos(from: invalidJson).isEmpty)
  }

  @Test func optimisticEchoReconciliationMatch() {
    let matched = SessionStore.isOptimisticMatch(
      draftText: "hello world",
      draftAttachmentsCount: 1,
      timeCreated: 10000,
      serverText: "hello world",
      serverFilesCount: 1,
      serverTimeCreated: 12000
    )
    #expect(matched)
  }

  @Test func optimisticEchoReconciliationMismatchText() {
    let matched = SessionStore.isOptimisticMatch(
      draftText: "hello world",
      draftAttachmentsCount: 1,
      timeCreated: 10000,
      serverText: "different text",
      serverFilesCount: 1,
      serverTimeCreated: 12000
    )
    #expect(!matched)
  }

  @Test func optimisticEchoReconciliationMismatchTime() {
    // Server created before draft - 5000ms window
    let matched = SessionStore.isOptimisticMatch(
      draftText: "hello world",
      draftAttachmentsCount: 0,
      timeCreated: 20000,
      serverText: "hello world",
      serverFilesCount: 0,
      serverTimeCreated: 10000
    )
    #expect(!matched)
  }
}
