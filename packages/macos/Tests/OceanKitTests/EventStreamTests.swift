import Testing

@testable import OceanKit

/// The SSE wire format, as `opencode serve` actually emits it: `data: {…}\n\n`
/// frames with `: heartbeat\n\n` comments in between.
@Suite("SSE parser")
struct SSEParserTests {
  private func consume(_ parser: inout SSEParser, _ text: String) -> [String] {
    parser.consume(Array(text.utf8))
  }

  @Test func oneFramePerBlankLine() {
    var parser = SSEParser()
    let frames = consume(&parser, "data: {\"a\":1}\n\ndata: {\"a\":2}\n\n")
    #expect(frames == [#"{"a":1}"#, #"{"a":2}"#])
  }

  @Test func commentsAreDropped() {
    var parser = SSEParser()
    // Straight off the wire, heartbeats and all.
    let frames = consume(
      &parser,
      "data: {\"type\":\"server.connected\"}\n\n: heartbeat\n\ndata: {\"type\":\"x\"}\n\n")
    #expect(frames == [#"{"type":"server.connected"}"#, #"{"type":"x"}"#])
  }

  @Test func aFrameSplitAcrossChunksIsHeldUntilItIsWhole() {
    var parser = SSEParser()
    #expect(consume(&parser, "data: {\"ty").isEmpty)
    #expect(consume(&parser, "pe\":\"x\"}").isEmpty)
    #expect(consume(&parser, "\n").isEmpty)
    #expect(consume(&parser, "\n") == [#"{"type":"x"}"#])
  }

  @Test func multipleDataLinesJoinWithNewlines() {
    var parser = SSEParser()
    #expect(consume(&parser, "data: one\ndata: two\n\n") == ["one\ntwo"])
  }

  @Test func carriageReturnsFoldToNewlinesEvenAcrossAChunkBoundary() {
    var parser = SSEParser()
    #expect(consume(&parser, "data: one\r").isEmpty)
    #expect(consume(&parser, "\n\r\n") == ["one"])
    #expect(consume(&parser, "data: two\r\r") == ["two"])
  }

  @Test func eventAndIdLinesAreIgnored() {
    var parser = SSEParser()
    #expect(consume(&parser, "id: 7\nevent: message\ndata: body\n\n") == ["body"])
  }

  @Test func emptyFramesYieldNothing() {
    var parser = SSEParser()
    #expect(consume(&parser, "\n\n\n\n").isEmpty)
    #expect(consume(&parser, "data:\n\n").isEmpty)
  }

  @Test func flushReturnsAFrameTheServerNeverClosed() {
    var parser = SSEParser()
    #expect(consume(&parser, "data: half").isEmpty)
    #expect(parser.flush() == "half")
    #expect(parser.flush() == nil)
  }

  @Test func realFrameParsesIntoAServerEvent() throws {
    var parser = SSEParser()
    // Copied verbatim from `curl -N /api/event` against the live server.
    let wire = """
      data: {"id":"evt_1","created":1786688547111,"type":"session.step.started",\
      "durable":{"aggregateID":"ses_1","seq":473,"version":1},\
      "location":{"directory":"/Users/ravi/dev/ocean"},\
      "data":{"sessionID":"ses_1","assistantMessageID":"msg_1","agent":"build"}}\n\n
      """
    let payloads = consume(&parser, wire)
    #expect(payloads.count == 1)

    let event = try #require(normaliseServerEvent(JSONValue.parse(Data(payloads[0].utf8))))
    #expect(event.type == "session.step.started")
    #expect(event.id == "evt_1")
    #expect(event.directory == "/Users/ravi/dev/ocean")
    #expect(event.sessionID == "ses_1")
    #expect(event["assistantMessageID"].string == "msg_1")
  }

  @Test func formCreatedCarriesItsSessionInsideThePayload() throws {
    let json = try JSONValue.parse(
      Data(#"{"type":"form.created","data":{"form":{"id":"f1","sessionID":"ses_9"}}}"#.utf8))
    #expect(try #require(normaliseServerEvent(json)).sessionID == "ses_9")
  }

  @Test func aFrameWithoutATypeIsNotAnEvent() throws {
    #expect(normaliseServerEvent(try JSONValue.parse(Data(#"{"id":"evt_1","data":{}}"#.utf8))) == nil)
    #expect(normaliseServerEvent(.string("hello")) == nil)
  }

  @Test func aDatalessFrameStillCarriesItsType() throws {
    let event = try #require(
      normaliseServerEvent(
        try JSONValue.parse(Data(#"{"type":"server.connected","data":{}}"#.utf8))))
    #expect(event.type == "server.connected")
    #expect(event.data.isEmpty)
  }
}
