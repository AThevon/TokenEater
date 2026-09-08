import Testing
import Foundation

@Suite("CodexWindowKind + window resolution")
struct CodexWindowKindTests {

    // MARK: - Classification

    @Test("windows are classified by duration, never by position")
    func classification() {
        #expect(CodexWindowKind.classify(seconds: 18_000) == .session)
        #expect(CodexWindowKind.classify(seconds: 300 * 60) == .session)
        #expect(CodexWindowKind.classify(seconds: 604_800) == .weekly)
        #expect(CodexWindowKind.classify(seconds: 5 * 86_400) == .weekly)
        #expect(CodexWindowKind.classify(seconds: 43_200) == .other)
        #expect(CodexWindowKind.classify(seconds: 0) == .other)
        #expect(CodexWindowKind.classify(seconds: -1) == .other)
    }

    @Test("a weekly-only plan reports its single window as weekly, not as a session")
    func weeklyOnlyPlanIsNotMislabelled() {
        let usage = CodexFixtures.decode(CodexFixtures.proliteJSON)
        let windows = CodexWindowResolver.windows(in: usage)

        #expect(windows.count == 1)
        #expect(windows.first?.kind == .weekly)
    }

    @Test("windows are ordered session first regardless of payload order")
    func ordering() {
        let usage = CodexFixtures.usage(
            primary: CodexFixtures.window(usedPercent: 10, windowSeconds: 604_800, resetAt: Date().addingTimeInterval(500_000)),
            secondary: CodexFixtures.window(usedPercent: 20, windowSeconds: 18_000, resetAt: Date().addingTimeInterval(3_600))
        )
        let windows = CodexWindowResolver.windows(in: usage)

        #expect(windows.map(\.kind) == [.session, .weekly])
    }

    // MARK: - Labels

    @Test("labels are derived from the actual duration")
    func labels() {
        #expect(CodexWindowKind.session.label(for: 18_000) == "5h")
        #expect(CodexWindowKind.other.label(for: 43_200) == "12h")
        #expect(CodexWindowKind.other.label(for: 3 * 86_400) == "3d")
        #expect(CodexWindowKind.other.label(for: 900) == "15min")
        // Weekly is a word, not a duration, in every language.
        #expect(!CodexWindowKind.weekly.label(for: 604_800).isEmpty)
    }

    // MARK: - Idle detection

    @Test("an untouched window is idle, a used one is not")
    func idleDetection() {
        let untouched = CodexRateWindow(usedPercent: 0, limitWindowSeconds: 18_000, resetAfterSeconds: 18_000, resetAt: 1)
        #expect(untouched.isIdle)

        let started = CodexRateWindow(usedPercent: 0, limitWindowSeconds: 18_000, resetAfterSeconds: 9_000, resetAt: 1)
        #expect(!started.isIdle)

        let used = CodexRateWindow(usedPercent: 12, limitWindowSeconds: 18_000, resetAfterSeconds: 18_000, resetAt: 1)
        #expect(!used.isIdle)

        // Without the countdown we cannot tell, and must not guess "idle":
        // suppressing a real reminder is worse than scheduling a redundant one.
        let unknown = CodexRateWindow(usedPercent: 0, limitWindowSeconds: 18_000, resetAfterSeconds: nil, resetAt: 1)
        #expect(!unknown.isIdle)
    }

    // MARK: - Snapshot

    @Test("snapshots carry formatted resets and pacing for a used window")
    func snapshotFormatting() {
        let now = Date()
        let usage = CodexFixtures.usage(
            primary: CodexFixtures.window(usedPercent: 50, windowSeconds: 18_000, resetAfterSeconds: 9_000, resetAt: now.addingTimeInterval(9_000))
        )
        let window = CodexWindowResolver.windows(in: usage, now: now).first

        #expect(window?.pct == 50)
        #expect(window?.label == "5h")
        #expect(window?.relativeReset.isEmpty == false)
        #expect(window?.absoluteReset.isEmpty == false)
        // Half the window elapsed, half of it used: exactly on pace.
        #expect(window?.pacing?.zone == .onTrack)
    }

    @Test("a session window running hot is flagged by pacing")
    func hotSessionPacing() {
        let now = Date()
        let usage = CodexFixtures.usage(
            primary: CodexFixtures.window(usedPercent: 90, windowSeconds: 18_000, resetAfterSeconds: 14_400, resetAt: now.addingTimeInterval(14_400))
        )
        let window = CodexWindowResolver.windows(in: usage, now: now).first

        #expect(window?.pacing?.zone == .hot)
    }

    @Test("percentages round rather than truncate")
    func rounding() {
        #expect(CodexRateWindow(usedPercent: 11.6, limitWindowSeconds: 18_000).pct == 12)
        #expect(CodexRateWindow(usedPercent: 11.2, limitWindowSeconds: 18_000).pct == 11)
    }
}
