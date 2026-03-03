import Testing
import Foundation

@Suite("JSONLParser")
struct JSONLParserTests {

    @Test("parses end_turn as idle")
    func parsesEndTurn() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.assistantEndTurn)
        #expect(result?.state == .idle)
        #expect(result?.sessionId == "abc-123")
        #expect(result?.projectPath == "/Users/test/projects/MyApp")
        #expect(result?.gitBranch == "main")
        #expect(result?.model == "claude-opus-4-6")
    }

    @Test("parses tool_use as toolExec")
    func parsesToolUse() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.assistantToolUse)
        #expect(result?.state == .toolExec)
        #expect(result?.gitBranch == "feat/overlay")
        #expect(result?.model == "claude-sonnet-4-6")
    }

    @Test("parses streaming (stop_reason null) as working")
    func parsesStreaming() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.assistantStreaming)
        #expect(result?.state == .working)
    }

    @Test("parses user text message as working")
    func parsesUserMessage() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.userMessage)
        #expect(result?.state == .working)
    }

    @Test("parses user tool_result as working")
    func parsesUserToolResult() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.userToolResult)
        #expect(result?.state == .working)
    }

    @Test("parses progress heartbeat as working")
    func parsesProgressHeartbeat() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.progressHeartbeat)
        #expect(result?.state == .working)
    }

    @Test("skips system messages, reads previous meaningful event")
    func skipsSystemMessages() {
        let lines = SessionJSONLFixture.assistantEndTurn + "\n" + SessionJSONLFixture.systemMessage
        let result = JSONLParser.parseLastState(from: lines)
        #expect(result?.state == .idle)
    }

    @Test("full session ends idle")
    func fullSessionEndsIdle() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.fullSession)
        #expect(result?.state == .idle)
    }

    @Test("working session ends toolExec")
    func workingSessionEndsToolExec() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.workingSession)
        #expect(result?.state == .toolExec)
    }

    @Test("empty string returns nil")
    func emptyStringReturnsNil() {
        let result = JSONLParser.parseLastState(from: "")
        #expect(result == nil)
    }

    @Test("parses timestamp correctly")
    func parsesTimestamp() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.assistantEndTurn)
        #expect(result != nil)
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: result!.timestamp)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 3)
    }
}
