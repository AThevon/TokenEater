import Foundation

enum SessionJSONLFixture {
    static let assistantEndTurn = """
    {"type":"assistant","sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:00:00.000Z","message":{"role":"assistant","model":"claude-opus-4-6","stop_reason":"end_turn","content":[{"type":"text","text":"Done."}]}}
    """

    static let assistantToolUse = """
    {"type":"assistant","sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"feat/overlay","version":"2.1.59","timestamp":"2026-03-03T10:01:00.000Z","message":{"role":"assistant","model":"claude-sonnet-4-6","stop_reason":"tool_use","content":[{"type":"tool_use","id":"toolu_01","name":"Bash","input":{"command":"ls"}}]}}
    """

    static let assistantStreaming = """
    {"type":"assistant","sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:02:00.000Z","message":{"role":"assistant","model":"claude-opus-4-6","stop_reason":null,"content":[{"type":"thinking","thinking":"Let me think..."}]}}
    """

    static let userMessage = """
    {"type":"user","sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:03:00.000Z","message":{"role":"user","content":"Hello"}}
    """

    static let userToolResult = """
    {"type":"user","sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:04:00.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_01","content":"output"}]}}
    """

    static let progressHeartbeat = """
    {"type":"progress","sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:05:00.000Z"}
    """

    static let systemMessage = """
    {"type":"system","sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:06:00.000Z"}
    """

    static let fullSession: String = [
        userMessage, assistantStreaming, assistantToolUse, userToolResult, assistantEndTurn
    ].joined(separator: "\n")

    static let workingSession: String = [
        userMessage, assistantStreaming, assistantToolUse
    ].joined(separator: "\n")

    /// Fresh session: only a system init event, no user prompt yet
    static let freshSessionInitOnly = """
    {"type":"system","subtype":"init","sessionId":"fresh-001","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:00:00.000Z"}
    """

    /// tool_use + queue-operation enqueue (no remove) → .waiting
    static let assistantToolUseWithEnqueue: String = [
        """
        {"type":"assistant","sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:01:00.000Z","message":{"role":"assistant","model":"claude-opus-4-6","stop_reason":"tool_use","content":[{"type":"tool_use","id":"toolu_01","name":"Bash","input":{"command":"rm -rf /"}}]}}
        """,
        """
        {"type":"queue-operation","sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:01:01.000Z","operation":"enqueue"}
        """
    ].joined(separator: "\n")

    /// tool_use + enqueue + remove → .toolExec (permission resolved)
    static let assistantToolUseWithEnqueueThenRemove: String = [
        """
        {"type":"assistant","sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:01:00.000Z","message":{"role":"assistant","model":"claude-opus-4-6","stop_reason":"tool_use","content":[{"type":"tool_use","id":"toolu_01","name":"Bash","input":{"command":"ls"}}]}}
        """,
        """
        {"type":"queue-operation","sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:01:01.000Z","operation":"enqueue"}
        """,
        """
        {"type":"queue-operation","sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:01:02.000Z","operation":"remove"}
        """
    ].joined(separator: "\n")

    /// progress with agent_progress → .subagent
    static let progressAgentProgress = """
    {"type":"progress","sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:05:00.000Z","data":{"type":"agent_progress"}}
    """

    /// AskUserQuestion tool_use (no queue-operation) → .waiting
    static let assistantAskUserQuestion = """
    {"type":"assistant","sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:01:00.000Z","message":{"role":"assistant","model":"claude-opus-4-6","stop_reason":"tool_use","content":[{"type":"tool_use","id":"toolu_01","name":"AskUserQuestion","input":{"questions":[{"question":"Which approach?"}]}}]}}
    """

    /// Meta user message (`isMeta: true`): hook feedback, session notices.
    /// Claude Code writes these as `user` lines, but nobody typed them.
    static let metaUserMessage = """
    {"type":"user","isMeta":true,"sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:07:00.000Z","message":{"role":"user","content":"A session-scoped Stop hook is now active."}}
    """

    /// AskUserQuestion still on screen when an attachment and a meta user
    /// message land before the answer (#269) → .waiting
    static let assistantAskUserQuestionThenMetaMessage: String = [
        assistantAskUserQuestion,
        """
        {"type":"attachment","sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:06:59.000Z","attachment":{"type":"goal_status"}}
        """,
        metaUserMessage
    ].joined(separator: "\n")

    /// Same question, now answered: the tool_result lands last → .thinking
    static let assistantAskUserQuestionAnswered: String = [
        assistantAskUserQuestionThenMetaMessage,
        """
        {"type":"user","sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:08:00.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_01","content":"User answered"}]}}
        """
    ].joined(separator: "\n")

    /// Meta user message while a Bash tool is still running → .toolExec
    static let assistantToolUseThenMetaMessage: String = [
        assistantToolUse, metaUserMessage
    ].joined(separator: "\n")

    /// Meta user message after the turn ended (another session messaging this
    /// one): it opens a new turn → .thinking
    static let assistantEndTurnThenMetaMessage: String = [
        assistantEndTurn, metaUserMessage
    ].joined(separator: "\n")

    /// system compact_boundary → .idle
    static let systemCompactBoundary = """
    {"type":"system","subtype":"compact_boundary","sessionId":"abc-123","cwd":"/Users/test/projects/MyApp","gitBranch":"main","version":"2.1.59","timestamp":"2026-03-03T10:06:00.000Z"}
    """
}
