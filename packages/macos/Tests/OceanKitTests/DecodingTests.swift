import Testing

@testable import OceanKit

@Suite("Loose JSON")
struct JSONValueTests {
  @Test func readsMissingKeysAsNull() throws {
    let json = try JSONValue.parse(Data(#"{"a":{"b":1}}"#.utf8))
    #expect(json["a"]["b"].int == 1)
    #expect(json["a"]["nope"]["deeper"].isNull)
    #expect(json["nope"].string == nil)
  }

  @Test func treatsEmptyStringsAsAbsent() throws {
    let json = try JSONValue.parse(Data(#"{"a":"","b":"x"}"#.utf8))
    #expect(json["a"].string == nil)
    #expect(json["b"].string == "x")
  }

  @Test func keepsBooleansAndNumbersApart() throws {
    let json = try JSONValue.parse(Data(#"{"flag":true,"count":2}"#.utf8))
    #expect(json["flag"].bool == true)
    #expect(json["flag"].double == nil)
    #expect(json["count"].int == 2)
    #expect(json["count"].bool == nil)
  }

  @Test func survivesNullsWhereObjectsWereExpected() throws {
    let json = try JSONValue.parse(Data(#"[{"id":"a"},null,{"id":"b"},{"nope":1}]"#.utf8))
    let ids = json.array.compactMap { $0["id"].string }
    #expect(ids == ["a", "b"])
  }
}

@Suite("Messages")
struct MessageTests {
  @Test func flattensAUserPrompt() throws {
    let json = try JSONValue.parse(
      Data(
        #"{"id":"msg_1","type":"user","time":{"created":10},"text":"hello","files":[{"name":"a.png","mime":"image/png","data":"AAA"}]}"#
          .utf8))
    let message = try #require(toMessage(json, sessionID: "ses_1"))
    #expect(message.info.role == .user)
    #expect(message.info.kind == "user")
    #expect(message.info.timeCreated == 10)
    #expect(message.parts.count == 2)
    #expect(message.parts[0].type == .file)
    #expect(message.parts[0].url == "data:image/png;base64,AAA")
    #expect(message.parts[1].type == .text)
    #expect(message.parts[1].text == "hello")
    #expect(message.parts[1].id == "msg_1:text")
  }

  @Test func keysPartsTheWayDeltasAddressThem() throws {
    let json = try JSONValue.parse(
      Data(
        """
        {"id":"msg_2","type":"assistant","time":{"created":1,"completed":2},
         "agent":"build","model":{"id":"m","providerID":"p","variant":"high"},
         "content":[
           {"type":"reasoning","text":"why"},
           {"type":"tool","id":"call_9","name":"shell",
            "time":{"created":5,"completed":9},
            "state":{"status":"completed","input":{"command":"ls"},
                     "content":[{"type":"text","text":"out"}],
                     "metadata":{"title":"ls"}}}
         ]}
        """.utf8))
    let message = try #require(toMessage(json, sessionID: "ses_1"))
    #expect(message.info.role == .assistant)
    #expect(message.info.modelID == "m")
    #expect(message.info.variant == "high")
    #expect(message.parts[0].id == "msg_2:0")
    #expect(message.parts[0].type == .reasoning)
    #expect(message.parts[1].id == "msg_2:tool:call_9")
    #expect(message.parts[1].callID == "call_9")
    #expect(message.parts[1].ordinal == 1)

    let state = try #require(message.parts[1].state)
    #expect(state.status == .completed)
    #expect(state.title == "ls")
    #expect(state.input?["command"]?.string == "ls")
    if case .completed(let completed) = state {
      #expect(completed.output == "out")
      #expect(completed.time == ToolTime(start: 5, end: 9))
    } else {
      Issue.record("expected a completed tool state")
    }
  }

  @Test func labelsEverythingElseAsASystemNote() throws {
    for kind in ["compaction", "skill", "agent-switched", "something-new"] {
      let json = try JSONValue.parse(
        Data(#"{"id":"m","type":"\#(kind)","time":{"created":1},"summary":"note"}"#.utf8))
      let message = try #require(toMessage(json, sessionID: "s"))
      #expect(message.info.role == .system)
      #expect(message.info.kind == kind)
      #expect(message.parts.first?.text == "note")
    }
  }

  @Test func aMissingIdDropsOneMessageAndNotTheList() throws {
    let json = try JSONValue.parse(
      Data(#"[{"type":"user","time":{"created":1}},{"id":"ok","type":"user","time":{"created":2}}]"#.utf8))
    let messages = json.array.compactMap { toMessage($0, sessionID: "s") }
    #expect(messages.count == 1)
    #expect(messages[0].info.id == "ok")
  }

  @Test func readsAFailedTool() throws {
    let json = try JSONValue.parse(
      Data(#"{"type":"tool","id":"c","name":"edit","state":{"status":"error","error":{"message":"nope"}}}"#.utf8))
    let state = toToolState(json)
    #expect(state.status == .error)
    if case .error(let failed) = state {
      #expect(failed.error == "nope")
    } else {
      Issue.record("expected an error tool state")
    }
  }

  @Test func aStateFreeToolIsPending() throws {
    let json = try JSONValue.parse(Data(#"{"type":"tool","id":"c","name":"edit"}"#.utf8))
    #expect(toToolState(json).status == .pending)
  }

  @Test func joinsToolOutputBlocks() throws {
    let json = try JSONValue.parse(
      Data(#"[{"type":"text","text":"a"},{"type":"file","name":"b.txt"},{"type":"other"}]"#.utf8))
    #expect(toolOutput(json) == "a\nb.txt")
  }
}

@Suite("Forms")
struct FormTests {
  @Test func readsEveryFieldKind() throws {
    let json = try JSONValue.parse(
      Data(
        """
        {"id":"f1","sessionID":"s1","title":"Details","fields":[
          {"key":"name","type":"string","required":true,"placeholder":"you"},
          {"key":"age","type":"integer","minimum":0,"maximum":120,"default":30},
          {"key":"ok","type":"boolean","default":true},
          {"key":"tags","type":"multiselect","options":[{"value":"a"},{"value":"b","label":"Bee"}]},
          {"key":"link","type":"external","url":"https://example.com"}
        ]}
        """.utf8))
    let form = try #require(toFormRequest(json))
    #expect(form.title == "Details")
    #expect(form.fields.map(\.type) == ["string", "integer", "boolean", "multiselect", "external"])
    #expect(form.fields[0].base.required)

    guard case .multiselect(let field) = form.fields[3] else {
      Issue.record("expected a multiselect")
      return
    }
    #expect(field.options.map(\.label) == ["a", "Bee"])
  }

  @Test func fallsBackToTextForAnUnknownKind() throws {
    let json = try JSONValue.parse(
      Data(#"{"id":"f","sessionID":"s","fields":[{"key":"k","type":"colour-picker"}]}"#.utf8))
    let form = try #require(toFormRequest(json))
    #expect(form.fields[0].type == "string")
  }

  @Test func anEmptyMultiselectBecomesTextSoItCanBeAnswered() throws {
    let json = try JSONValue.parse(
      Data(#"{"id":"f","sessionID":"s","fields":[{"key":"k","type":"multiselect","options":[]}]}"#.utf8))
    let form = try #require(toFormRequest(json))
    #expect(form.fields[0].type == "string")
  }

  @Test func aFormWithNoUsableFieldsIsNotAForm() throws {
    #expect(toFormRequest(try JSONValue.parse(Data(#"{"id":"f","sessionID":"s","fields":[]}"#.utf8))) == nil)
    #expect(toFormRequest(try JSONValue.parse(Data(#"{"id":"f","fields":[{"key":"k"}]}"#.utf8))) == nil)
  }

  @Test func conditionsDecideWhatIsAsked() throws {
    let json = try JSONValue.parse(
      Data(
        """
        {"id":"f","sessionID":"s","fields":[
          {"key":"kind","type":"string"},
          {"key":"port","type":"integer","when":[{"key":"kind","op":"eq","value":"tcp"}]},
          {"key":"note","type":"string","when":[{"key":"kind","op":"neq","value":"tcp"}]}
        ]}
        """.utf8))
    let form = try #require(toFormRequest(json))
    let answers: FormAnswer = ["kind": .string("tcp")]
    #expect(form.fields[0].isActive(in: answers))
    #expect(form.fields[1].isActive(in: answers))
    #expect(!form.fields[2].isActive(in: answers))
    #expect(!form.fields[1].isActive(in: ["kind": .string("udp")]))
  }

  @Test func numbersGoOutAsNumbers() throws {
    let answer: FormAnswer = ["n": .number(2), "s": .string("x"), "b": .boolean(true)]
    let body = JSONValue.object(answer.mapValues(\.jsonValue))
    let text = String(decoding: try body.encoded(), as: UTF8.self)
    #expect(text.contains("\"n\":2"))
    #expect(!text.contains("\"2\""))
  }
}

@Suite("Sessions, projects, models")
struct EntityTests {
  @Test func readsASession() throws {
    let json = try JSONValue.parse(
      Data(
        #"{"id":"ses_1","projectID":"p","agent":"build","model":{"id":"m","providerID":"pr","variant":"high"},"cost":1.5,"tokens":{"input":1,"cache":{"read":2}},"time":{"created":10,"updated":20},"title":"t","location":{"directory":"/repo"}}"#
          .utf8))
    let session = try #require(Session(json: json))
    #expect(session.directory == "/repo")
    #expect(session.model?.modelID == "m")
    #expect(session.model?.ref == ModelRef(providerID: "pr", modelID: "m", variant: "high"))
    #expect(session.tokens?.cache?.read == 2)
    #expect(session.timeUpdated == 20)
    #expect(!isHiddenSession(session))
  }

  @Test func hidesSubagentSessions() throws {
    let json = try JSONValue.parse(Data(#"{"id":"a","parentID":"b","time":{"created":1,"updated":1}}"#.utf8))
    #expect(isHiddenSession(try #require(Session(json: json))))
  }

  @Test func readsAProject() throws {
    let json = try JSONValue.parse(
      Data(#"{"id":"p","canonical":"/repo","vcs":"git","time":{"created":1},"sandboxes":[]}"#.utf8))
    let project = try #require(Project(json: json))
    #expect(project.worktree == "/repo")
    #expect(project.isGit)
    #expect(project.directories == ["/repo"])
  }

  @Test func readsModelCapabilities() throws {
    let json = try JSONValue.parse(
      Data(
        #"{"id":"m","modelID":"m","providerID":"p","name":"M","capabilities":{"tools":true,"input":["text","image","pdf"],"output":["text"]},"variants":[{"id":"low"},{"id":"high"}],"enabled":true,"status":"active"}"#
          .utf8))
    let model = try #require(ModelInfo(json: json))
    #expect(model.capabilities.input == ["text", "image", "pdf"])
    #expect(model.capabilities.acceptsImages)
    #expect(model.capabilities.acceptsPDFs)
    #expect(model.capabilities.tools)
    #expect(model.variants == ["low", "high"])
  }

  @Test func acceptsBareStringVariantsFromOlderBuilds() throws {
    let json = try JSONValue.parse(
      Data(#"{"id":"m","providerID":"p","variants":["low","high"]}"#.utf8))
    #expect(try #require(ModelInfo(json: json)).variants == ["low", "high"])
  }

  @Test func aModelWithoutAProviderIsUnusable() throws {
    #expect(ModelInfo(json: try JSONValue.parse(Data(#"{"id":"m"}"#.utf8))) == nil)
  }

  @Test func narrowsMcpStatus() throws {
    let json = try JSONValue.parse(
      Data(
        #"[{"name":"a","status":{"status":"connected"}},{"name":"b","status":{"status":"failed","error":"boom"}},{"name":"c","status":{"status":"weird"}}]"#
          .utf8))
    let servers = json.array.compactMap(McpServer.init(json:))
    #expect(servers.map(\.status) == [.connected, .failed, .disabled])
    #expect(servers[1].error == "boom")
  }

  @Test func readsAnInboxItem() throws {
    let json = try JSONValue.parse(
      Data(
        #"{"id":"i","sessionID":"s","timeCreated":5,"delivery":"steer","payload":{"text":"go","files":[1,2]}}"#
          .utf8))
    let item = try #require(toInboxItem(json))
    #expect(item.delivery == .steer)
    #expect(item.text == "go")
    #expect(item.attachments == 2)
    #expect(item.type == "user")
  }

  @Test func readsAPermissionRequest() throws {
    let json = try JSONValue.parse(
      Data(
        #"{"id":"pr","sessionID":"s","action":"edit","resources":["/a"],"save":["/a/*"],"source":{"type":"tool","messageID":"m","id":"c"}}"#
          .utf8))
    let request = try #require(PermissionRequest(json: json))
    #expect(request.action == "edit")
    #expect(request.resources == ["/a"])
    #expect(request.save == ["/a/*"])
    #expect(request.source?.id == "c")
  }

  @Test func readsAQuestion() throws {
    let json = try JSONValue.parse(
      Data(
        #"{"id":"q","sessionID":"s","questions":[{"question":"which?","options":[{"label":"a"},{"label":"b","description":"bee"}],"multiple":true}],"tool":{"messageID":"m","callID":"c"}}"#
          .utf8))
    let request = try #require(QuestionRequest(json: json))
    #expect(request.questions.count == 1)
    #expect(request.questions[0].multiple)
    #expect(request.questions[0].options.map(\.label) == ["a", "b"])
    #expect(request.tool?.callID == "c")
  }
}

@Suite("Errors")
struct ErrorTests {
  @Test func distinguishesWhatTheUserShouldDo() {
    #expect(ApiError(.auth, "x").userMessage.contains("password"))
    #expect(ApiError(.notfound, "x").userMessage.contains("v2 API"))
    #expect(ApiError(.network, "x").userMessage.contains("opencode serve"))
    #expect(ApiError(.server, "x", status: 502).userMessage.contains("502"))
    #expect(ApiError(.unsupported, "This build has no forms.").userMessage == "This build has no forms.")
    #expect(ApiError(.aborted, "x").userMessage == "Cancelled.")
  }

  @Test func knowsWhatIsWorthRetrying() {
    #expect(ApiError(.network, "x").retryable)
    #expect(ApiError(.timeout, "x").retryable)
    #expect(ApiError(.server, "x").retryable)
    #expect(!ApiError(.auth, "x").retryable)
    #expect(!ApiError(.notfound, "x").retryable)
  }

  @Test func turnsAnythingIntoCopy() {
    #expect(toUserMessage(ApiError(.auth, "x")).contains("password"))
    #expect(toUserMessage(CancellationError()) == "Cancelled.")
    #expect(toUserMessage(URLError(.cannotFindHost)).contains("opencode serve"))
  }

  @Test func mapsUrlErrors() {
    #expect(apiError(from: URLError(.timedOut), url: nil).kind == .timeout)
    #expect(apiError(from: URLError(.cancelled), url: nil).kind == .aborted)
    #expect(apiError(from: URLError(.notConnectedToInternet), url: nil).kind == .network)
  }
}
