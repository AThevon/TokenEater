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

    @Test("pre-critical utilization with moderate remaining lands in warning band")
    func projectedRiskWarning() {
        // 80% utilization with 90 min left: risk = 72 (between 70 and 100) -> warning.
        let observed = color(80, minutesRemaining: 90)
        let expected = theme.gaugeNSColor(for: 75, thresholds: thresholds)
        #expect(observed == expected)
    }
}
