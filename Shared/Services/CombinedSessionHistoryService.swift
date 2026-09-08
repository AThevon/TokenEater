import Foundation

final class CombinedSessionHistoryService: SessionHistoryServiceProtocol {
    private let claude: SessionHistoryServiceProtocol
    private let codex: SessionHistoryServiceProtocol

    init(
        claude: SessionHistoryServiceProtocol = SessionHistoryService(),
        codex: SessionHistoryServiceProtocol = SessionHistoryService(source: .codex)
    ) {
        self.claude = claude
        self.codex = codex
    }

    func loadHistory(range: HistoryRange) async throws -> [HistoryBucket] {
        async let claudeBuckets = claude.loadHistory(range: range)
        async let codexBuckets = codex.loadHistory(range: range)
        let buckets = try await claudeBuckets + codexBuckets
        try Task.checkCancellation()
        return Dictionary(buckets.map { ($0.date, $0) }, uniquingKeysWith: {
            HistoryBucket.merging($0, $1, date: $0.date)
        }).values.sorted { $0.date < $1.date }
    }

    func loadPreviousPeriodActiveTokens(range: HistoryRange) async throws -> Int {
        async let claudeTotal = claude.loadPreviousPeriodActiveTokens(range: range)
        async let codexTotal = codex.loadPreviousPeriodActiveTokens(range: range)
        return try await claudeTotal + codexTotal
    }
}
