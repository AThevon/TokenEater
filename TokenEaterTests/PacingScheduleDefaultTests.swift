import Testing
import Foundation

@Suite("PacingSchedule.default")
struct PacingScheduleDefaultTests {

    @Test("default schedule is the classic rolling window with 9-18 hours")
    func defaultMatchesRolling() {
        let d = PacingSchedule.default
        #expect(d.enabled == false)
        #expect(d.activeDays == PacingSchedule.workweek)
        #expect(d.hoursEnabled == false)
        #expect(d.startHour == 9)
        #expect(d.endHour == 18)
        #expect(d.startHour == PacingSchedule.defaultStartHour)
        #expect(d.endHour == PacingSchedule.defaultEndHour)
    }

    @Test("default is disabled so every day counts")
    func defaultIsRolling() {
        #expect(PacingSchedule.default.effectiveActiveDays == PacingSchedule.allDays)
        #expect(PacingSchedule.default.isActive == false)
    }
}
