import Testing

@testable import OceanKit

@Suite("Part keys")
struct PartKeyTests {
  @Test func ordinalKeys() throws {
    #expect(PartKey.ordinal(messageID: "msg_1", ordinal: 3).rawValue == "msg_1:3")
    let parsed = try #require(PartKey(rawValue: "msg_1:3"))
    #expect(parsed == .ordinal(messageID: "msg_1", ordinal: 3))
    #expect(parsed.messageID == "msg_1")
  }

  @Test func toolKeys() {
    let key = PartKey.tool(messageID: "msg_1", callID: "toolu_01Y7DWpWBQATbUoZh2X4S9r7")
    #expect(key.rawValue == "msg_1:tool:toolu_01Y7DWpWBQATbUoZh2X4S9r7")
    #expect(PartKey(rawValue: key.rawValue) == key)
  }

  @Test func fileAndPlainTextKeys() {
    #expect(PartKey(rawValue: "msg_1:file:0") == .file(messageID: "msg_1", index: 0))
    #expect(PartKey(rawValue: "msg_1:text") == .text(messageID: "msg_1"))
    #expect(PartKey.text(messageID: "msg_1").rawValue == "msg_1:text")
  }

  @Test func rubbishIsNotAKey() {
    #expect(PartKey(rawValue: "msg_1") == nil)
    #expect(PartKey(rawValue: "msg_1:") == nil)
    #expect(PartKey(rawValue: ":3") == nil)
    #expect(PartKey(rawValue: "msg_1:banana") == nil)
    #expect(PartKey(rawValue: "msg_1:tool:") == nil)
    #expect(PartKey(rawValue: "msg_1:file:x") == nil)
    #expect(PartKey(rawValue: "") == nil)
  }

  /// The keys `toMessage` mints have to be the ones a delta can reconstruct, or
  /// a streaming update lands on nothing.
  @Test func keysMintedByToMessageRoundTrip() throws {
    let wire = """
      {"id":"msg_1","type":"assistant","time":{"created":1},
       "content":[
         {"type":"text","text":"thinking out loud"},
         {"type":"tool","id":"toolu_9","name":"read","state":{"status":"completed",
          "input":{"filePath":"/x"},"content":[{"type":"text","text":"ok"}]}},
         {"type":"reasoning","text":"hmm"}
       ]}
      """
    let message = try #require(toMessage(JSONValue.parse(Data(wire.utf8)), sessionID: "ses_1"))

    #expect(message.parts.map(\.id) == ["msg_1:0", "msg_1:tool:toolu_9", "msg_1:2"])
    #expect(message.parts.map(\.ordinal) == [0, 1, 2])
    #expect(PartKey(rawValue: message.parts[0].id) == .ordinal(messageID: "msg_1", ordinal: 0))
    #expect(PartKey(rawValue: message.parts[1].id) == .tool(messageID: "msg_1", callID: "toolu_9"))
    #expect(message.parts[1].state?.status == .completed)
    #expect(message.parts[2].type == .reasoning)
  }

  /// A user prompt carries its text on the message, not in `content`, and its
  /// attachments alongside — real shapes taken off the live server.
  @Test func userPromptPartsAreKeyedSeparately() throws {
    let wire = """
      {"id":"msg_2","type":"user","time":{"created":1},"text":"look at this",
       "files":[{"name":"shot.png","mime":"image/png","data":"AAAA"}]}
      """
    let message = try #require(toMessage(JSONValue.parse(Data(wire.utf8)), sessionID: "ses_1"))
    #expect(message.parts.map(\.id) == ["msg_2:file:0", "msg_2:text"])
    #expect(message.parts[0].url == "data:image/png;base64,AAAA")
    #expect(message.parts[1].text == "look at this")
    #expect(message.info.role == .user)
  }
}
