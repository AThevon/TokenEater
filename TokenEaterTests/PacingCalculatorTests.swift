import Testing
import Foundation

@Suite("PacingCalculator")
struct PacingCalculatorTests {

    // MARK: - Helper

    /// Truncate to whole seconds so ISO8601 round-trip is lossless.
    private static func stableNow() -> Date {
        Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    }

    private func makeResetsAt(elapsedFraction: Double, now: Date) -> String {
        let totalDuration: TimeInterval = 7 * 24 * 3600
        let resetsAt = now.addingTimeInterval((1 - elapsedFraction) * totalDuration)
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

    @Test("delta just above +10 is hot")
    func deltaJustAbovePlus10IsHot() {
        let now = Self.stableNow()
        // At 50% elapsed, expected = 50. utilization = 61 → delta ≈ +11
        let usage = UsageResponse.fixture(
            sevenDayUtil: 61,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result?.zone == .hot)
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

    @Test("at start of period (elapsed ≈ 0) even small usage is hot")
    func startOfPeriodSmallUsageIsHot() {
        let now = Self.stableNow()
        // elapsed ≈ 1% → expected ≈ 1. Utilization = 20 → delta ≈ +19
        let usage = UsageResponse.fixture(
            sevenDayUtil: 20,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.01, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result?.zone == .hot)
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
}
