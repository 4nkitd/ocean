import Testing
@testable import OceanKit

@Suite("Question and Permission routes")
struct QuestionRouteTests {
  private func client() -> OpenCodeClient {
    OpenCodeClient(credentials: ServerCredentials(url: "127.0.0.1:4100", password: "secret"))
  }

  @Test func listQuestionsUrlPath() throws {
    let url = try client().url("/session/ses_abc123/question")
    #expect(url.absoluteString == "http://127.0.0.1:4100/api/session/ses_abc123/question")
  }

  @Test func replyQuestionUrlPath() throws {
    let url = try client().url("/session/ses_abc123/question/que_456/reply")
    #expect(url.absoluteString == "http://127.0.0.1:4100/api/session/ses_abc123/question/que_456/reply")
  }

  @Test func rejectQuestionUrlPath() throws {
    let url = try client().url("/session/ses_abc123/question/que_456/reject")
    #expect(url.absoluteString == "http://127.0.0.1:4100/api/session/ses_abc123/question/que_456/reject")
  }

  @Test func listPermissionsUrlPath() throws {
    let url = try client().url("/session/ses_abc123/permission")
    #expect(url.absoluteString == "http://127.0.0.1:4100/api/session/ses_abc123/permission")
  }

  @Test func replyPermissionUrlPath() throws {
    let url = try client().url("/session/ses_abc123/permission/per_789/reply")
    #expect(url.absoluteString == "http://127.0.0.1:4100/api/session/ses_abc123/permission/per_789/reply")
  }
}
