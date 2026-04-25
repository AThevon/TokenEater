import Foundation

enum PacingCalculator {
    private static let chillMessages = [
        "pacing.chill.1", "pacing.chill.2", "pacing.chill.3",
    ]
    private static let onTrackMessages = [
        "pacing.ontrack.1", "pacing.ontrack.2", "pacing.ontrack.3",
    ]
    private static let warningMessages = [
        "pacing.warning.1", "pacing.warning.2", "pacing.warning.3",
    ]
    private static let hotMessages = [
        "pacing.hot.1", "pacing.hot.2", "pacing.hot.3",
    ]

    static func calculate(from usage: UsageResponse, margin: Double = 10, now: Date = Date()) -> PacingResult? {
        calculateForBucket(usage.sevenDay, duration: PacingBucket.sevenDay.periodDuration, margin: margin, now: now)
    }

    static func calculate(from usage: UsageResponse, bucket: PacingBucket, margin: Double = 10, now: Date = Date()) -> PacingResult? {
        let usageBucket: UsageBucket?
        switch bucket {
        case .fiveHour: usageBucket = usage.fiveHour
        case .sevenDay: usageBucket = usage.sevenDay
        case .sonnet: usageBucket = usage.sevenDaySonnet
        }
        return calculateForBucket(usageBucket, duration: bucket.periodDuration, margin: margin, now: now)
    }

    static func calculateAll(from usage: UsageResponse, margin: Double = 10, now: Date = Date()) -> [PacingBucket: PacingResult] {
        var results: [PacingBucket: PacingResult] = [:]
        for bucket in PacingBucket.allCases {
            if let result = calculate(from: usage, bucket: bucket, margin: margin, now: now) {
                results[bucket] = result
            }
        }
        return results
    }

    private static func calculateForBucket(_ bucket: UsageBucket?, duration: TimeInterval, margin: Double = 10, now: Date = Date()) -> PacingResult? {
        guard let bucket, let resetsAt = bucket.resetsAtDate else { return nil }

        let startOfPeriod = resetsAt.addingTimeInterval(-duration)
        let elapsed = now.timeIntervalSince(startOfPeriod) / duration
        let clampedElapsed = min(max(elapsed, 0), 1)

        let expectedUsage = clampedElapsed * 100
        let delta = bucket.utilization - expectedUsage

        // 4-zone pacing -> chill / onTrack (within ±margin) / warning (margin..2*margin)
        // / hot (>2*margin). The pacingMargin slider drives both thresholds so a
        // single user-facing setting controls the whole sensitivity curve.
        let zone: PacingZone
        let messages: [String]
        if delta < -margin {
            zone = .chill
            messages = chillMessages
        } else if delta <= margin {
            zone = .onTrack
            messages = onTrackMessages
        } else if delta <= margin * 2 {
            zone = .warning
            messages = warningMessages
        } else {
            zone = .hot
            messages = hotMessages
        }

        let index = abs(Int(delta)) % messages.count
        let messageKey = messages[index]
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
