import Foundation
import SwiftUI

/// Drives `HistoryView`. Owns the active range + filter, kicks off cancellable
/// load tasks on a detached priority `.utility` queue, and exposes the
/// aggregated buckets + summary for the view to render.
@MainActor
final class HistoryStore: ObservableObject {

    // MARK: - State

    @Published var range: HistoryRange = .sevenDays {
        didSet { if oldValue != range { reload() } }
    }

    @Published var filter: HistoryFilter = .all

    /// Which providers History is showing. The mode selector in the window bar
    /// drives the whole app, and this view was the one place it did nothing:
    /// the buckets come from `CombinedSessionHistoryService`, so they already
    /// hold both providers' models mixed together.
    ///
    /// The gate is applied where the buckets are stored rather than at each
    /// read site, so the chart, the summary, the chips, the project ranking
    /// and the session list all follow without knowing the mode exists.
    @Published var providerMode: ProviderMode = .all {
        didSet {
            guard oldValue != providerMode else { return }
            // A Claude family filter left over from All mode would show an
            // empty chart in Codex mode, which reads as "no data" rather than
            // "wrong filter".
            filter = .all
            applyResult(buckets: rawBuckets, previousActive: previousPeriodActive)
        }
    }

    /// Active tab of the chart card (Tokens / Projects / Sessions / Cache).
    /// Lives in the store (hoisted in `MainAppView`) so the choice survives
    /// navigating away from History and back.
    @Published var statsTab: HistoryStatsTab = .tokens

    /// All buckets within the active range. Kept un-filtered so swapping the
    /// model filter is instant (no re-parse).
    @Published private(set) var buckets: [HistoryBucket] = []

    /// Summary computed from `buckets` after applying `filter`.
    @Published private(set) var summary: HistorySummary = .empty

    @Published private(set) var isLoading: Bool = false

    /// True once we attempted at least one load; prevents the empty-state from
    /// flashing during the cold load.
    @Published private(set) var hasLoadedOnce: Bool = false

    /// Active model families derived from the data. Drives the auto-adaptive
    /// legend + which filter chips light up vs grey out.
    @Published private(set) var activeFamilies: Set<ModelFamily> = []

    /// Total active tokens per family for the chip badges (e.g. "Opus · 1.2M").
    @Published private(set) var familyTotals: [ModelFamily: Int] = [:]

    /// Ranked project breakdown over the visible range (highest tokens first).
    /// Backs the panel behind the "Top project" chip. Always model-agnostic
    /// (see `ProjectTotal`), so it only changes with the range, not the filter.
    @Published private(set) var projectTotals: [ProjectTotal] = []

    var availableFamilies: [ModelFamily] {
        let codex = activeFamilies.filter(\.isCodex).sorted { $0.rawValue < $1.rawValue }
        switch providerMode.provider {
        case .claude: return ModelFamily.allCases
        case .codex:  return codex
        case nil:     return ModelFamily.allCases + codex
        }
    }

    var sortedModelKinds: [ModelKind] {
        ModelKind.stackOrder + totalsByKind.keys.filter(\.isCodex).sorted { $0.rawValue < $1.rawValue }
    }

    // MARK: - Wiring

    private let service: SessionHistoryServiceProtocol
    private var loadTask: Task<Void, Never>?

    init(service: SessionHistoryServiceProtocol = CombinedSessionHistoryService()) {
        self.service = service
    }

    // MARK: - Public

    func reload() {
        loadTask?.cancel()
        let range = self.range
        let service = self.service
        isLoading = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let bucketsTask = Task.detached(priority: .utility) {
                    try await service.loadHistory(range: range)
                }.value
                async let previousTask = Task.detached(priority: .utility) {
                    try await service.loadPreviousPeriodActiveTokens(range: range)
                }.value

                let buckets = try await bucketsTask
                let previousActive = (try? await previousTask) ?? [:]

                if Task.isCancelled { return }
                await MainActor.run {
                    self.applyResult(buckets: buckets, previousActive: previousActive)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self.buckets = []
                    self.summary = .empty
                    self.projectTotals = []
                    self.isLoading = false
                    self.hasLoadedOnce = true
                }
            }
        }
    }

    func setFilter(_ newFilter: HistoryFilter) {
        guard filter != newFilter else { return }
        filter = newFilter
        recomputeSummary()
    }

    // MARK: - Private

    /// The buckets exactly as parsed, before the provider gate. Kept so
    /// switching mode is instant, the same reason `buckets` keeps everything
    /// the model filter would hide.
    private var rawBuckets: [HistoryBucket] = []

    private func applyResult(buckets: [HistoryBucket], previousActive: [MetricProvider: Int]) {
        self.rawBuckets = buckets
        self.buckets = Self.gate(buckets, to: providerMode)
        self.previousPeriodActive = previousActive
        self.activeFamilies = Self.activeFamilies(in: buckets)
        self.familyTotals = Self.familyTotals(in: buckets)
        self.isLoading = false
        self.hasLoadedOnce = true
        recomputeSummary()
    }

    /// Cached during `applyResult` so `recomputeSummary` (called whenever the
    /// filter flips) doesn't have to re-issue a load. Kept split by provider
    /// because `buckets` is gated by `providerMode`: summing both sides here
    /// would compare a Codex-only total against a Claude + Codex one and
    /// render the difference as a collapse in usage.
    private var previousPeriodActive: [MetricProvider: Int] = [:]

    /// The previous-period total for the providers currently on screen.
    private var gatedPreviousPeriodActive: Int {
        previousPeriodActive
            .filter { providerMode.shows($0.key) }
            .values
            .reduce(0, +)
    }

    private func recomputeSummary() {
        let filtered = applyFilter(to: buckets, filter: filter)

        let totalActive = filtered.reduce(0) { $0 + $1.totalActive }
        let totalCached = filtered.reduce(0) { $0 + $1.cachedTokens }
        let sessionsCount = filtered.reduce(0) { $0 + $1.sessionsCount }

        let heaviest = filtered.max(by: { $0.totalActive < $1.totalActive })

        // Top model: across the filtered range, which model carried the most
        // active tokens.
        var modelTotals: [ModelKind: Int] = [:]
        for bucket in filtered {
            for (kind, tokens) in bucket.tokensByModel {
                modelTotals[kind, default: 0] += tokens
            }
        }
        let topModel: (kind: ModelKind, tokens: Int)? = modelTotals
            .max(by: { $0.value < $1.value })
            .map { (kind: $0.key, tokens: $0.value) }

        // Top project + full ranking: same idea over the project breakdown.
        let ranked = Self.rankedProjects(in: filtered)
        projectTotals = ranked
        let topProject: (path: String, tokens: Int)? = ranked.first
            .map { (path: $0.path, tokens: $0.tokens) }

        // The previous-period delta only makes sense when `filter == .all`.
        // Filtered totals don't have an apples-to-apples previous comparison
        // (we'd have to refetch with the same filter), so we zero it out for
        // the filtered case to avoid lying with the % delta.
        let prev = filter.isAll ? gatedPreviousPeriodActive : 0

        summary = HistorySummary(
            totalActive: totalActive,
            totalCached: totalCached,
            previousPeriodActive: prev,
            heaviestBucket: heaviest,
            topModel: topModel,
            topProject: topProject,
            sessionsCount: sessionsCount
        )
    }

    /// Drops the hidden provider's models from every bucket. A bucket with
    /// nothing left is dropped entirely, so an empty range reads as empty
    /// rather than as a row of zeroes.
    ///
    /// Only `tokensByModel` can be split by provider. `tokensByProject`,
    /// `sessionsCount` and the raw input/output counters are per bucket, not
    /// per model, so in a provider mode they still describe both. That is why
    /// the project ranking and the session count stay honest only in All
    /// mode; scaling them by the surviving share would invent numbers.
    nonisolated static func gate(_ buckets: [HistoryBucket], to mode: ProviderMode) -> [HistoryBucket] {
        guard let provider = mode.provider else { return buckets }
        let wantsCodex = provider == .codex
        return buckets.compactMap { bucket in
            let kept = bucket.tokensByModel.filter { $0.key.isCodex == wantsCodex }
            guard !kept.isEmpty else { return nil }
            var copy = bucket
            copy.tokensByModel = kept
            return copy
        }
    }

    private func applyFilter(to buckets: [HistoryBucket], filter: HistoryFilter) -> [HistoryBucket] {
        switch filter {
        case .all:
            return buckets
        case .family(let family):
            return buckets.map { bucket in
                var b = bucket
                b.tokensByModel = bucket.tokensByModel.filter { $0.key.family == family }
                // Active token totals are recomputed lazily via totalActive,
                // but we also need the input/output split if we want to keep
                // cache hit rate accurate. Conservatively zero out the cache
                // counters when filtering to avoid lying about cache hit rate
                // for a model-specific view (cache counters are not reported
                // per-model in the JSONL, so we can't attribute them).
                let kept = b.tokensByModel.values.reduce(0, +)
                let scale = bucket.totalActive == 0 ? 0 : Double(kept) / Double(bucket.totalActive)
                b.inputTokens = Int(Double(bucket.inputTokens) * scale)
                b.outputTokens = Int(Double(bucket.outputTokens) * scale)
                b.cacheReadTokens = Int(Double(bucket.cacheReadTokens) * scale)
                b.cacheCreateTokens = Int(Double(bucket.cacheCreateTokens) * scale)
                return b
            }
        }
    }

    private static func activeFamilies(in buckets: [HistoryBucket]) -> Set<ModelFamily> {
        var set: Set<ModelFamily> = []
        for bucket in buckets {
            for kind in bucket.tokensByModel.keys {
                set.insert(kind.family)
            }
        }
        return set
    }

    private static func familyTotals(in buckets: [HistoryBucket]) -> [ModelFamily: Int] {
        var totals: [ModelFamily: Int] = [:]
        for bucket in buckets {
            for (kind, tokens) in bucket.tokensByModel {
                totals[kind.family, default: 0] += tokens
            }
        }
        return totals
    }

    /// Ranked project totals (active tokens, highest first) across the given
    /// buckets. Ties break on path so the ordering is deterministic. Pure and
    /// static so it can be unit-tested without a MainActor store instance.
    nonisolated static func rankedProjects(in buckets: [HistoryBucket]) -> [ProjectTotal] {
        var totals: [String: Int] = [:]
        for bucket in buckets {
            for (path, tokens) in bucket.tokensByProject {
                totals[path, default: 0] += tokens
            }
        }
        return totals
            .map { ProjectTotal(path: $0.key, tokens: $0.value) }
            .sorted { $0.tokens != $1.tokens ? $0.tokens > $1.tokens : $0.path < $1.path }
    }

    /// Total active tokens per `ModelKind` across the given buckets. Pure and
    /// static so it can be unit-tested without a MainActor store instance.
    /// Used by the chart to decide which kinds have any data to stack.
    nonisolated static func totalsByKind(in buckets: [HistoryBucket]) -> [ModelKind: Int] {
        var totals: [ModelKind: Int] = [:]
        for bucket in buckets {
            for (kind, tokens) in bucket.tokensByModel {
                totals[kind, default: 0] += tokens
            }
        }
        return totals
    }

    /// Instance accessor over the currently loaded (unfiltered) buckets.
    var totalsByKind: [ModelKind: Int] {
        Self.totalsByKind(in: buckets)
    }

    /// Chart-facing filter: keeps every field intact and narrows only
    /// `tokensByModel` to the selected family. Distinct from the private
    /// `applyFilter` used by the summary, which additionally scales the
    /// cache counters. Pure + static for unit tests.
    nonisolated static func bucketsForChart(_ buckets: [HistoryBucket], filter: HistoryFilter) -> [HistoryBucket] {
        switch filter {
        case .all:
            return buckets
        case .family(let family):
            return buckets.map { bucket in
                var b = bucket
                b.tokensByModel = bucket.tokensByModel.filter { $0.key.family == family }
                return b
            }
        }
    }

    /// Instance accessor over the loaded buckets with the active filter applied.
    var filteredBuckets: [HistoryBucket] {
        Self.bucketsForChart(buckets, filter: filter)
    }
}
