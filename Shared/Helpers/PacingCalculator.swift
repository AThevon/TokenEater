import Foundation

enum PacingCalculator {
    private static let chillMessages = [
        "pacing.chill.1", "pacing.chill.2", "pacing.chill.3",
    ]
    private static let onTrackMessages = [
        "pacing.ontrack.1", "pacing.ontrack.2", "pacing.ontrack.3",
    ]
    private static let hotMessages = [
        "pacing.hot.1", "pacing.hot.2", "pacing.hot.3",
    ]

    static func calculate(from usage: UsageResponse, now: Date = Date()) -> PacingResult? {
        guard let bucket = usage.sevenDay,
              let resetsAt = bucket.resetsAtDate
        else { return nil }

        let totalDuration: TimeInterval = 7 * 24 * 3600
        let startOfPeriod = resetsAt.addingTimeInterval(-totalDuration)
        let elapsed = now.timeIntervalSince(startOfPeriod) / totalDuration
        let clampedElapsed = min(max(elapsed, 0), 1)

        let expectedUsage = clampedElapsed * 100
        let delta = bucket.utilization - expectedUsage

        let zone: PacingZone
        let messages: [String]
        if delta < -10 {
            zone = .chill
            messages = chillMessages
        } else if delta > 10 {
            zone = .hot
            messages = hotMessages
        } else {
            zone = .onTrack
            messages = onTrackMessages
        }

        let messageKey = messages.randomElement() ?? messages[0]
        let message = String(localized: String.LocalizationValue(messageKey))

        return PacingResult(
            delta: delta,
            expectedUsage: expectedUsage,
            actualUsage: bucket.utilization,
            zone: zone,
            message: message,
            resetDate: resetsAt
        )
    }
}
