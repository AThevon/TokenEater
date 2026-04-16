import Testing
import Foundation

@Suite("UsageStore.formatAbsoluteReset")
@MainActor
struct UsageStoreResetFormatTests {

    @Test("formats same-day reset as HH:mm")
    func sameDay() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 16, hour: 14))!
        let reset = calendar.date(from: DateComponents(year: 2026, month: 4, day: 16, hour: 20, minute: 30))!

        let formatted = UsageStore.formatAbsoluteReset(reset, now: now)
        #expect(formatted == "20:30")
    }

    @Test("formats other-day reset as EEE HH:mm")
    func otherDay() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 16, hour: 20))!
        let reset = calendar.date(from: DateComponents(year: 2026, month: 4, day: 17, hour: 8, minute: 0))!

        let formatted = UsageStore.formatAbsoluteReset(reset, now: now)
        // The weekday label depends on the current locale; we only assert
        // the HH:mm portion is present and there is a space-separated prefix.
        #expect(formatted.hasSuffix(" 08:00"))
        #expect(formatted.count > 6)
    }
}
