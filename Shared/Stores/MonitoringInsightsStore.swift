import Foundation
import SwiftUI

/// Lightweight history-data layer dedicated to the Monitoring homepage.
/// Independent from `HistoryStore` (which is owned by HistoryView and
/// keyed to the user's selected range / filter) so a Monitoring open
/// doesn't tamper with HistoryView's state.
///
/// Always loads the last 7 daily buckets + the previous 7-day total
/// (for the delta). Pre-warms silently on Monitoring appear; cached
/// per-file aggregates inside `SessionHistoryService` keep repeat
/// loads cheap.
@MainActor
final class MonitoringInsightsStore: ObservableObject {

    @Published private(set) var weeklyBuckets: [HistoryBucket] = []
    @Published private(set) var previousWeekTotal: Int = 0
    @Published private(set) var hasLoaded: Bool = false

    private let service: SessionHistoryServiceProtocol
    private var loadTask: Task<Void, Never>?
    private var lastLoaded: Date?
    private static let staleAfter: TimeInterval = 60

    init(service: SessionHistoryServiceProtocol = SessionHistoryService()) {
        self.service = service
    }

    /// Kicks a background load if no data has been loaded yet, or if the
    /// last load is older than 60s. No-op if a load is already in flight
    /// for the same window.
    func warmIfStale() {
        if let lastLoaded, hasLoaded, Date().timeIntervalSince(lastLoaded) < Self.staleAfter {
            return
        }
        loadTask?.cancel()
        let service = self.service
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let bucketsTask = Task.detached(priority: .utility) {
                    try await service.loadHistory(range: .sevenDays)
                }.value
                async let previousTask = Task.detached(priority: .utility) {
                    try await service.loadPreviousPeriodActiveTokens(range: .sevenDays)
                }.value

                let buckets = try await bucketsTask
                let previous = (try? await previousTask) ?? 0
                if Task.isCancelled { return }
                await MainActor.run {
                    self.weeklyBuckets = buckets
                    self.previousWeekTotal = previous
                    self.hasLoaded = true
                    self.lastLoaded = Date()
                }
            } catch {
                // Silent fail - back-of-card content just stays minimal.
            }
        }
    }

    /// Computes a snapshot of tile insights for a given model family
    /// (or `nil` for all-models, used by the Weekly tile). Returns nil
    /// before data is loaded so the consumer can render a placeholder.
    func snapshot(for family: ModelFamily?) -> TileInsightsSnapshot? {
        guard hasLoaded else { return nil }

        let tokens = weeklyBuckets.map { bucket -> Int in
            tokensFor(family, in: bucket)
        }
        let total = tokens.reduce(0, +)

        // Heaviest day -> bucket with the highest count for this family.
        let heaviest: TileInsightsSnapshot.HeaviestDay? = zip(weeklyBuckets, tokens)
            .max { $0.1 < $1.1 }
            .flatMap { (bucket, count) in
                count > 0 ? .init(date: bucket.date, tokens: count) : nil
            }

        // Delta % vs previous 7d. Only meaningful for the all-models
        // family (Weekly tile) - per-family previous-period totals are
        // not pre-computed by the service.
        let deltaPercent: Double? = {
            guard family == nil, previousWeekTotal > 0 else { return nil }
            return (Double(total) - Double(previousWeekTotal)) / Double(previousWeekTotal) * 100
        }()

        return TileInsightsSnapshot(
            sparkline: tokens,
            total: total,
            heaviestDay: heaviest,
            deltaPercent: deltaPercent
        )
    }

    private func tokensFor(_ family: ModelFamily?, in bucket: HistoryBucket) -> Int {
        guard let family else {
            // Weekly (all) -> sum of every model in the bucket.
            return bucket.totalActive
        }
        return bucket.tokensByModel.reduce(0) { acc, pair in
            pair.key.family == family ? acc + pair.value : acc
        }
    }
}

/// Plain value snapshot consumed by `MetricTile` to render the back
/// face. Equatable so SwiftUI can avoid re-renders when nothing changed.
struct TileInsightsSnapshot: Equatable {
    /// 7 entries (one per day in chronological order). Drives the
    /// sparkline + total computation.
    let sparkline: [Int]
    let total: Int
    let heaviestDay: HeaviestDay?
    /// Only present for the all-models tile (Weekly).
    let deltaPercent: Double?

    struct HeaviestDay: Equatable {
        let date: Date
        let tokens: Int
    }
}
