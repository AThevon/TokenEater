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

    @Test("parses streaming (stop_reason null) as thinking")
    func parsesStreaming() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.assistantStreaming)
        #expect(result?.state == .thinking)
    }

    @Test("parses user text message as thinking")
    func parsesUserMessage() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.userMessage)
        #expect(result?.state == .thinking)
    }

    @Test("parses user tool_result as thinking")
    func parsesUserToolResult() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.userToolResult)
        #expect(result?.state == .thinking)
    }

    @Test("parses progress heartbeat as thinking")
    func parsesProgressHeartbeat() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.progressHeartbeat)
        #expect(result?.state == .thinking)
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

    @Test("fresh session with only system init returns idle")
    func freshSessionReturnsIdle() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.freshSessionInitOnly)
        #expect(result != nil)
        #expect(result?.state == .idle)
        #expect(result?.sessionId == "fresh-001")
        #expect(result?.projectPath == "/Users/test/projects/MyApp")
        #expect(result?.gitBranch == "main")
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

    @Test("tool_use with pending enqueue → waiting")
    func parsesWaiting() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.assistantToolUseWithEnqueue)
        #expect(result?.state == .waiting)
    }

    @Test("tool_use with enqueue then remove → toolExec (permission resolved)")
    func parsesResolvedPermission() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.assistantToolUseWithEnqueueThenRemove)
        #expect(result?.state == .toolExec)
    }

    @Test("progress agent_progress → subagent")
    func parsesSubagent() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.progressAgentProgress)
        #expect(result?.state == .subagent)
    }

    @Test("system compact_boundary → idle")
    func parsesCompactBoundary() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.systemCompactBoundary)
        #expect(result?.state == .idle)
    }

    @Test("AskUserQuestion tool_use → waiting (no queue-operation needed)")
    func parsesAskUserQuestion() {
        let result = JSONLParser.parseLastState(from: SessionJSONLFixture.assistantAskUserQuestion)
        #expect(result?.state == .waiting)
    }
}
