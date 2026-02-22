import WidgetKit
import Foundation

struct UsageEntry: TimelineEntry {
    let date: Date
    let usage: UsageResponse?
    let error: String?
    let isStale: Bool

    init(date: Date, usage: UsageResponse?, error: String? = nil, isStale: Bool = false) {
        self.date = date
        self.usage = usage
        self.error = error
        self.isStale = isStale
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static var placeholder: UsageEntry {
        UsageEntry(
            date: Date(),
            usage: UsageResponse(
                fiveHour: UsageBucket(utilization: 35, resetsAt: iso8601String(from: Date().addingTimeInterval(3600))),
                sevenDay: UsageBucket(utilization: 52, resetsAt: iso8601String(from: Date().addingTimeInterval(86400 * 3))),
                sevenDaySonnet: UsageBucket(utilization: 12, resetsAt: iso8601String(from: Date().addingTimeInterval(86400 * 3)))
            )
        )
    }

    static var unconfigured: UsageEntry {
        UsageEntry(date: Date(), usage: nil, error: String(localized: "error.notoken"))
    }
}
