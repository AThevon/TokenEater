import Testing
import Foundation

@Suite("ResetCountdownFormatter")
@MainActor
struct ResetCountdownFormatterTests {

    // MARK: - Session (5h)

    @Test("session: same-day absolute is HH:mm")
    func sessionSameDay() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 16, hour: 14))!
        let reset = calendar.date(from: DateComponents(year: 2026, month: 4, day: 16, hour: 20, minute: 30))!

        let (_, absolute) = ResetCountdownFormatter.session(from: reset, now: now)
        #expect(absolute == "20:30")
    }

    @Test("session: other-day absolute is EEE HH:mm")
    func sessionOtherDay() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 16, hour: 20))!
        let reset = calendar.date(from: DateComponents(year: 2026, month: 4, day: 17, hour: 8, minute: 0))!

        let (_, absolute) = ResetCountdownFormatter.session(from: reset, now: now)
        // Weekday label depends on current locale; just assert the HH:mm suffix.
        #expect(absolute.hasSuffix(" 08:00"))
        #expect(absolute.count > 6)
    }

    @Test("session: relative formats hours + padded minutes")
    func sessionRelativeHours() {
        let now = Date()
        let reset = now.addingTimeInterval(1 * 3600 + 25 * 60)
        let (relative, _) = ResetCountdownFormatter.session(from: reset, now: now)
        #expect(relative == "1h25")
    }

    @Test("session: relative with only minutes")
    func sessionRelativeMinutes() {
        let now = Date()
        let reset = now.addingTimeInterval(25 * 60)
        let (relative, _) = ResetCountdownFormatter.session(from: reset, now: now)
        #expect(relative == "25min")
    }

    @Test("session: nil date yields empty strings")
    func sessionNil() {
        let (relative, absolute) = ResetCountdownFormatter.session(from: nil)
        #expect(relative == "")
        #expect(absolute == "")
    }

    // MARK: - Weekly (7d)

    @Test("weekly: multi-day relative is Xd Yh")
    func weeklyRelativeDays() {
        let now = Date()
        let reset = now.addingTimeInterval(3 * 86_400 + 14 * 3600)
        let (relative, _) = ResetCountdownFormatter.weekly(from: reset, now: now)
        #expect(relative == "3d 14h")
    }

    @Test("weekly: under-a-day relative is Xh Ym")
    func weeklyRelativeHours() {
        let now = Date()
        let reset = now.addingTimeInterval(14 * 3600 + 5 * 60)
        let (relative, _) = ResetCountdownFormatter.weekly(from: reset, now: now)
        #expect(relative == "14h 05")
    }

    @Test("weekly: under-an-hour relative is Xmin")
    func weeklyRelativeMinutes() {
        let now = Date()
        let reset = now.addingTimeInterval(25 * 60)
        let (relative, _) = ResetCountdownFormatter.weekly(from: reset, now: now)
        #expect(relative == "25min")
    }

    // MARK: - display() combiner

    @Test("display: relative mode returns only relative")
    func displayRelative() {
        let result = ResetCountdownFormatter.display(relative: "1h25", absolute: "20:30", format: .relative)
        #expect(result == "1h25")
    }

    @Test("display: both mode joins with ' - '")
    func displayBoth() {
        let result = ResetCountdownFormatter.display(relative: "1h25", absolute: "20:30", format: .both)
        #expect(result == "1h25 - 20:30")
    }

    @Test("display: both mode with empty relative returns absolute only")
    func displayBothEmptyRelative() {
        let result = ResetCountdownFormatter.display(relative: "", absolute: "20:30", format: .both)
        #expect(result == "20:30")
    }

    // MARK: - Sentence split (#295)

    @Test("sentenceParts: English sentence splits before the countdown")
    func sentencePartsEnglish() {
        let parts = ResetCountdownFormatter.sentenceParts("Resets in %@")
        #expect(parts?.before == "Resets in")
        #expect(parts?.after == "")
    }

    @Test("sentenceParts: French sentence splits before the countdown")
    func sentencePartsFrench() {
        let parts = ResetCountdownFormatter.sentenceParts("Reset dans %@")
        #expect(parts?.before == "Reset dans")
        #expect(parts?.after == "")
    }

    @Test("sentenceParts: words after the placeholder are kept, trimmed")
    func sentencePartsTrailingWords() {
        let parts = ResetCountdownFormatter.sentenceParts("%@ before reset")
        #expect(parts?.before == "")
        #expect(parts?.after == "before reset")
    }

    @Test("sentenceParts: a positional placeholder splits too")
    func sentencePartsPositional() {
        let parts = ResetCountdownFormatter.sentenceParts("Reset in %1$@.")
        #expect(parts?.before == "Reset in")
        #expect(parts?.after == ".")
    }

    @Test("sentenceParts: nil without a placeholder")
    func sentencePartsNoPlaceholder() {
        #expect(ResetCountdownFormatter.sentenceParts("Resets soon") == nil)
    }

    @Test("sentenceParts: the shipped EN and FR strings both split")
    func sentencePartsShippedStrings() throws {
        let bundle = Bundle(for: SentencePartsBundleToken.self)
        for language in ["en", "fr"] {
            let path = try #require(bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language))
            let table = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
            let format = try #require(table["metric.reset"])
            let parts = try #require(ResetCountdownFormatter.sentenceParts(format))
            #expect(!parts.before.isEmpty)
            #expect(parts.before + " " + "2h14" == String(format: format, "2h14"))
        }
    }
}

private final class SentencePartsBundleToken {}
