import Foundation

// MARK: - Range

/// Time window the History view looks back over. The 24h view buckets by hour
/// so the chart still has 24 data points; everything else buckets by day.
enum HistoryRange: String, CaseIterable, Codable, Sendable {
    case twentyFourHours = "24h"
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case ninetyDays = "90d"

    var labelKey: String {
        "history.range.\(rawValue)"
    }

    /// Number of seconds covered by the range.
    var seconds: TimeInterval {
        switch self {
        case .twentyFourHours: return 24 * 3600
        case .sevenDays:       return 7 * 86_400
        case .thirtyDays:      return 30 * 86_400
        case .ninetyDays:      return 90 * 86_400
        }
    }

    /// True when the range is short enough to be displayed at hourly resolution.
    var isHourly: Bool { self == .twentyFourHours }

    /// Bucket size used when aggregating raw events. The cache stores hourly
    /// counts as well, so daily ranges simply roll up multiple hourly buckets.
    var bucketSeconds: TimeInterval {
        isHourly ? 3600 : 86_400
    }
}

// MARK: - Model classification

/// Coarse model identity used for chart colouring + filter chips. Opus 4.7 and
/// 4.6 are kept distinct (the user might run both back-to-back), Sonnet/Haiku
/// collapse all minor versions, anything unrecognised lands in `.other`. Design
/// intentionally absent: it never appears in Claude Code JSONL files.
enum ModelKind: String, CaseIterable, Codable, Hashable, Sendable {
    case opus47
    case opus46
    case sonnet
    case haiku
    case other

    init(rawModel: String) {
        let lower = rawModel.lowercased()
        if lower.contains("opus-4-7") || lower.contains("opus-4.7") {
            self = .opus47
        } else if lower.contains("opus-4-6") || lower.contains("opus-4.6") {
            self = .opus46
        } else if lower.contains("sonnet") {
            self = .sonnet
        } else if lower.contains("haiku") {
            self = .haiku
        } else {
            self = .other
        }
    }

    var displayName: String {
        switch self {
        case .opus47: return "Opus 4.7"
        case .opus46: return "Opus 4.6"
        case .sonnet: return "Sonnet"
        case .haiku:  return "Haiku"
        case .other:  return "Other"
        }
    }

    /// Family used by the filter chips. Opus 4.7 and 4.6 fold into `.opus`
    /// since users typically think "Opus" not "Opus 4.7 vs 4.6".
    var family: ModelFamily {
        switch self {
        case .opus47, .opus46: return .opus
        case .sonnet:          return .sonnet
        case .haiku:           return .haiku
        case .other:           return .other
        }
    }

    /// Stable order for chart stacking (heaviest at the top of the bar).
    static var stackOrder: [ModelKind] {
        [.haiku, .opus46, .opus47, .sonnet, .other]
    }
}

enum ModelFamily: String, CaseIterable, Codable, Hashable, Sendable {
    case opus, sonnet, haiku, other

    var displayName: String {
        switch self {
        case .opus:   return "Opus"
        case .sonnet: return "Sonnet"
        case .haiku:  return "Haiku"
        case .other:  return "Other"
        }
    }
}

// MARK: - Filter

enum HistoryFilter: Hashable, Sendable {
    case all
    case family(ModelFamily)

    var isAll: Bool { if case .all = self { true } else { false } }
}

// MARK: - Aggregates

/// Per-bucket aggregate produced by `SessionHistoryService`. The bucket can be
/// either an hour (24h range) or a day (everything else); the consumer decides
/// based on the active `HistoryRange`.
struct HistoryBucket: Identifiable, Codable, Sendable {
    /// Bucket start instant, normalised to the calendar boundary (start of day
    /// or start of hour depending on resolution).
    let date: Date
    /// Token totals broken down by model so the chart can stack segments and
    /// the filter chips can sum a single family.
    var tokensByModel: [ModelKind: Int]
    /// Active tokens (input + output) per project path. Used for the "top
    /// project" chip and any future project drill-down.
    var tokensByProject: [String: Int]
    /// Distinct session count -> drives "avg / session" stat.
    var sessionsCount: Int
    /// Accumulated raw counters for cache hit rate calculation.
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheCreateTokens: Int

    var id: Date { date }

    var totalActive: Int {
        tokensByModel.values.reduce(0, +)
    }

    var totalIncludingCache: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreateTokens
    }

    var cachedTokens: Int {
        cacheReadTokens + cacheCreateTokens
    }

    static let empty = HistoryBucket(
        date: .distantPast,
        tokensByModel: [:],
        tokensByProject: [:],
        sessionsCount: 0,
        inputTokens: 0,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheCreateTokens: 0
    )

    static func merging(_ lhs: HistoryBucket, _ rhs: HistoryBucket, date: Date) -> HistoryBucket {
        var byModel = lhs.tokensByModel
        for (k, v) in rhs.tokensByModel { byModel[k, default: 0] += v }
        var byProject = lhs.tokensByProject
        for (k, v) in rhs.tokensByProject { byProject[k, default: 0] += v }
        return HistoryBucket(
            date: date,
            tokensByModel: byModel,
            tokensByProject: byProject,
            sessionsCount: lhs.sessionsCount + rhs.sessionsCount,
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            cacheReadTokens: lhs.cacheReadTokens + rhs.cacheReadTokens,
            cacheCreateTokens: lhs.cacheCreateTokens + rhs.cacheCreateTokens
        )
    }
}

// MARK: - Summary

/// One-line snapshot of the visible range, used to fill the hero card and the
/// footer chips. Computed by `HistoryStore` from the current bucket array
/// after applying the model filter.
struct HistorySummary: Sendable {
    let totalActive: Int
    let totalCached: Int
    /// Active tokens of the equivalent previous period (e.g. `last 7d` -> the
    /// 7d before that), for the hero delta percentage.
    let previousPeriodActive: Int
    let heaviestBucket: HistoryBucket?
    let topModel: (kind: ModelKind, tokens: Int)?
    let topProject: (path: String, tokens: Int)?
    let sessionsCount: Int

    var totalIncludingCache: Int { totalActive + totalCached }

    var cacheHitRate: Double {
        let denom = totalIncludingCache
        return denom == 0 ? 0 : Double(totalCached) / Double(denom)
    }

    var averagePerSession: Int {
        sessionsCount == 0 ? 0 : totalActive / sessionsCount
    }

    var deltaPercent: Double? {
        guard previousPeriodActive > 0 else { return nil }
        return (Double(totalActive) - Double(previousPeriodActive)) / Double(previousPeriodActive) * 100
    }

    static let empty = HistorySummary(
        totalActive: 0,
        totalCached: 0,
        previousPeriodActive: 0,
        heaviestBucket: nil,
        topModel: nil,
        topProject: nil,
        sessionsCount: 0
    )
}

// MARK: - Cache entry

/// Per-file cache entry persisted to disk. The aggregator skips re-parsing a
/// file when its mtime matches the cached value -> repeated opens of the
/// History view stay sub-100ms after the first scan.
struct HistoryFileCacheEntry: Codable, Sendable {
    let path: String
    let mtime: Date
    let buckets: [HistoryBucket]
    /// Distinct session ids seen in this file. Used by the merger to compute
    /// `sessionsCount` correctly when aggregating across files (one session
    /// might span multiple JSONL lines but the count is per session, not per
    /// line).
    let sessionIds: [String]
}

struct HistoryCache: Codable, Sendable {
    /// Schema version. Bump when the cache shape changes so old caches are
    /// thrown away cleanly instead of decoded into garbage.
    var version: Int
    var entries: [String: HistoryFileCacheEntry]

    static let currentVersion = 1
    static let empty = HistoryCache(version: currentVersion, entries: [:])
}
