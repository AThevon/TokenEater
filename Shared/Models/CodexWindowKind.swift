import Foundation

/// What a Codex rate-limit window represents, derived from its duration rather
/// than its position in the payload.
///
/// This distinction is load-bearing: the API's `primary_window` is the 5h
/// session window on `plus` / `pro`, but the *weekly* one on plans that have no
/// session window at all (`prolite` returns a 604 800 s primary and a null
/// secondary). Anything keyed on "primary means session" mislabels those
/// accounts and gives them the wrong notification cadence.
enum CodexWindowKind: String, Codable, CaseIterable, Sendable {
    /// Short rolling window, 5 h in every payload observed so far.
    case session
    /// Long rolling window, 7 days in every payload observed so far.
    case weekly
    /// Neither shape. Defensive: renders with a duration-derived label instead
    /// of being dropped, so a new backend window still shows up.
    case other

    /// Boundaries are deliberately wide: they only have to separate "intraday"
    /// from "multi-day", not pin exact values the backend may tune.
    static func classify(seconds: Int) -> CodexWindowKind {
        if seconds <= 0 { return .other }
        if seconds <= 6 * 3600 { return .session }
        if seconds >= 5 * 86_400 { return .weekly }
        return .other
    }

    /// Short label for gauges and tiles: "5h", "Weekly", "12h", "3d".
    func label(for duration: TimeInterval) -> String {
        switch self {
        case .weekly:
            return String(localized: "codex.window.weekly")
        case .session, .other:
            let seconds = Int(duration)
            guard seconds > 0 else { return String(localized: "codex.window.unknown") }
            if seconds % 86_400 == 0, seconds >= 86_400 { return "\(seconds / 86_400)d" }
            if seconds >= 3600 { return "\(seconds / 3600)h" }
            return "\(max(1, seconds / 60))min"
        }
    }

    /// Whether a workweek pacing schedule applies. Intraday windows always
    /// measure on the calendar clock, matching how the Claude 5h bucket behaves.
    var isIntraday: Bool { self == .session }

    /// Which pacing quip family this window draws from.
    var messagePool: PacingMessagePool { self == .session ? .session : .weekly }

    /// Sort order for the UI: session first, then weekly, then anything else.
    var displayOrder: Int {
        switch self {
        case .session: return 0
        case .weekly: return 1
        case .other: return 2
        }
    }
}

/// View-facing snapshot of one Codex window, published by `CodexUsageStore`.
/// Everything the menu bar, dashboard and widget need, already formatted, so no
/// surface recomputes pacing or countdowns on its own.
struct CodexWindowSnapshot: Equatable, Identifiable {
    let kind: CodexWindowKind
    let pct: Int
    let utilization: Double
    let resetDate: Date?
    let windowDuration: TimeInterval
    let isIdle: Bool
    let relativeReset: String
    let absoluteReset: String
    let pacing: PacingResult?

    var id: String { "\(kind.rawValue)-\(Int(windowDuration))" }

    var label: String { kind.label(for: windowDuration) }
}

// MARK: - Notification bridging

extension CodexWindowSnapshot {
    /// Adapts the window to the shape `NotificationService` evaluates, so Codex
    /// windows go through the same threshold and Smart Color logic as the
    /// Claude buckets instead of a parallel copy of it.
    var metricSnapshot: MetricSnapshot {
        MetricSnapshot(
            pct: pct,
            resetsAt: resetDate,
            windowDuration: windowDuration,
            utilization: utilization
        )
    }
}
