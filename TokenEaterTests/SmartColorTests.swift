import Testing
import Foundation

/// Tests for the smart-color v2 risk model. Builds on the validation
/// matrix in the design document: each scenario asserts the continuous
/// risk score lands in the expected band, and that zone derivation
/// (with optional hysteresis) returns the correct discrete bucket.
///
/// Pure functional tests - no UI, no async, no UserDefaults.
@Suite("SmartColor")
struct SmartColorTests {

    // MARK: - Defaults used across scenarios

    private let defaults = (θw: 0.60, θc: 0.85, m: 0.10)

    // MARK: - Helpers

    /// Builds a synthetic resetDate that yields a desired elapsed
    /// fraction `e` for a given window. Reused so test scenarios stay
    /// readable as "u, e" pairs instead of date arithmetic.
    private func resetDate(elapsed: Double, window: TimeInterval, now: Date = Date()) -> Date {
        let remaining = max(0, (1 - elapsed)) * window
        return now.addingTimeInterval(remaining)
    }

    private func risk(u: Double, e: Double, m: Double = 0.10) -> Double {
        SmartColor.combinedRisk(u: u, e: e, θw: 0.60, θc: 0.85, m: m)
    }

    // MARK: - Mathematical primitives

    @Test("smoothstep produces 0 at lower bound and 1 at upper bound")
    func smoothstepBounds() {
        #expect(SmartColor.smoothstep(0.5, 0.8, 0.5) == 0)
        #expect(SmartColor.smoothstep(0.5, 0.8, 0.8) == 1)
    }

    @Test("smoothstep clamps below lower bound to 0")
    func smoothstepBelow() {
        #expect(SmartColor.smoothstep(0.5, 0.8, 0.3) == 0)
    }

    @Test("smoothstep clamps above upper bound to 1")
    func smoothstepAbove() {
        #expect(SmartColor.smoothstep(0.5, 0.8, 0.9) == 1)
    }

    @Test("confidence grows from 0 to nearly 1 over the window")
    func confidenceCurve() {
        #expect(SmartColor.confidence(e: 0.0) == 0)
        #expect(SmartColor.confidence(e: 0.10) > 0.30)
        #expect(SmartColor.confidence(e: 0.10) < 0.45)
        #expect(SmartColor.confidence(e: 0.50) > 0.90)
        #expect(SmartColor.confidence(e: 1.0) > 0.99)
    }

    // MARK: - Validation matrix (mirrors design doc)

    @Test("just started, 1% used at 1% elapsed -> chill")
    func scenarioJustStarted() {
        let r = risk(u: 0.01, e: 0.01)
        #expect(r < 0.30)
        #expect(SmartColor.zoneForRisk(r) == .chill)
    }

    @Test("burst 5% in 1% elapsed -> chill (confidence damps panic)")
    func scenarioEarlyBurst() {
        // Without confidence, projection would scream. Confidence
        // reduces the weight to ~5% of the raw projection.
        let r = risk(u: 0.05, e: 0.01)
        #expect(r < 0.30)
        #expect(SmartColor.zoneForRisk(r) == .chill)
    }

    @Test("perfectly on linear pace, halfway -> chill")
    func scenarioOnPace() {
        let r = risk(u: 0.50, e: 0.50)
        #expect(r < 0.30)
        #expect(SmartColor.zoneForRisk(r) == .chill)
    }

    @Test("80% used at 50% elapsed -> hot (way ahead and high)")
    func scenario80At50() {
        let r = risk(u: 0.80, e: 0.50)
        #expect(r >= 0.78)
        #expect(SmartColor.zoneForRisk(r) == .hot)
    }

    @Test("KEY FIX -> 98% used with 30 min remaining (e=0.90) -> hot, not green")
    func scenarioCriticalLowTime() {
        let r = risk(u: 0.98, e: 0.90)
        #expect(r >= 0.78, "98% utilization MUST trigger hot regardless of time remaining")
        #expect(SmartColor.zoneForRisk(r) == .hot)
    }

    @Test("50% used at 90% elapsed -> chill (low absolute, behind pace)")
    func scenarioLowAt90() {
        let r = risk(u: 0.50, e: 0.90)
        #expect(r < 0.30)
        #expect(SmartColor.zoneForRisk(r) == .chill)
    }

    @Test("KEY FIX -> 75% at 1h01min vs 75% at 59min should give SAME band (no cliff)")
    func scenarioNoCliffAtHourBoundary() {
        // Within a 5h window: 1h01min remaining => e ≈ 0.7967
        // 59min remaining => e ≈ 0.8033
        let rJustBefore = risk(u: 0.75, e: 0.7967)
        let rJustAfter  = risk(u: 0.75, e: 0.8033)
        #expect(abs(rJustBefore - rJustAfter) < 0.05, "Risk must be continuous around the 1h boundary")
        #expect(SmartColor.zoneForRisk(rJustBefore) == SmartColor.zoneForRisk(rJustAfter))
    }

    @Test("95% with 5 min remaining -> hot (close to limit AND nearly out of time)")
    func scenarioVeryCriticalLowTime() {
        let r = risk(u: 0.95, e: 0.983)
        #expect(r >= 0.78)
        #expect(SmartColor.zoneForRisk(r) == .hot)
    }

    @Test("30% used with 1 min remaining -> chill (low absolute, soon-resetting safe)")
    func scenarioLowUtilImminent() {
        let r = risk(u: 0.30, e: 0.997)
        #expect(r < 0.30)
        #expect(SmartColor.zoneForRisk(r) == .chill)
    }

    @Test("100% utilization always -> hot (hard cap)")
    func scenarioHardCap() {
        // Multiple e values - should always be hot
        for e in [0.0, 0.25, 0.50, 0.75, 1.0] {
            let r = risk(u: 1.0, e: e)
            #expect(r == 1.0, "u=100% must yield risk=1.0 regardless of e (got \(r) at e=\(e))")
            #expect(SmartColor.zoneForRisk(r) == .hot)
        }
    }

    // MARK: - Continuity

    @Test("Risk is continuous across small u perturbations near threshold boundaries")
    func continuityAcrossWarningBoundary() {
        // Continuity check: tiny perturbations of u around the warning
        // threshold (0.60) must not produce a step-jump. The bound is
        // generous because at e=0.50 the projection smoothstep is
        // near its maximum slope (1/0.4 amplification), so the model
        // is rightfully steep here - we just want to confirm there is
        // no discrete cliff.
        for delta in [0.001, 0.005, 0.01] {
            let rBelow = risk(u: 0.60 - delta, e: 0.50)
            let rAbove = risk(u: 0.60 + delta, e: 0.50)
            #expect(abs(rAbove - rBelow) < 0.20, "Discontinuity detected across warning threshold (delta=\(delta), |Δr|=\(abs(rAbove - rBelow)))")
        }
    }

    @Test("Risk monotonically non-decreasing in u (e fixed)")
    func monotonicityInU() {
        let e = 0.50
        var prev: Double = -1
        for u in stride(from: 0.0, through: 1.0, by: 0.05) {
            let r = risk(u: u, e: e)
            #expect(r >= prev, "Risk decreased when u increased: u=\(u) prev=\(prev) now=\(r)")
            prev = r
        }
    }

    // MARK: - Hysteresis

    @Test("Zone resolution with no previous matches strict thresholds")
    func zoneNoHysteresisMatchesRising() {
        // Just under chill->onTrack rising threshold
        #expect(SmartColor.zoneForRisk(0.29) == .chill)
        // At rising threshold
        #expect(SmartColor.zoneForRisk(0.30) == .onTrack)
        // Just under onTrack->warning
        #expect(SmartColor.zoneForRisk(0.54) == .onTrack)
        // At rising threshold
        #expect(SmartColor.zoneForRisk(0.55) == .warning)
        // At warning->hot
        #expect(SmartColor.zoneForRisk(0.78) == .hot)
        #expect(SmartColor.zoneForRisk(0.77) == .warning)
    }

    @Test("Hysteresis prevents flicker when r oscillates around a boundary")
    func hysteresisPreventsFlicker() {
        // We're in `warning` (>= 0.55). r drops to 0.54 - normally
        // that'd cross down to onTrack, but with hysteresis (falling
        // threshold = 0.50) we stay warning until r < 0.50.
        let stayWarning = SmartColor.zoneForRisk(0.54, previous: .warning)
        #expect(stayWarning == .warning)

        let dropToOnTrack = SmartColor.zoneForRisk(0.49, previous: .warning)
        #expect(dropToOnTrack == .onTrack)

        // We're in `hot` (>= 0.78). r drops to 0.77 - stay hot until < 0.73.
        let stayHot = SmartColor.zoneForRisk(0.74, previous: .hot)
        #expect(stayHot == .hot)
        let dropToWarning = SmartColor.zoneForRisk(0.72, previous: .hot)
        #expect(dropToWarning == .warning)
    }

    @Test("Hysteresis still escalates immediately when risk genuinely climbs")
    func hysteresisDoesNotBlockRising() {
        // From chill, climbing risk should escalate to the right zone.
        #expect(SmartColor.zoneForRisk(0.50, previous: .chill) == .onTrack)
        #expect(SmartColor.zoneForRisk(0.60, previous: .chill) == .warning)
        #expect(SmartColor.zoneForRisk(0.85, previous: .chill) == .hot)
    }

    // MARK: - Backwards compatibility (smartLevel mapping)

    @Test("Legacy smartLevel maps from continuous risk consistently")
    func legacyLevelMapping() {
        // Defaults to back-compat with existing notification logic:
        // r < 0.50 -> .normal, 0.50 <= r < 0.78 -> .warning, >= 0.78 -> .critical
        #expect(SmartColor.legacyLevel(forRisk: 0.0)  == .normal)
        #expect(SmartColor.legacyLevel(forRisk: 0.49) == .normal)
        #expect(SmartColor.legacyLevel(forRisk: 0.50) == .warning)
        #expect(SmartColor.legacyLevel(forRisk: 0.77) == .warning)
        #expect(SmartColor.legacyLevel(forRisk: 0.78) == .critical)
        #expect(SmartColor.legacyLevel(forRisk: 1.0)  == .critical)
    }

    // MARK: - End-to-end through ThemeColors API

    @Test("smartRisk via ThemeColors honors a 5h window with 30min remaining + 98% util -> 1.0")
    func endToEndCriticalScenario() {
        let theme = ThemeColors.default
        let now = Date()
        let window: TimeInterval = 5 * 3600  // 5h
        let resetIn30min = now.addingTimeInterval(30 * 60)

        let r = theme.smartRisk(
            utilization: 98,
            resetDate: resetIn30min,
            windowDuration: window,
            thresholds: .default,
            pacingMargin: 10,
            now: now
        )
        #expect(r >= 0.78, "98% util with 30min remaining must surface as hot (got \(r))")
    }

    @Test("smartRisk falls back to threshold-only when resetDate is nil")
    func fallbackWithoutResetDate() {
        let theme = ThemeColors.default
        let r = theme.smartRisk(
            utilization: 90,
            resetDate: nil,
            windowDuration: 5 * 3600,
            thresholds: .default,
            pacingMargin: 10,
            now: Date()
        )
        // u=0.90 with thresholds (0.60, 0.85) -> well past critical -> 1.0 (smoothstep clamped)
        #expect(r >= 0.95)
    }
}
