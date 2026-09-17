import Foundation

/// Claude history, plus Codex history when the user is tracking Codex.
///
/// Two rules the legs do not share. The Codex leg follows `codexEnabled`,
/// read at load time rather than at construction, so switching the toggle
/// takes effect on the next reload instead of requiring the store to be
/// rebuilt. And a failing Codex leg never takes Claude's data with it: local
/// log parsing can fail on a malformed rollout, and a user who does not even
/// use Codex should not lose their own History screen to it.
final class CombinedSessionHistoryService: SessionHistoryServiceProtocol {
    private let claude: SessionHistoryServiceProtocol
    private let codex: SessionHistoryServiceProtocol
    private let isCodexEnabled: () -> Bool

    init(
        claude: SessionHistoryServiceProtocol = SessionHistoryService(),
        codex: SessionHistoryServiceProtocol = SessionHistoryService(source: .codex),
        isCodexEnabled: @escaping () -> Bool = {
            UserDefaults.standard.object(forKey: "codexEnabled") as? Bool ?? false
        }
    ) {
        self.claude = claude
        self.codex = codex
        self.isCodexEnabled = isCodexEnabled
    }

    func loadHistory(range: HistoryRange) async throws -> [HistoryBucket] {
        async let claudeBuckets = claude.loadHistory(range: range)
        let codexBuckets = try await optionalCodex { try await self.codex.loadHistory(range: range) } ?? []
        let buckets = try await claudeBuckets + codexBuckets
        try Task.checkCancellation()
        return Dictionary(buckets.map { ($0.date, $0) }, uniquingKeysWith: {
            HistoryBucket.merging($0, $1, date: $0.date)
        }).values.sorted { $0.date < $1.date }
    }

    func loadPreviousPeriodActiveTokens(range: HistoryRange) async throws -> [MetricProvider: Int] {
        async let claudeTotals = claude.loadPreviousPeriodActiveTokens(range: range)
        let codexTotals = try await optionalCodex {
            try await self.codex.loadPreviousPeriodActiveTokens(range: range)
        } ?? [:]
        return try await claudeTotals.merging(codexTotals) { $0 + $1 }
    }

    /// Runs a Codex leg when tracking is on, swallowing its failure. Only
    /// cancellation propagates, so an aborted reload still aborts.
    private func optionalCodex<T>(_ work: () async throws -> T) async throws -> T? {
        guard isCodexEnabled() else { return nil }
        do { return try await work() }
        catch is CancellationError { throw CancellationError() }
        catch { return nil }
    }
}
