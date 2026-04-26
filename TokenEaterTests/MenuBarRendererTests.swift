import Testing
import Foundation
import AppKit

@Suite("MenuBarRenderer.smartResetNSColor")
struct MenuBarRendererTests {

    private let theme = ThemeColors.default
    private let thresholds = UsageThresholds.default // warning: 60, critical: 85
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func reset(_ minutesAway: Double) -> Date {
        now.addingTimeInterval(minutesAway * 60)
    }

    private func color(_ utilization: Double, minutesRemaining: Double) -> NSColor {
        MenuBarRenderer.smartResetNSColor(
            utilization: utilization,
            resetDate: reset(minutesRemaining),
            themeColors: theme,
            thresholds: thresholds,
            now: now
        )
    }

    @Test("limit reached with short remaining stays critical")
    func limitReachedShortRemainingCritical() {
        // Bug repro: utilization 100%, 20 min left -> risk score = 20 which
        // used to map to the normal (green) gauge color. With the fix, any
        // utilization at or above the critical threshold must return the
        // critical color regardless of remaining time.
        let observed = color(100, minutesRemaining: 20)
        let expected = theme.gaugeNSColor(for: 100, thresholds: thresholds)
        #expect(observed == expected)
    }

    @Test("limit reached with long remaining stays critical")
    func limitReachedLongRemainingCritical() {
        let observed = color(95, minutesRemaining: 240)
        let expected = theme.gaugeNSColor(for: 95, thresholds: thresholds)
        #expect(observed == expected)
    }

    @Test("low utilization near reset stays normal")
    func lowUtilizationShortRemainingNormal() {
        // 30% with 15 min left: risk = 4.5 -> normal color.
        let observed = color(30, minutesRemaining: 15)
        let expected = theme.gaugeNSColor(for: 10, thresholds: thresholds)
        #expect(observed == expected)
    }

    @Test("high pre-critical utilization with ample remaining escalates to critical")
    func projectedRiskEscalatesToCritical() {
        // 80% utilization (below critical 85) with 3h left: risk = 144 -> critical band.
        let observed = color(80, minutesRemaining: 180)
        let expected = theme.gaugeNSColor(for: 100, thresholds: thresholds)
        #expect(observed == expected)
    }

    @Test("pre-critical utilization with moderate remaining stays in critical band (v2)")
    func projectedRiskWarning() {
        // v2 model: at u=0.80, absolute risk smoothstep(0.60, 0.85, 0.80)
        // already lands ~0.90 - well past the 0.85 critical anchor. The
        // legacy v1 expectation of "warning band at 80% / 90min" is no
        // longer correct: the absolute component alone makes 80% red,
        // independent of the remaining-minutes projection. This is the
        // intended v2 behaviour (no override, no soft cap).
        let observed = color(80, minutesRemaining: 90)
        let expected = theme.gaugeNSColor(for: 95, thresholds: thresholds)
        #expect(observed == expected)
    }
}
