import SwiftUI

/// Single source of truth for "smart vs threshold" gauge coloring, shared by
/// the Monitoring dashboard, the popover layouts, and (later) the widget.
/// Previously this dispatch was copy-pasted in `PopoverColors`,
/// `MonitoringView.gaugeColor/gaugeGradient`, and `MetricTile.body`.
///
/// Pure over `ThemeColors` (not the store) so the decision is unit-testable.
/// The only per-call-site difference is the gradient's start/end points.
enum GaugeColorMode: Equatable {
    case smart
    case threshold
}

enum GaugeColorResolver {
    /// The decision: Smart Color setting on -> risk-aware; off -> static ramp.
    static func mode(smartColorEnabled: Bool, windowDuration: TimeInterval) -> GaugeColorMode {
        // Smart Color is a time-aware risk model; it needs a window to project
        // over (windowDuration > 0). The smart path itself handles a missing
        // reset date (falls back to absolute risk), so metrics like Opus/Cowork
        // that have a week window but no resets_at still colour via smart.
        // Only metrics with no window at all (e.g. the Extra Credits pool,
        // windowDuration 0) fall back to the static threshold ladder.
        (smartColorEnabled && windowDuration > 0) ? .smart : .threshold
    }

    static func color(
        mode: GaugeColorMode,
        utilization: Int,
        resetDate: Date?,
        windowDuration: TimeInterval,
        theme: ThemeColors,
        thresholds: UsageThresholds,
        pacingMargin: Double,
        now: Date = Date(),
        profile: SmartColorProfile
    ) -> Color {
        switch mode {
        case .smart:
            return theme.smartGaugeColor(
                utilization: Double(utilization),
                resetDate: resetDate,
                windowDuration: windowDuration,
                thresholds: thresholds,
                pacingMargin: pacingMargin,
                now: now,
                profile: profile
            )
        case .threshold:
            return theme.gaugeColor(for: Double(utilization), thresholds: thresholds)
        }
    }

    static func gradient(
        mode: GaugeColorMode,
        utilization: Int,
        resetDate: Date?,
        windowDuration: TimeInterval,
        theme: ThemeColors,
        thresholds: UsageThresholds,
        pacingMargin: Double,
        now: Date = Date(),
        profile: SmartColorProfile,
        startPoint: UnitPoint,
        endPoint: UnitPoint
    ) -> LinearGradient {
        switch mode {
        case .smart:
            return theme.smartGaugeGradient(
                utilization: Double(utilization),
                resetDate: resetDate,
                windowDuration: windowDuration,
                thresholds: thresholds,
                pacingMargin: pacingMargin,
                now: now,
                startPoint: startPoint,
                endPoint: endPoint,
                profile: profile
            )
        case .threshold:
            return theme.gaugeGradient(
                for: Double(utilization),
                thresholds: thresholds,
                startPoint: startPoint,
                endPoint: endPoint
            )
        }
    }
}
