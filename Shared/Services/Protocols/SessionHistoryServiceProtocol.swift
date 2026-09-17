import Foundation

/// Reads local session logs and produces aggregated history
/// buckets. Implementations must be cancellable and persist a cache so the
/// repeated UI-driven loads stay cheap.
protocol SessionHistoryServiceProtocol: Sendable {
    /// Loads buckets covering the requested range. Implementations should
    /// honour `Task.checkCancellation()` so a fast range switch doesn't waste
    /// CPU on an obsolete scan.
    func loadHistory(range: HistoryRange) async throws -> [HistoryBucket]

    /// Loads the equivalent previous-period active tokens, split by provider
    /// (used by the hero delta). A provider with no data older than the
    /// current range start is absent from the dictionary rather than zero.
    ///
    /// The split exists because the delta is rendered next to a total the
    /// caller may have filtered to one provider: comparing a Claude-only
    /// total against a Claude + Codex previous total reports a collapse that
    /// never happened.
    func loadPreviousPeriodActiveTokens(range: HistoryRange) async throws -> [MetricProvider: Int]
}
