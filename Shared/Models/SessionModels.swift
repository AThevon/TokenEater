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

    var gitBranch: String?

    /// Branch to display in the UI - nil for default branches (main/master/HEAD)
    var visibleBranch: String? {
        guard let branch = gitBranch,
              branch != "main", branch != "master", branch != "HEAD" else { return nil }
        return branch
    }

    /// Title for branch-priority mode: shows branch when non-default, otherwise project name
    var displayName: String {
        visibleBranch ?? projectName
    }
    var model: String?
    var state: SessionState
    var lastUpdate: Date
    var startedAt: Date
    var processPid: Int32?
    var sourceKind: SessionSourceKind = .unknown

    /// Current context window size in tokens (sum of input + cache_creation +
    /// cache_read + output from the most recent assistant turn). Nil until the
    /// session has produced at least one assistant response.
    var contextTokens: Int?

    /// Max context window capacity in tokens for the session's model. Defaults
    /// to 200k; `[1m]` model variants return 1M. Only meaningful alongside
    /// `contextTokens`.
    var contextMax: Int?

    /// Ratio 0.0 - 1.0 of the context window consumed. Nil when context data
    /// isn't available yet. The `activeSessionsTrait` UI uses this to drive
    /// the per-tile progress indicator on both Frost and Neon themes.
    var contextFraction: Double? {
        guard let tokens = contextTokens, let max = contextMax, max > 0 else { return nil }
        return min(Double(tokens) / Double(max), 1.0)
    }

    var isStale: Bool { Date().timeIntervalSince(lastUpdate) > 10 }
    var isDead: Bool { processPid == nil && Date().timeIntervalSince(lastUpdate) > 60 }
}
