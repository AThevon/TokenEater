import Foundation

/// Adaptive refresh speed for the usage poller.
enum RefreshSpeed: TimeInterval {
    case fast = 120      // After FSEvents token change - 2min
    case normal = 300    // Steady state - configurable via settings (default 5min)
    case slow = 1200     // After 429 - 2x normal or 20min minimum
}

/// Pure rate-limit backoff policy for the usage poller. Anthropic's
/// /api/oauth/usage returns 429 with no useful Retry-After (see
/// anthropics/claude-code#31637 + #31021), so a missing or zero hint falls back
/// to a capped exponential ladder; a real positive hint is honoured verbatim.
struct RateLimitBackoff {
    /// Exponential ladder, in seconds: 30 min -> 1 h -> 2 h -> 4 h -> 6 h cap.
    static let schedule: [TimeInterval] = [
        30 * 60,
        60 * 60,
        2 * 3600,
        4 * 3600,
        6 * 3600,
    ]

    /// Computes the next allowed retry date after a 429.
    /// - Parameters:
    ///   - consecutiveRateLimits: count of back-to-back 429s seen so far (0 on the first).
    ///   - serverRetryAfter: parsed Retry-After in seconds, if the server sent a usable one.
    ///   - now: injected clock.
    /// - Returns: the retry date and the updated consecutive count (bumped only
    ///   when the exponential path is taken).
    static func nextRetryDate(
        consecutiveRateLimits: Int,
        serverRetryAfter: TimeInterval?,
        now: Date = Date()
    ) -> (date: Date, consecutiveRateLimits: Int) {
        if let r = serverRetryAfter, r > 0 {
            return (now.addingTimeInterval(r), consecutiveRateLimits)
        }
        let bumped = consecutiveRateLimits + 1
        let idx = min(bumped - 1, schedule.count - 1)
        return (now.addingTimeInterval(schedule[idx]), bumped)
    }

    /// Effective poll interval given the adaptive speed and the user's base interval.
    static func effectiveInterval(speed: RefreshSpeed, baseInterval: TimeInterval) -> TimeInterval {
        switch speed {
        case .fast: return min(120, baseInterval)
        case .normal: return baseInterval
        case .slow: return max(baseInterval * 2, 1200)
        }
    }
}
