import WidgetKit
import Foundation

struct UsageEntry: TimelineEntry {
    let date: Date
    let usage: UsageResponse?
    let error: String?
    let isStale: Bool
    let lastSync: Date?
    /// 7 daily token totals (oldest first). Only populated for the
    /// History Sparkline widget. Refreshed by the main app once a day.
    let lastWeekDailyTotals: [Int]?

    init(
        date: Date,
        usage: UsageResponse?,
        error: String? = nil,
        isStale: Bool = false,
        lastSync: Date? = nil,
        lastWeekDailyTotals: [Int]? = nil
    ) {
        self.date = date
        self.usage = usage
        self.error = error
        self.isStale = isStale
        self.lastSync = lastSync
        self.lastWeekDailyTotals = lastWeekDailyTotals
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func iso8601String(from date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    static var placeholder: UsageEntry {
        UsageEntry(
            date: Date(),
            usage: UsageResponse(
                fiveHour: UsageBucket(utilization: 35, resetsAt: iso8601String(from: Date().addingTimeInterval(3600))),
                sevenDay: UsageBucket(utilization: 52, resetsAt: iso8601String(from: Date().addingTimeInterval(86400 * 3))),
                sevenDaySonnet: UsageBucket(utilization: 12, resetsAt: iso8601String(from: Date().addingTimeInterval(86400 * 3)))
            ),
            lastWeekDailyTotals: [120_000, 180_000, 95_000, 240_000, 310_000, 150_000, 220_000]
        )
    }

    static var unconfigured: UsageEntry {
        UsageEntry(date: Date(), usage: nil, error: String(localized: "error.notoken"))
    }
}
