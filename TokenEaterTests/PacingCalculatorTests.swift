import Testing
import Foundation

@Suite("PacingCalculator")
struct PacingCalculatorTests {

    // MARK: - Helper

    private func makeResetsAt(elapsedFraction: Double, now: Date = Date()) -> String {
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
        let now = Date()
        let usage = UsageResponse.fixture(
            sevenDayUtil: 20,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result != nil)
        #expect(result?.zone == .chill)
    }

    @Test("hot zone when utilization far above expected")
    func hotZoneWhenOverPacing() {
        let now = Date()
        let usage = UsageResponse.fixture(
            sevenDayUtil: 80,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result != nil)
        #expect(result?.zone == .hot)
    }

    @Test("onTrack when utilization close to expected")
    func onTrackWhenMatchingPace() {
        let now = Date()
        let usage = UsageResponse.fixture(
            sevenDayUtil: 50,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result != nil)
        #expect(result?.zone == .onTrack)
    }

    // MARK: - Delta sign

    @Test("delta is positive when over-pacing")
    func deltaPositiveWhenOverPacing() {
        let now = Date()
        let usage = UsageResponse.fixture(
            sevenDayUtil: 80,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result != nil)
        #expect((result?.delta ?? 0) > 0)
    }

    @Test("delta is negative when under-pacing")
    func deltaNegativeWhenUnderPacing() {
        let now = Date()
        let usage = UsageResponse.fixture(
            sevenDayUtil: 20,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let result = PacingCalculator.calculate(from: usage, now: now)
        #expect(result != nil)
        #expect((result?.delta ?? 0) < 0)
    }
}
