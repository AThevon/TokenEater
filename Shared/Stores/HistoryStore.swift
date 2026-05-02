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

    // MARK: - Wiring

    private let service: SessionHistoryServiceProtocol
    private var loadTask: Task<Void, Never>?

    init(service: SessionHistoryServiceProtocol = SessionHistoryService()) {
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
                let previousActive = (try? await previousTask) ?? 0

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

    private func applyResult(buckets: [HistoryBucket], previousActive: Int) {
        self.buckets = buckets
        self.previousPeriodActive = previousActive
        self.activeFamilies = Self.activeFamilies(in: buckets)
        self.familyTotals = Self.familyTotals(in: buckets)
        self.isLoading = false
        self.hasLoadedOnce = true
        recomputeSummary()
    }

    /// Cached during `applyResult` so `recomputeSummary` (called whenever the
    /// filter flips) doesn't have to re-issue a load.
    private var previousPeriodActive: Int = 0

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

        // Top project: same idea over the project breakdown.
        var projectTotals: [String: Int] = [:]
        for bucket in filtered {
            for (path, tokens) in bucket.tokensByProject {
                projectTotals[path, default: 0] += tokens
            }
        }
        let topProject: (path: String, tokens: Int)? = projectTotals
            .max(by: { $0.value < $1.value })
            .map { (path: $0.key, tokens: $0.value) }

        // The previous-period delta only makes sense when `filter == .all`.
        // Filtered totals don't have an apples-to-apples previous comparison
        // (we'd have to refetch with the same filter), so we zero it out for
        // the filtered case to avoid lying with the % delta.
        let prev = filter.isAll ? previousPeriodActive : 0

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
}
