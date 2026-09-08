import Testing
import Foundation

@Suite("CodexResetDetector")
struct CodexResetDetectorTests {

    private let weekly: TimeInterval = 604_800
    private let session: TimeInterval = 18_000

    // MARK: - The idle-window trap

    @Test("an untouched window whose deadline slides on every poll never fires")
    func idleWindowNeverFires() {
        let now = Date()
        // What the backend actually reports for an unused window: reset_at is
        // recomputed as now + window on every single poll.
        var previous = CodexResetDetector.Observation(usedPercent: 0, resetAt: now.addingTimeInterval(weekly))
        for tick in 1...20 {
            let pollTime = now.addingTimeInterval(Double(tick) * 300)
            let current = CodexResetDetector.Observation(usedPercent: 0, resetAt: pollTime.addingTimeInterval(weekly))
            #expect(!CodexResetDetector.didReset(previous: previous, current: current, windowDuration: weekly, now: pollTime))
            previous = current
        }
    }

    // MARK: - Real rollovers

    @Test("usage dropping across a moved deadline fires")
    func usageDropFires() {
        let now = Date()
        let previous = CodexResetDetector.Observation(usedPercent: 90, resetAt: now.addingTimeInterval(60))
        let current = CodexResetDetector.Observation(usedPercent: 3, resetAt: now.addingTimeInterval(weekly))

        #expect(CodexResetDetector.didReset(previous: previous, current: current, windowDuration: weekly, now: now))
    }

    @Test("a deadline that elapsed while the Mac slept fires even without a usage drop")
    func elapsedDeadlineFires() {
        let now = Date()
        // Asleep across the reset: the old deadline is now in the past and the
        // fresh window happens to report the same percentage.
        let previous = CodexResetDetector.Observation(usedPercent: 40, resetAt: now.addingTimeInterval(-3_600))
        let current = CodexResetDetector.Observation(usedPercent: 40, resetAt: now.addingTimeInterval(weekly))

        #expect(CodexResetDetector.didReset(previous: previous, current: current, windowDuration: weekly, now: now))
    }

    @Test("a session window rollover fires on its own shorter tolerance")
    func sessionRollover() {
        let now = Date()
        let previous = CodexResetDetector.Observation(usedPercent: 75, resetAt: now.addingTimeInterval(30))
        let current = CodexResetDetector.Observation(usedPercent: 0, resetAt: now.addingTimeInterval(session))

        #expect(CodexResetDetector.didReset(previous: previous, current: current, windowDuration: session, now: now))
    }

    // MARK: - Non-events

    @Test("the first observation of a window never fires")
    func firstObservationIsSilent() {
        let current = CodexResetDetector.Observation(usedPercent: 5, resetAt: Date().addingTimeInterval(weekly))
        #expect(!CodexResetDetector.didReset(previous: nil, current: current, windowDuration: weekly))
    }

    @Test("clock jitter under the tolerance does not fire")
    func jitterIsIgnored() {
        let now = Date()
        let reset = now.addingTimeInterval(50_000)
        let previous = CodexResetDetector.Observation(usedPercent: 40, resetAt: reset)
        // A couple of seconds of server-side rounding on a live deadline.
        let current = CodexResetDetector.Observation(usedPercent: 41, resetAt: reset.addingTimeInterval(3))

        #expect(!CodexResetDetector.didReset(previous: previous, current: current, windowDuration: weekly, now: now))
    }

    @Test("usage climbing inside the same window does not fire")
    func normalUsageDoesNotFire() {
        let now = Date()
        let reset = now.addingTimeInterval(200_000)
        let previous = CodexResetDetector.Observation(usedPercent: 20, resetAt: reset)
        let current = CodexResetDetector.Observation(usedPercent: 55, resetAt: reset)

        #expect(!CodexResetDetector.didReset(previous: previous, current: current, windowDuration: weekly, now: now))
    }

    @Test("a drop with an unchanged deadline does not fire")
    func dropWithoutRolloverDoesNotFire() {
        let now = Date()
        let reset = now.addingTimeInterval(200_000)
        // The backend correcting a percentage downwards is not a new window.
        let previous = CodexResetDetector.Observation(usedPercent: 60, resetAt: reset)
        let current = CodexResetDetector.Observation(usedPercent: 58, resetAt: reset)

        #expect(!CodexResetDetector.didReset(previous: previous, current: current, windowDuration: weekly, now: now))
    }

    @Test("a rollover is announced once, not on every later poll")
    func firesExactlyOnce() {
        let now = Date()
        let oldReset = now.addingTimeInterval(60)
        let newReset = now.addingTimeInterval(weekly)

        let atReset = CodexResetDetector.Observation(usedPercent: 2, resetAt: newReset)
        #expect(CodexResetDetector.didReset(
            previous: CodexResetDetector.Observation(usedPercent: 88, resetAt: oldReset),
            current: atReset,
            windowDuration: weekly,
            now: now
        ))

        // Next poll five minutes later, inside the same fresh window.
        let later = now.addingTimeInterval(300)
        #expect(!CodexResetDetector.didReset(
            previous: atReset,
            current: CodexResetDetector.Observation(usedPercent: 4, resetAt: newReset),
            windowDuration: weekly,
            now: later
        ))
    }
}
