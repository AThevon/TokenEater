import Foundation

/// A usage window a widget ring can draw, and which ones it draws for a
/// given response. Every plan but Ultra has a 5-hour session window; Ultra
/// has none (`five_hour` null, no `session` entry in `limits`), so the rings
/// that would show the session show the week instead, and the Overview's
/// freed slot goes to the Fable limit when the plan has one.
enum WidgetUsageWindow: Equatable, CaseIterable {
    case session
    case weekly
    case fable

    /// Length of the window, for Smart Color's projection.
    var windowDuration: TimeInterval {
        switch self {
        case .session: return 5 * 3600
        case .weekly, .fable: return 7 * 86_400
        }
    }

    /// Whether the window lasts days, so its reset reads as a weekday and a
    /// time rather than a countdown.
    var isMultiDay: Bool { self != .session }

    func bucket(in usage: UsageResponse) -> UsageBucket? {
        switch self {
        case .session: return usage.fiveHour
        case .weekly: return usage.sevenDay
        case .fable: return usage.sevenDayFable
        }
    }

    /// The window a single-ring widget (Session Ring, the account widget's
    /// small family) draws: the session when the plan has one, else the
    /// week, else nothing (no window to draw, not a reason to wait).
    static func primary(for usage: UsageResponse) -> WidgetUsageWindow? {
        if usage.fiveHour != nil { return .session }
        if usage.sevenDay != nil { return .weekly }
        return nil
    }

    /// The usage rings of the Overview's medium family, in order, before
    /// pacing and Extra Credits. With a session window: session then week,
    /// exactly as before Ultra. Without one: the week first, then Fable in
    /// the session's place when the plan has that limit.
    static func mediumRings(for usage: UsageResponse) -> [WidgetUsageWindow] {
        let order: [WidgetUsageWindow] = usage.fiveHour != nil ? [.session, .weekly] : [.weekly, .fable]
        return order.filter { $0.bucket(in: usage) != nil }
    }
}
