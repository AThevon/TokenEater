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
    private let sharedFile: SharedFileServiceProtocol
    private var loadTask: Task<Void, Never>?
    private var lastLoaded: Date?
    private static let staleAfter: TimeInterval = 60

    init(
        service: SessionHistoryServiceProtocol = SessionHistoryService(),
        sharedFile: SharedFileServiceProtocol = SharedFileService()
    ) {
        self.service = service
        self.sharedFile = sharedFile
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
                    let now = Date()
                    // Trim the rolling-window result to the 7 calendar days the
                    // widget renders so the in-app weekly total matches the
                    // widget total (loadHistory can surface a partial 8th day).
                    let windowed = Self.bucketsInWindow(buckets, today: now)
                    self.weeklyBuckets = windowed
                    self.previousWeekTotal = previous
                    self.hasLoaded = true
                    self.lastLoaded = now
                    // Mirror the daily totals to the shared file so the
                    // History Sparkline widget renders without re-parsing
                    // JSONL from the sandboxed widget process. Densify to one
                    // slot per calendar day so empty days stay aligned (#179).
                    let totals = Self.dailyTotalsByDay(from: windowed, today: now)
                    self.sharedFile.updateLastWeekDailyTotals(totals, refreshedAt: now)
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

    /// Maps sparse daily buckets onto a dense, calendar-aligned array of
    /// `days` slots (oldest first, today last), zero-filling days with no
    /// activity. The History Sparkline widget labels each bar by its position
    /// relative to today, so a missing day must be an explicit zero rather
    /// than skipped - otherwise every later bar shifts under the wrong weekday
    /// (issue #179). Returns `[]` when there is no history at all so the widget
    /// keeps showing its empty state.
    /// The buckets whose calendar day falls within the last `days` days ending
    /// today (inclusive). `loadHistory` uses a rolling instant window that can
    /// surface a partial 8th day; trimming here keeps the in-app weekly total
    /// aligned with the 7 calendar days the widget renders (#179).
    nonisolated static func bucketsInWindow(
        _ buckets: [HistoryBucket],
        days: Int = 7,
        today: Date,
        calendar: Calendar = .current
    ) -> [HistoryBucket] {
        let startToday = calendar.startOfDay(for: today)
        guard let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: startToday) else {
            return buckets
        }
        return buckets.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= windowStart && day <= startToday
        }
    }

    nonisolated static func dailyTotalsByDay(
        from buckets: [HistoryBucket],
        days: Int = 7,
        today: Date,
        calendar: Calendar = .current
    ) -> [Int] {
        guard !buckets.isEmpty else { return [] }
        let totalsByDay = Dictionary(
            buckets.map { (calendar.startOfDay(for: $0.date), $0.totalActive) },
            uniquingKeysWith: +
        )
        let startToday = calendar.startOfDay(for: today)
        let dense = (0..<days).reversed().map { offset -> Int in
            let day = calendar.date(byAdding: .day, value: -offset, to: startToday) ?? startToday
            return totalsByDay[day] ?? 0
        }
        // All-zero means the surviving activity all fell on the dropped partial
        // day outside the window - return empty so the widget shows its empty
        // state instead of a flat 0-chart (#179 review finding).
        return dense.allSatisfy { $0 == 0 } ? [] : dense
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
