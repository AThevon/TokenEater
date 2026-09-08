import Testing
import Foundation

@Suite("PacingCalculator provider-neutral window")
struct PacingCalculatorWindowTests {

    /// The extraction must not change any Claude number: the bucket entry point
    /// and the raw-window one have to agree exactly.
    @Test("the bucket path and the window path produce identical results")
    func parityWithBucketPath() {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let resetsAt = now.addingTimeInterval(2 * 86_400)
        let usage = UsageResponse(
            sevenDay: .fixture(utilization: 61, resetsAt: ISO8601DateFormatter().string(from: resetsAt))
        )

        let viaBucket = PacingCalculator.calculate(from: usage, bucket: .sevenDay, margin: 10, now: now)
        let viaWindow = PacingCalculator.calculate(
            utilization: 61,
            resetsAt: resetsAt,
            windowDuration: 7 * 86_400,
            isIntraday: false,
            messagePool: .weekly,
            margin: 10,
            now: now
        )

        #expect(viaBucket?.delta == viaWindow?.delta)
        #expect(viaBucket?.expectedUsage == viaWindow?.expectedUsage)
        #expect(viaBucket?.zone == viaWindow?.zone)
        #expect(viaBucket?.message == viaWindow?.message)
        #expect(viaBucket?.coolingDate == viaWindow?.coolingDate)
    }

    @Test("an intraday window ignores the workweek schedule, like the Claude session bucket")
    func intradayIgnoresSchedule() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(9_000)
        let workweek = PacingSchedule(enabled: true, activeDays: PacingSchedule.workweek)

        let rolling = PacingCalculator.calculate(
            utilization: 50, resetsAt: resetsAt, windowDuration: 18_000,
            isIntraday: true, messagePool: .session, now: now
        )
        let scheduled = PacingCalculator.calculate(
            utilization: 50, resetsAt: resetsAt, windowDuration: 18_000,
            isIntraday: true, messagePool: .session, now: now,
            activeDays: workweek.effectiveActiveDays, activeHours: workweek.effectiveHours
        )

        #expect(rolling?.expectedUsage == scheduled?.expectedUsage)
    }

    @Test("an arbitrary window duration is supported, not just 5h and 7d")
    func arbitraryDuration() {
        let now = Date()
        // Half of a 12-hour window elapsed, 80% used: well ahead of pace.
        let result = PacingCalculator.calculate(
            utilization: 80,
            resetsAt: now.addingTimeInterval(21_600),
            windowDuration: 43_200,
            isIntraday: false,
            messagePool: .weekly,
            now: now
        )

        #expect(result?.expectedUsage == 50)
        #expect(result?.delta == 30)
        #expect(result?.zone == .hot)
    }

    @Test("a zero-length window yields no pacing rather than dividing by zero")
    func zeroDuration() {
        let result = PacingCalculator.calculate(
            utilization: 50, resetsAt: Date(), windowDuration: 0,
            isIntraday: false, messagePool: .weekly
        )

        #expect(result == nil)
    }
}
