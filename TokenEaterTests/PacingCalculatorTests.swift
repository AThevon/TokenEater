import Testing
import Foundation

@Suite("PacingCalculator")
struct PacingCalculatorTests {

    // MARK: - Helper

    /// Truncate to whole seconds so ISO8601 round-trip is lossless.
    private static func stableNow() -> Date {
        Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    }

    private func makeResetsAt(elapsedFraction: Double, now: Date, duration: TimeInterval = 7 * 24 * 3600) -> String {
        let resetsAt = now.addingTimeInterval((1 - elapsedFraction) * duration)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: resetsAt)
    }

    // MARK: - Nil cases

    @Test("returns nil when sevenDay is nil")
    func returnsNilWhenSevenDayIsNil() {
        let usage = UsageResponse()
        let result = PacingCalculator.calculate(from: usage)
        #expect(result == nil)
    }

    @Test("returns nil when resetsAt is nil")
    func returnsNilWhenResetsAtIsNil() {
        let usage = UsageResponse(sevenDay: .fixture(utilization: 50, resetsAt: nil))
        let result = PacingCalculator.calculate(from: usage)
        #expect(result == nil)
    }

    // MARK: - Zone classification

    @Test("chill zone when utilization far below expected")
    func chillZoneWhenUnderPacing() {
        let now = Self.stableNow()
        let usage = UsageResponse.fixture(
            sevenDayUtil: 20,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result?.zone == .chill)
    }

    @Test("hot zone when utilization far above expected")
    func hotZoneWhenOverPacing() {
        let now = Self.stableNow()
        let usage = UsageResponse.fixture(
            sevenDayUtil: 80,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result?.zone == .hot)
    }

    @Test("onTrack when utilization close to expected")
    func onTrackWhenMatchingPace() {
        let now = Self.stableNow()
        let usage = UsageResponse.fixture(
            sevenDayUtil: 50,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result?.zone == .onTrack)
    }

    // MARK: - Delta sign

    @Test("delta is positive when over-pacing")
    func deltaPositiveWhenOverPacing() {
        let now = Self.stableNow()
        let usage = UsageResponse.fixture(
            sevenDayUtil: 80,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect((result?.delta ?? 0) > 0)
    }

    @Test("delta is negative when under-pacing")
    func deltaNegativeWhenUnderPacing() {
        let now = Self.stableNow()
        let usage = UsageResponse.fixture(
            sevenDayUtil: 20,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect((result?.delta ?? 0) < 0)
    }

    // MARK: - Exact delta value

    @Test("delta equals utilization minus expected usage")
    func deltaEqualsUtilizationMinusExpected() {
        let now = Self.stableNow()
        // At 50% elapsed, expected = 50. Utilization = 75 → delta = 25
        let usage = UsageResponse.fixture(
            sevenDayUtil: 75,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result != nil)
        // Allow small floating-point tolerance
        let delta = result!.delta
        #expect(abs(delta - 25) < 1)
        #expect(abs(result!.expectedUsage - 50) < 1)
    }

    // MARK: - Threshold boundaries (±10)

    @Test("delta exactly +10 is onTrack (not hot)")
    func deltaExactlyPlus10IsOnTrack() {
        let now = Self.stableNow()
        // At 50% elapsed, expected = 50. Need utilization = 60 → delta = +10
        let usage = UsageResponse.fixture(
            sevenDayUtil: 60,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result != nil)
        #expect(result?.zone == .onTrack)
    }

    @Test("delta exactly -10 is onTrack (not chill)")
    func deltaExactlyMinus10IsOnTrack() {
        let now = Self.stableNow()
        // At 50% elapsed, expected = 50. Need utilization = 40 → delta = -10
        let usage = UsageResponse.fixture(
            sevenDayUtil: 40,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result != nil)
        #expect(result?.zone == .onTrack)
    }

    @Test("delta just above +10 is warning (between margin and 2x margin)")
    func deltaJustAbovePlus10IsWarning() {
        let now = Self.stableNow()
        // At 50% elapsed, expected = 50. utilization = 61 → delta ≈ +11.
        // With margin 10, the warning band is (10..20], so +11 lands in warning.
        let usage = UsageResponse.fixture(
            sevenDayUtil: 61,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result?.zone == .warning)
    }

    @Test("delta just below -10 is chill")
    func deltaJustBelowMinus10IsChill() {
        let now = Self.stableNow()
        // At 50% elapsed, expected = 50. utilization = 39 → delta ≈ -11
        let usage = UsageResponse.fixture(
            sevenDayUtil: 39,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result?.zone == .chill)
    }

    // MARK: - Boundary values

    @Test("utilization 0% at 50% elapsed is chill")
    func zeroUtilizationIsChill() {
        let now = Self.stableNow()
        let usage = UsageResponse.fixture(
            sevenDayUtil: 0,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result?.zone == .chill)
        #expect((result?.delta ?? 0) < 0)
    }

    @Test("utilization 100% at 50% elapsed is hot")
    func fullUtilizationIsHot() {
        let now = Self.stableNow()
        let usage = UsageResponse.fixture(
            sevenDayUtil: 100,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result?.zone == .hot)
    }

    @Test("at start of period (elapsed ≈ 0) small usage is warning")
    func startOfPeriodSmallUsageIsWarning() {
        let now = Self.stableNow()
        // elapsed ≈ 1% → expected ≈ 1. Utilization = 20 → delta ≈ +19.
        // With margin 10 the warning band is (10..20]; pushing utilization
        // above 30 in this scenario would tip into hot.
        let usage = UsageResponse.fixture(
            sevenDayUtil: 20,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.01, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result?.zone == .warning)
    }

    @Test("at end of period (elapsed ≈ 100%) high usage is onTrack")
    func endOfPeriodHighUsageIsOnTrack() {
        let now = Self.stableNow()
        // elapsed ≈ 99% → expected ≈ 99. Utilization = 95 → delta ≈ -4
        let usage = UsageResponse.fixture(
            sevenDayUtil: 95,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.99, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result?.zone == .onTrack)
    }

    // MARK: - Custom margin

    @Test("custom margin 5: delta +6 is warning (would be onTrack with default 10)")
    func customMargin5MakesSmallDeltaWarning() {
        let now = Self.stableNow()
        // At 50% elapsed, expected = 50. Utilization = 56 → delta = +6.
        // With margin 5, the warning band is (5..10], so +6 lands warning.
        let usage = UsageResponse.fixture(
            sevenDayUtil: 56,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let defaultResult = PacingCalculator.calculate(from: usage, now: now)
        #expect(defaultResult?.zone == .onTrack)

        let tightResult = PacingCalculator.calculate(from: usage, margin: 5, now: now)
        #expect(tightResult?.zone == .warning)
    }

    @Test("custom margin 5: delta -6 is chill (would be onTrack with default 10)")
    func customMargin5MakesSmallNegativeDeltaChill() {
        let now = Self.stableNow()
        // At 50% elapsed, expected = 50. Utilization = 44 → delta = -6
        let usage = UsageResponse.fixture(
            sevenDayUtil: 44,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let defaultResult = PacingCalculator.calculate(from: usage, now: now)
        #expect(defaultResult?.zone == .onTrack)

        let tightResult = PacingCalculator.calculate(from: usage, margin: 5, now: now)
        #expect(tightResult?.zone == .chill)
    }

    @Test("custom margin 20: delta +15 is onTrack (would be warning with default 10)")
    func customMargin20KeepsLargeDeltaOnTrack() {
        let now = Self.stableNow()
        // At 50% elapsed, expected = 50. Utilization = 65 → delta = +15.
        // Default margin 10 → warning band (10..20], so +15 is warning.
        // With margin 20, the onTrack band stretches to ±20, so +15 is onTrack.
        let usage = UsageResponse.fixture(
            sevenDayUtil: 65,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let defaultResult = PacingCalculator.calculate(from: usage, now: now)
        #expect(defaultResult?.zone == .warning)

        let wideResult = PacingCalculator.calculate(from: usage, margin: 20, now: now)
        #expect(wideResult?.zone == .onTrack)
    }

    @Test("custom margin 20: delta -15 is onTrack (would be chill with default 10)")
    func customMargin20KeepsLargeNegativeDeltaOnTrack() {
        let now = Self.stableNow()
        // At 50% elapsed, expected = 50. Utilization = 35 → delta = -15
        let usage = UsageResponse.fixture(
            sevenDayUtil: 35,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let defaultResult = PacingCalculator.calculate(from: usage, now: now)
        #expect(defaultResult?.zone == .chill)

        let wideResult = PacingCalculator.calculate(from: usage, margin: 20, now: now)
        #expect(wideResult?.zone == .onTrack)
    }

    @Test("margin 1: nearly any deviation triggers zone change")
    func margin1VeryTight() {
        let now = Self.stableNow()
        // At 50% elapsed, expected = 50. Utilization = 52 → delta = +2.
        // With margin 1, warning band is (1..2], hot is >2, so +2 lands at the
        // top of warning (the boundary is inclusive on the warning side).
        let usage = UsageResponse.fixture(
            sevenDayUtil: 52,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, margin: 1, now: now)
        #expect(result?.zone == .warning)
    }

    @Test("default margin: existing boundary tests still pass with explicit margin 10")
    func explicitDefaultMarginMatchesImplicit() {
        let now = Self.stableNow()
        // delta = +10 → onTrack
        let usage = UsageResponse.fixture(
            sevenDayUtil: 60,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let implicit = PacingCalculator.calculate(from: usage, now: now)
        let explicit = PacingCalculator.calculate(from: usage, margin: 10, now: now)
        #expect(implicit?.zone == explicit?.zone)
        #expect(implicit?.zone == .onTrack)
    }

    // MARK: - Per-bucket pacing

    @Test("fiveHour bucket uses 5h period duration")
    func fiveHourBucketUses5hPeriod() {
        let now = Self.stableNow()
        // 50% elapsed in a 5h window, utilization = 80 → delta = +30 → hot
        let usage = UsageResponse(
            fiveHour: .fixture(utilization: 80, resetsAt: makeResetsAt(elapsedFraction: 0.5, now: now, duration: 5 * 3600))
        )
        let result = PacingCalculator.calculate(from: usage, bucket: .fiveHour, now: now)
        #expect(result != nil)
        #expect(result?.zone == .hot)
        #expect(abs((result?.delta ?? 0) - 30) < 1)
    }

    @Test("sonnet bucket uses 7d period duration")
    func sonnetBucketUses7dPeriod() {
        let now = Self.stableNow()
        let usage = UsageResponse(
            sevenDaySonnet: .fixture(utilization: 20, resetsAt: makeResetsAt(elapsedFraction: 0.5, now: now))
        )
        let result = PacingCalculator.calculate(from: usage, bucket: .sonnet, now: now)
        #expect(result != nil)
        #expect(result?.zone == .chill)
    }

    @Test("calculateAll returns results for all available buckets")
    func calculateAllReturnsAllBuckets() {
        let now = Self.stableNow()
        let usage = UsageResponse.fixture(
            fiveHourUtil: 80,
            sevenDayUtil: 50,
            sonnetUtil: 20,
            fiveHourResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now, duration: 5 * 3600),
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now),
            sonnetResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let results = PacingCalculator.calculateAll(from: usage, now: now)
        #expect(results.count == 3)
        #expect(results[.fiveHour]?.zone == .hot)
        #expect(results[.sevenDay]?.zone == .onTrack)
        #expect(results[.sonnet]?.zone == .chill)
    }

    @Test("calculateAll skips buckets without reset dates")
    func calculateAllSkipsMissingBuckets() {
        let now = Self.stableNow()
        let usage = UsageResponse.fixture(
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let results = PacingCalculator.calculateAll(from: usage, now: now)
        #expect(results.count == 1)
        #expect(results[.sevenDay] != nil)
    }

    @Test("per-bucket calculate returns nil when bucket is missing")
    func perBucketReturnsNilWhenMissing() {
        let usage = UsageResponse()
        #expect(PacingCalculator.calculate(from: usage, bucket: .fiveHour) == nil)
        #expect(PacingCalculator.calculate(from: usage, bucket: .sonnet) == nil)
    }
}
