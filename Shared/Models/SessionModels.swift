import Foundation

enum SessionState: String, Sendable {
    case idle
    case thinking
    case toolExec
    case waiting
    case subagent
    case compacting
}

enum SessionSourceKind: Sendable {
    case terminal
    case ide
    case unknown
}

struct ClaudeSession: Identifiable, Sendable {
    let id: String
    let projectPath: String
    var projectName: String { URL(fileURLWithPath: projectPath).lastPathComponent }

    var displayName: String {
        if let branch = gitBranch, branch != "main", branch != "master", branch != "HEAD" {
            return branch
        }
        return projectName
    }
    var gitBranch: String?
    var model: String?
    var state: SessionState
    var lastUpdate: Date
    var startedAt: Date
    var processPid: Int32?
    var sourceKind: SessionSourceKind = .unknown

    var isStale: Bool { Date().timeIntervalSince(lastUpdate) > 10 }
    var isDead: Bool { processPid == nil && Date().timeIntervalSince(lastUpdate) > 60 }
}
