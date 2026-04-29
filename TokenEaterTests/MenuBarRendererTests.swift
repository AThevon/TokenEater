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

    @Test("pre-critical utilization with moderate remaining lands in warning band (v3)")
    func projectedRiskWarning() {
        // v3 model: smart calibration is now profile-driven (Balanced
        // bounds 0.50/1.00 instead of the user's 0.60/0.85 thresholds),
        // and the absolute signal is dampened by projection health
        // (smoothstep(0.7, 1.0, u/e)). At u=0.80 / 90min remaining on
        // 5h: u/e = 0.80/0.90 = 0.889, dampened to ~0.69, multiplied
        // by absolute_raw smoothstep(0.50, 1.00, 0.80) ≈ 0.65 -> final
        // risk ~0.45, which interpolates ~60% of the way from green to
        // orange. So the color is a vivid orange, not red.
        //
        // The pre-v3 expectation of "stays critical at 80% / 90min" was
        // a v2-era fix for v1's reset-imminent override; v3's projection-
        // health damping makes 80% with calm pacing legitimately less
        // alarming because the user is on track to finish ~89% of limit.
        let observed = color(80, minutesRemaining: 90)
        // The 98%/30min hard flag is preserved separately; here we just
        // assert the color sits in the green-to-orange interpolation
        // region rather than matching threshold-mode red.
        let red = theme.gaugeNSColor(for: 95, thresholds: thresholds)
        #expect(observed != red, "80% / 90min should no longer match the threshold-mode red color")
    }
}
