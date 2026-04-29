import Foundation

/// Reads `~/.claude/projects/**/*.jsonl` and produces aggregated history
/// buckets. Implementations must be cancellable and persist a cache so the
/// repeated UI-driven loads stay cheap.
protocol SessionHistoryServiceProtocol: Sendable {
    /// Loads buckets covering the requested range. Implementations should
    /// honour `Task.checkCancellation()` so a fast range switch doesn't waste
    /// CPU on an obsolete scan.
    func loadHistory(range: HistoryRange) async throws -> [HistoryBucket]

    /// Loads the equivalent previous-period total active tokens (used by the
    /// hero delta). Returns 0 if there is no data older than the current range
    /// start.
    func loadPreviousPeriodActiveTokens(range: HistoryRange) async throws -> Int
}
