import Foundation

enum PacingCalculator {
    /// Messages cycle through 3 variants per zone, picked deterministically from
    /// the absolute delta so the same metric does not flip wording on every refresh.
    /// Two surface families: short (5h session, sprint feel) and long (weekly,
    /// marathon feel). Sonnet/Design weekly buckets reuse the long set.
    private static let sessionMessages: [PacingZone: [String]] = [
        .chill:   ["pacing.session.chill.1", "pacing.session.chill.2", "pacing.session.chill.3"],
        .onTrack: ["pacing.session.ontrack.1", "pacing.session.ontrack.2", "pacing.session.ontrack.3"],
        .warning: ["pacing.session.warning.1", "pacing.session.warning.2", "pacing.session.warning.3"],
        .hot:     ["pacing.session.hot.1", "pacing.session.hot.2", "pacing.session.hot.3"],
    ]
    private static let weeklyMessages: [PacingZone: [String]] = [
        .chill:   ["pacing.weekly.chill.1", "pacing.weekly.chill.2", "pacing.weekly.chill.3"],
        .onTrack: ["pacing.weekly.ontrack.1", "pacing.weekly.ontrack.2", "pacing.weekly.ontrack.3"],
        .warning: ["pacing.weekly.warning.1", "pacing.weekly.warning.2", "pacing.weekly.warning.3"],
        .hot:     ["pacing.weekly.hot.1", "pacing.weekly.hot.2", "pacing.weekly.hot.3"],
    ]

    static func calculate(from usage: UsageResponse, margin: Double = 10, now: Date = Date()) -> PacingResult? {
        calculate(from: usage, bucket: .sevenDay, margin: margin, now: now)
    }

    static func calculate(from usage: UsageResponse, bucket: PacingBucket, margin: Double = 10, now: Date = Date()) -> PacingResult? {
        let usageBucket: UsageBucket?
        switch bucket {
        case .fiveHour: usageBucket = usage.fiveHour
        case .sevenDay: usageBucket = usage.sevenDay
        case .sonnet: usageBucket = usage.sevenDaySonnet
        }
        return calculateForBucket(usageBucket, bucket: bucket, margin: margin, now: now)
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

    private static func calculateForBucket(_ usageBucket: UsageBucket?, bucket: PacingBucket, margin: Double = 10, now: Date = Date()) -> PacingResult? {
        guard let usageBucket, let resetsAt = usageBucket.resetsAtDate else { return nil }

        let duration = bucket.periodDuration
        let startOfPeriod = resetsAt.addingTimeInterval(-duration)
        let elapsed = now.timeIntervalSince(startOfPeriod) / duration
        let clampedElapsed = min(max(elapsed, 0), 1)

        let expectedUsage = clampedElapsed * 100
        let delta = usageBucket.utilization - expectedUsage

        // 4-zone pacing -> chill / onTrack (within ±margin) / warning (margin..2*margin)
        // / hot (>2*margin). The pacingMargin slider drives both thresholds so a
        // single user-facing setting controls the whole sensitivity curve.
        let zone: PacingZone
        if delta < -margin {
            zone = .chill
        } else if delta <= margin {
            zone = .onTrack
        } else if delta <= margin * 2 {
            zone = .warning
        } else {
            zone = .hot
        }

        let pool = (bucket == .fiveHour ? sessionMessages : weeklyMessages)[zone] ?? []
        let index = pool.isEmpty ? 0 : abs(Int(delta)) % pool.count
        let messageKey = pool.isEmpty ? "" : pool[index]
        let message = messageKey.isEmpty ? "" : String(localized: String.LocalizationValue(messageKey))

        return PacingResult(
            delta: delta,
            expectedUsage: expectedUsage,
            actualUsage: usageBucket.utilization,
            zone: zone,
            message: message,
            resetDate: resetsAt
        )
    }
}
