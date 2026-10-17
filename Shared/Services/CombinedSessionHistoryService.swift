import Foundation

/// Claude history, every tracked account's, plus Codex history when the user
/// is tracking Codex.
///
/// Three rules the legs do not share. The Claude legs are one per tracked
/// account, paused ones included since their transcripts are local, and are
/// read again at every load, so adding, removing or moving an account reaches
/// the next reload without rebuilding anything; `accountFilter` narrows them
/// to one account. The Codex leg follows `codexEnabled`, read at load time
/// rather than at construction, for the same reason. And a failing leg never
/// takes the others with it: local log parsing can fail on a malformed file,
/// and a user who does not even use Codex, or one account's unreadable folder,
/// should not cost the rest of the History screen.
final class CombinedSessionHistoryService: SessionHistoryServiceProtocol {
    private let claudeLegs: @Sendable () -> [SessionHistoryServiceProtocol]
    private let codex: SessionHistoryServiceProtocol
    private let isCodexEnabled: @Sendable () -> Bool

    static let codexEnabledDefault: @Sendable () -> Bool = {
        UserDefaults.standard.object(forKey: "codexEnabled") as? Bool ?? false
    }

    /// - Parameters:
    ///   - claudeRoots: the Claude folders to read, evaluated at every load.
    ///     Every tracked account by default.
    ///   - accountFilter: one account's folder only, or nil for all of them.
    init(
        claudeRoots: @escaping @Sendable () -> [ClaudeHistoryRoot] = { CombinedSessionHistoryService.trackedClaudeRoots() },
        accountFilter: AccountID? = nil,
        codex: SessionHistoryServiceProtocol = CombinedSessionHistoryService.codexLeg(),
        isCodexEnabled: @escaping @Sendable () -> Bool = CombinedSessionHistoryService.codexEnabledDefault
    ) {
        self.claudeLegs = {
            claudeRoots()
                .filter { accountFilter == nil || $0.account == accountFilter }
                .map(Self.claudeLeg(for:))
        }
        self.codex = codex
        self.isCodexEnabled = isCodexEnabled
    }

    /// One fixed Claude leg, for tests and callers that already hold one.
    init(
        claude: SessionHistoryServiceProtocol,
        codex: SessionHistoryServiceProtocol = CombinedSessionHistoryService.codexLeg(),
        isCodexEnabled: @escaping @Sendable () -> Bool = CombinedSessionHistoryService.codexEnabledDefault
    ) {
        self.claudeLegs = { [claude] }
        self.codex = codex
        self.isCodexEnabled = isCodexEnabled
    }

    /// The reader of one Claude folder's transcripts, with its own cache.
    /// A folder of the multi-account demo is generated in memory instead,
    /// and only while the demo runs (`DemoMode`).
    static func claudeLeg(for root: ClaudeHistoryRoot) -> SessionHistoryServiceProtocol {
        DemoMode.historyService(for: root)
            ?? SessionHistoryService(rootURL: root.projectsURL, cacheURL: root.cacheURL)
    }

    /// The Codex reader: `CODEX_HOME`'s sessions, or the demo's fake Codex
    /// login while the demo runs.
    static func codexLeg() -> SessionHistoryServiceProtocol {
        DemoMode.codexHistoryService() ?? SessionHistoryService(source: .codex)
    }

    /// Every tracked Claude account's folder, the main one first: its
    /// `<dir>/projects` (`~/.claude/projects` unless moved, #294) with
    /// `history-cache.json`, then each added account's, paused or not, with
    /// `history-cache.acct-<uuid>.json`. Read from the stored account list,
    /// so it costs one small decode per load and needs no store.
    static func trackedClaudeRoots() -> [ClaudeHistoryRoot] {
        let home = ClaudeConfigDirResolver.realHome()
        return ClaudeAccountsStorage.load(from: .standard).map { record in
            ClaudeHistoryRoot(
                account: record.id,
                projectsURL: record.scope.projectsURL(home: home),
                cacheURL: SessionHistoryService.cacheURL(for: record.id)
            )
        }
    }

    func loadHistory(range: HistoryRange) async throws -> [HistoryBucket] {
        let legs = claudeLegs()
        async let claudeBuckets = Self.claude(legs) { try await $0.loadHistory(range: range) }
        let codexBuckets = try await optionalCodex { try await self.codex.loadHistory(range: range) } ?? []
        let buckets = try await claudeBuckets.flatMap { $0 } + codexBuckets
        try Task.checkCancellation()
        return Dictionary(buckets.map { ($0.date, $0) }, uniquingKeysWith: {
            HistoryBucket.merging($0, $1, date: $0.date)
        }).values.sorted { $0.date < $1.date }
    }

    func loadPreviousPeriodActiveTokens(range: HistoryRange) async throws -> [MetricProvider: Int] {
        let legs = claudeLegs()
        async let claudeTotals = Self.claude(legs) { try await $0.loadPreviousPeriodActiveTokens(range: range) }
        let codexTotals = try await optionalCodex {
            try await self.codex.loadPreviousPeriodActiveTokens(range: range)
        } ?? [:]
        return try await claudeTotals.reduce(codexTotals) { $0.merging($1) { $0 + $1 } }
    }

    /// Runs the Claude legs one after the other: each one already parses its
    /// files in parallel, and stacking N accounts' worth of that on every
    /// reload is the idle-CPU trap of #255. A single leg fails as it always
    /// has; with several, a failing one is left out unless they all fail.
    /// Cancellation always propagates.
    private static func claude<T>(
        _ legs: [SessionHistoryServiceProtocol],
        _ work: (SessionHistoryServiceProtocol) async throws -> T
    ) async throws -> [T] {
        var results: [T] = []
        var firstError: Error?
        for leg in legs {
            do {
                results.append(try await work(leg))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                firstError = firstError ?? error
            }
        }
        if results.isEmpty, let firstError { throw firstError }
        return results
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
