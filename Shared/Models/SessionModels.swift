import Foundation

enum SessionState: String, Sendable {
    case idle
    case thinking
    case toolExec
    case waiting
    case subagent
    case compacting
}

struct ClaudeSession: Identifiable, Sendable {
    let id: String
    let projectPath: String
    var projectName: String { URL(fileURLWithPath: projectPath).lastPathComponent }
    var gitBranch: String?
    var model: String?
    var state: SessionState
    var lastUpdate: Date
    var startedAt: Date
    var processPid: Int32?

    var isStale: Bool { Date().timeIntervalSince(lastUpdate) > 10 }
    var isDead: Bool { processPid == nil && Date().timeIntervalSince(lastUpdate) > 60 }
}
