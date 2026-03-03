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
}
