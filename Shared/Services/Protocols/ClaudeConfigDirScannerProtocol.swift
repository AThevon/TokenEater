import Foundation

/// Finds the Claude Code config folders a user may want to track, without
/// reading a credential. Only the add-account sheet and the main account's
/// folder picker call it, and only while they are on screen: nothing scans
/// at launch.
protocol ClaudeConfigDirScannerProtocol: Sendable {
    /// The `~/.claude-*` folders (and `~/.claude` itself) that look like a
    /// Claude Code config folder, most recently used first, minus the ones
    /// already tracked.
    func candidates(excluding trackedPaths: Set<String>) -> [ConfigDirCandidate]
    /// The same facts for one folder the user picked by hand.
    func inspect(path: String) -> ConfigDirCandidate
}
