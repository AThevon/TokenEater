import Foundation

enum SessionState: String, Sendable {
    case idle
    case working
    case toolExec
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

    var isStale: Bool { Date().timeIntervalSince(lastUpdate) > 10 }
    var isDead: Bool { Date().timeIntervalSince(lastUpdate) > 60 }
}
