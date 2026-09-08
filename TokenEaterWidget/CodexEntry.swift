import WidgetKit
import Foundation

struct CodexEntry: TimelineEntry {
    let date: Date
    let usage: CodexUsageResponse?
    let isEnabled: Bool
    let isStale: Bool
    let lastSync: Date?
    let error: String?
    var pacingMargin: Double = 10

    static var placeholder: CodexEntry {
        let now = Date()
        return CodexEntry(
            date: now,
            usage: CodexUsageResponse(
                planType: "plus",
                rateLimit: CodexRateLimit(
                    primaryWindow: CodexRateWindow(usedPercent: 35, limitWindowSeconds: 18_000, resetAt: Int(now.addingTimeInterval(3600).timeIntervalSince1970)),
                    secondaryWindow: CodexRateWindow(usedPercent: 52, limitWindowSeconds: 604_800, resetAt: Int(now.addingTimeInterval(259_200).timeIntervalSince1970))
                ),
                resetCreditsAvailable: 2
            ),
            isEnabled: true, isStale: false, lastSync: now, error: nil
        )
    }
}
