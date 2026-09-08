import Foundation

/// Turns a raw usage payload into ordered, formatted window snapshots.
///
/// Pure and shared by the store, the widget and the connection test so no
/// surface re-derives window classification, countdown strings or pacing on its
/// own (and none of them can disagree about which window is the session one).
enum CodexWindowResolver {

    // MARK: - Type Methods

    static func windows(
        in usage: CodexUsageResponse,
        margin: Double = 10,
        schedule: PacingSchedule = .rolling,
        now: Date = Date()
    ) -> [CodexWindowSnapshot] {
        guard let rateLimit = usage.rateLimit else { return [] }
        return rateLimit.windows
            .map { snapshot(for: $0, margin: margin, schedule: schedule, now: now) }
            .sorted { lhs, rhs in
                if lhs.kind.displayOrder != rhs.kind.displayOrder {
                    return lhs.kind.displayOrder < rhs.kind.displayOrder
                }
                return lhs.windowDuration < rhs.windowDuration
            }
    }

    static func snapshot(
        for window: CodexRateWindow,
        margin: Double = 10,
        schedule: PacingSchedule = .rolling,
        now: Date = Date()
    ) -> CodexWindowSnapshot {
        let kind = window.kind
        let resetDate = window.resetDate

        // Session windows read like the Claude 5h bucket (a countdown), weekly
        // ones like the 7d bucket (a weekday + time).
        let formatted = kind == .session
            ? ResetCountdownFormatter.session(from: resetDate, now: now)
            : ResetCountdownFormatter.weekly(from: resetDate, now: now)

        let pacing: PacingResult? = resetDate.flatMap { reset in
            PacingCalculator.calculate(
                utilization: window.usedPercent,
                resetsAt: reset,
                windowDuration: window.windowDuration,
                isIntraday: kind.isIntraday,
                messagePool: kind.messagePool,
                margin: margin,
                now: now,
                activeDays: schedule.effectiveActiveDays,
                activeHours: schedule.effectiveHours
            )
        }

        return CodexWindowSnapshot(
            kind: kind,
            pct: window.pct,
            utilization: window.usedPercent,
            resetDate: resetDate,
            windowDuration: window.windowDuration,
            isIdle: window.isIdle,
            relativeReset: formatted.relative,
            absoluteReset: formatted.absolute,
            pacing: pacing
        )
    }
}
