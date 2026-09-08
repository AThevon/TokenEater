import Foundation

/// Decides whether a rate-limit window has actually rolled over since the last
/// poll, so the app can announce "your quota is back" exactly once.
///
/// The naive rule (the deadline moved forward) is wrong for Codex: a window
/// nobody has touched reports `reset_at = now + window` on every single poll, so
/// its deadline slides continuously and would fire an alert every refresh
/// interval, forever. The two extra conditions below distinguish a real
/// rollover from that sliding:
///
/// - usage dropped: the previous poll saw real usage and this one sees less,
///   which only happens when the counter was cleared;
/// - deadline passed: the previously announced deadline is now in the past, so
///   the window we were watching genuinely ended (covers a Mac that was asleep
///   across the reset and woke up to an already-fresh window).
///
/// An idle window satisfies neither: its usage never leaves zero and its
/// deadline is always in the future.
enum CodexResetDetector {

    // MARK: - Nested Types

    struct Observation: Equatable {
        let usedPercent: Double
        let resetAt: Date

        init(usedPercent: Double, resetAt: Date) {
            self.usedPercent = usedPercent
            self.resetAt = resetAt
        }
    }

    // MARK: - Type Methods

    /// True when `current` belongs to a new window compared to `previous`.
    /// The first observation of a window never fires: with nothing to compare
    /// against, a fresh install would otherwise announce a reset that the user
    /// did not experience.
    static func didReset(
        previous: Observation?,
        current: Observation,
        windowDuration: TimeInterval,
        now: Date = Date()
    ) -> Bool {
        guard let previous else { return false }

        // Tolerance absorbs clock skew and the server rounding `reset_at` to the
        // second, while staying far below a real window's length.
        let tolerance = max(60, windowDuration * 0.02)
        let movedForward = current.resetAt.timeIntervalSince(previous.resetAt) > tolerance
        guard movedForward else { return false }

        let usageDropped = previous.usedPercent > 0 && current.usedPercent < previous.usedPercent
        let deadlinePassed = previous.resetAt <= now
        return usageDropped || deadlinePassed
    }
}
