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

    // MARK: - Workweek pacing

    /// UTC Gregorian calendar so weekend math is deterministic (no DST, no
    /// machine-local timezone).
    private static var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test("activeSeconds with all seven days equals the full duration")
    func activeSecondsAllDays() {
        let cal = Self.utcCalendar
        let start = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let end = start.addingTimeInterval(7 * 86_400)
        let secs = PacingCalculator.activeSeconds(from: start, to: end, activeDays: PacingSchedule.allDays, calendar: cal)
        #expect(secs == 7 * 86_400)
    }

    @Test("any midnight-aligned 7-day window has exactly 5 workweek days")
    func activeSecondsWorkweekIsAlwaysFiveDays() {
        let cal = Self.utcCalendar
        // Slide the window start across all 7 weekdays; each full week always
        // contains exactly one Saturday + one Sunday -> 5 active days.
        let base = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        for offset in 0..<7 {
            let start = base.addingTimeInterval(Double(offset) * 86_400)
            let end = start.addingTimeInterval(7 * 86_400)
            let secs = PacingCalculator.activeSeconds(from: start, to: end, activeDays: PacingSchedule.workweek, calendar: cal)
            #expect(secs == 5 * 86_400)
        }
    }

    @Test("activeSeconds ignores a partial off-day and counts a partial active day")
    func activeSecondsPartialDays() {
        let cal = Self.utcCalendar
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let saturday = cal.startOfDay(for: cal.nextDate(after: base, matching: DateComponents(weekday: 7), matchingPolicy: .nextTime)!)
        let monday = cal.startOfDay(for: cal.nextDate(after: base, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!)

        let satHalf = PacingCalculator.activeSeconds(from: saturday, to: saturday.addingTimeInterval(12 * 3600), activeDays: PacingSchedule.workweek, calendar: cal)
        let monHalf = PacingCalculator.activeSeconds(from: monday, to: monday.addingTimeInterval(12 * 3600), activeDays: PacingSchedule.workweek, calendar: cal)

        #expect(satHalf == 0)
        #expect(monHalf == 12 * 3600)
    }

    @Test("empty active days falls back to all seven (no divide by zero)")
    func emptyActiveDaysFallsBack() {
        let schedule = PacingSchedule(enabled: true, activeDays: [])
        #expect(schedule.effectiveActiveDays == PacingSchedule.allDays)
        #expect(schedule.isActive == false)
    }

    @Test("isActive only when the schedule meaningfully excludes a day")
    func isActiveSemantics() {
        #expect(PacingSchedule(enabled: false, activeDays: PacingSchedule.workweek).isActive == false)
        #expect(PacingSchedule(enabled: true, activeDays: PacingSchedule.allDays).isActive == false)
        #expect(PacingSchedule(enabled: true, activeDays: PacingSchedule.workweek).isActive == true)
    }

    @Test("isOffDay flags weekends and not weekdays when active")
    func isOffDayWeekendVsWeekday() {
        let cal = Self.utcCalendar
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let saturday = cal.nextDate(after: base, matching: DateComponents(weekday: 7), matchingPolicy: .nextTime)!
        let monday = cal.nextDate(after: base, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!
        let schedule = PacingSchedule(enabled: true, activeDays: PacingSchedule.workweek)

        #expect(schedule.isOffDay(saturday, calendar: cal) == true)
        #expect(schedule.isOffDay(monday, calendar: cal) == false)
        // A disabled schedule never reports off-days.
        #expect(PacingSchedule.rolling.isOffDay(saturday, calendar: cal) == false)
    }

    @Test("default activeDays matches classic rolling behavior exactly")
    func defaultMatchesRolling() {
        let now = Self.stableNow()
        let usage = UsageResponse.fixture(
            sevenDayUtil: 80,
            sevenDayResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now)
        )
        let classic = PacingCalculator.calculate(from: usage, now: now)
        let explicit = PacingCalculator.calculate(from: usage, now: now, activeDays: PacingSchedule.allDays)
        #expect(classic?.delta == explicit?.delta)
        #expect(classic?.zone == explicit?.zone)
        #expect(classic?.expectedUsage == explicit?.expectedUsage)
    }

    @Test("five-hour bucket is never workweek-adjusted")
    func fiveHourIgnoresWorkweek() {
        let now = Self.stableNow()
        let usage = UsageResponse.fixture(
            fiveHourUtil: 60,
            fiveHourResetsAt: makeResetsAt(elapsedFraction: 0.5, now: now, duration: 5 * 3600)
        )
        let classic = PacingCalculator.calculate(from: usage, bucket: .fiveHour, now: now)
        let workweek = PacingCalculator.calculate(from: usage, bucket: .fiveHour, now: now, activeDays: PacingSchedule.workweek)
        #expect(classic?.expectedUsage == workweek?.expectedUsage)
    }

    // MARK: - Active hours

    @Test("activeSeconds with hours counts only the work-hour window")
    func activeSecondsWithHours() {
        let cal = Self.utcCalendar
        let start = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let end = start.addingTimeInterval(7 * 86_400)
        // Mon-Fri, 9-18 = 9h on each of 5 weekdays.
        let secs = PacingCalculator.activeSeconds(from: start, to: end, activeDays: PacingSchedule.workweek, hours: (9, 18), calendar: cal)
        #expect(abs(secs - 5 * 9 * 3600) < 1)
    }

    @Test("effectiveHours is nil unless enabled with a valid range")
    func effectiveHoursSemantics() {
        #expect(PacingSchedule(enabled: true, activeDays: PacingSchedule.workweek, hoursEnabled: false, startHour: 9, endHour: 18).effectiveHours == nil)
        #expect(PacingSchedule(enabled: true, activeDays: PacingSchedule.workweek, hoursEnabled: true, startHour: 18, endHour: 9).effectiveHours == nil)
        let h = PacingSchedule(enabled: true, activeDays: PacingSchedule.workweek, hoursEnabled: true, startHour: 9, endHour: 18).effectiveHours
        #expect(h?.start == 9)
        #expect(h?.end == 18)
    }

    @Test("hours narrowing makes the schedule active even with all seven days")
    func isActiveWithHoursAllDays() {
        let s = PacingSchedule(enabled: true, activeDays: PacingSchedule.allDays, hoursEnabled: true, startHour: 9, endHour: 18)
        #expect(s.isActive == true)
    }

    @Test("isOffDay flags off-hours on an active day")
    func isOffDayHonorsHours() {
        let cal = Self.utcCalendar
        let s = PacingSchedule(enabled: true, activeDays: PacingSchedule.workweek, hoursEnabled: true, startHour: 9, endHour: 18)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let monday = cal.startOfDay(for: cal.nextDate(after: base, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!)
        let mon7 = cal.date(bySettingHour: 7, minute: 0, second: 0, of: monday)!
        let mon12 = cal.date(bySettingHour: 12, minute: 0, second: 0, of: monday)!
        #expect(s.isOffDay(mon7, calendar: cal) == true)
        #expect(s.isOffDay(mon12, calendar: cal) == false)
    }

    // MARK: - Off-day ranges + now marker (#194)

    /// A Mon-aligned 7-day window so day fractions are exact: Mon..Fri = [0, 5/7],
    /// Sat+Sun = [5/7, 1]. `resetDate` is the window END (next Monday).
    private static func mondayAlignedWindow() -> (windowStart: Date, resetDate: Date, calendar: Calendar) {
        let cal = utcCalendar
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let monday = cal.startOfDay(for: cal.nextDate(after: base, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!)
        return (monday, monday.addingTimeInterval(7 * 86_400), cal)
    }

    @Test("offDayRanges covers exactly the weekend (~2/7) for a Mon-Fri window")
    func offDayRangesWeekendWidth() {
        let (_, resetDate, cal) = Self.mondayAlignedWindow()
        let s = PacingSchedule(enabled: true, activeDays: PacingSchedule.workweek)
        let ranges = s.offDayRanges(resetDate: resetDate, calendar: cal)
        let total = ranges.reduce(0.0) { $0 + ($1.upperBound - $1.lowerBound) }
        #expect(abs(total - 2.0 / 7.0) < 0.001)
    }

    @Test("nowFraction is the linear calendar fraction of now in the window")
    func nowFractionIsLinear() {
        let (windowStart, resetDate, _) = Self.mondayAlignedWindow()
        let s = PacingSchedule(enabled: true, activeDays: PacingSchedule.workweek)
        // Friday noon = 4.5 days into a 7-day window.
        let fridayNoon = windowStart.addingTimeInterval(4 * 86_400 + 12 * 3600)
        #expect(abs(s.nowFraction(resetDate: resetDate, now: fridayNoon) - 4.5 / 7.0) < 0.0001)
        // Clamps outside the window.
        #expect(s.nowFraction(resetDate: resetDate, now: windowStart.addingTimeInterval(-86_400)) == 0)
        #expect(s.nowFraction(resetDate: resetDate, now: resetDate.addingTimeInterval(86_400)) == 1)
    }

    /// The core invariant: a "now" marker drawn at `nowFraction` lands on a
    /// dashed (off) segment exactly when `isOffDay(now)` is true. Interior
    /// instants (noon) avoid the ClosedRange endpoint ambiguity at day borders.
    @Test("nowFraction lands in an offDayRange iff now is an off day")
    func nowMarkerAgreesWithOffDayHatch() {
        let (windowStart, resetDate, cal) = Self.mondayAlignedWindow()
        let s = PacingSchedule(enabled: true, activeDays: PacingSchedule.workweek)
        let ranges = s.offDayRanges(resetDate: resetDate, calendar: cal)

        let fridayNoon = windowStart.addingTimeInterval(4 * 86_400 + 12 * 3600)
        let saturdayNoon = windowStart.addingTimeInterval(5 * 86_400 + 12 * 3600)

        let fFri = s.nowFraction(resetDate: resetDate, now: fridayNoon)
        let fSat = s.nowFraction(resetDate: resetDate, now: saturdayNoon)

        #expect(s.isOffDay(fridayNoon, calendar: cal) == false)
        #expect(ranges.contains { $0.contains(fFri) } == false)

        #expect(s.isOffDay(saturdayNoon, calendar: cal) == true)
        #expect(ranges.contains { $0.contains(fSat) } == true)
    }

    /// Regression guard for #194: with Mon/Wed/Fri active and now on Friday, the
    /// OLD active-time marker (expectedUsage) lands on a dashed off-day segment,
    /// while the calendar-time `nowFraction` correctly sits on Friday's solid band.
    @Test("active-time marker mislands on the hatch but nowFraction does not (#194)")
    func nowFractionFixesMislandedMarker() {
        let (windowStart, resetDate, cal) = Self.mondayAlignedWindow()
        let mwf = PacingSchedule(enabled: true, activeDays: [2, 4, 6]) // Mon, Wed, Fri
        let ranges = mwf.offDayRanges(resetDate: resetDate, calendar: cal)
        let fridayNoon = windowStart.addingTimeInterval(4 * 86_400 + 12 * 3600)

        // Old marker position = active-time fraction (off-days compressed out).
        let activeElapsed = PacingCalculator.activeSeconds(from: windowStart, to: fridayNoon, activeDays: [2, 4, 6], calendar: cal)
        let activeTotal = PacingCalculator.activeSeconds(from: windowStart, to: resetDate, activeDays: [2, 4, 6], calendar: cal)
        let oldMarker = activeElapsed / activeTotal
        let newMarker = mwf.nowFraction(resetDate: resetDate, now: fridayNoon)

        // The bug: the active-time marker fell inside a dashed off-day range.
        #expect(ranges.contains { $0.contains(oldMarker) } == true)
        // The fix: the calendar-time marker sits on the active (solid) segment.
        #expect(mwf.isOffDay(fridayNoon, calendar: cal) == false)
        #expect(ranges.contains { $0.contains(newMarker) } == false)
    }
}
