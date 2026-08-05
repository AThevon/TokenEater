import Testing
import Foundation

@Suite("PacingSampleBuffer (#240 real pacing trajectory)")
struct PacingSampleBufferTests {

    private let window: TimeInterval = 5 * 3600

    /// A reset 2.5h from `now` -> we're mid-window, window started 2.5h ago.
    private func reset(from now: Date) -> Date {
        now.addingTimeInterval(window / 2)
    }

    @Test("append records a new dated reading")
    func appendRecordsReading() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let out = PacingSampleBuffer.append(
            [], utilization: 42, resetDate: reset(from: now), windowDuration: window, now: now
        )
        #expect(out.count == 1)
        #expect(out.first?.utilization == 42)
        #expect(out.first?.date == now)
    }

    @Test("append with no reset window leaves the buffer unchanged")
    func appendNoWindowNoop() {
        let existing = [PacingSample(date: Date(timeIntervalSince1970: 1), utilization: 10)]
        let out = PacingSampleBuffer.append(
            existing, utilization: 50, resetDate: nil, windowDuration: window, now: Date(timeIntervalSince1970: 2)
        )
        #expect(out == existing)
    }

    @Test("a new window drops the previous window's samples")
    func newWindowDropsOldSamples() {
        let base = Date(timeIntervalSince1970: 2_000_000)
        // Two readings in the first window.
        var samples = PacingSampleBuffer.append([], utilization: 10, resetDate: reset(from: base), windowDuration: window, now: base)
        samples = PacingSampleBuffer.append(samples, utilization: 20, resetDate: reset(from: base.addingTimeInterval(600)), windowDuration: window, now: base.addingTimeInterval(600))
        #expect(samples.count == 2)

        // Jump well past the first window: reset is now far in the future, so
        // its window start is after the old samples -> they're dropped.
        let later = base.addingTimeInterval(window + 4000)
        let out = PacingSampleBuffer.append(samples, utilization: 5, resetDate: reset(from: later), windowDuration: window, now: later)
        #expect(out.count == 1)
        #expect(out.first?.utilization == 5)
    }

    @Test("append caps the buffer at maxCount")
    func appendCaps() {
        let now = Date(timeIntervalSince1970: 3_000_000)
        let r = reset(from: now)
        // Seed a full buffer of in-window samples just before `now`.
        let seed = (0..<PacingSampleBuffer.maxCount).map {
            PacingSample(date: now.addingTimeInterval(-Double($0) - 1), utilization: 1)
        }
        let out = PacingSampleBuffer.append(seed, utilization: 99, resetDate: r, windowDuration: window, now: now)
        #expect(out.count == PacingSampleBuffer.maxCount)
        #expect(out.last?.utilization == 99) // newest kept
    }

    @Test("trajectory maps samples to elapsed-fraction / utilization coordinates")
    func trajectoryMapsCoordinates() {
        // resetDate defines the window; a sample at the window's midpoint -> x=50.
        let reset = Date(timeIntervalSince1970: 4_000_000)
        let windowStart = reset.addingTimeInterval(-window)
        let mid = windowStart.addingTimeInterval(window / 2)
        let points = PacingSampleBuffer.trajectory(
            [PacingSample(date: mid, utilization: 30)],
            resetDate: reset, windowDuration: window
        )
        #expect(points.count == 1)
        #expect(abs((points.first?.expected ?? 0) - 50) < 0.001)
        #expect(points.first?.actual == 30)
    }

    @Test("trajectory sorts by date and clamps utilization")
    func trajectorySortsAndClamps() {
        let reset = Date(timeIntervalSince1970: 5_000_000)
        let windowStart = reset.addingTimeInterval(-window)
        let late = windowStart.addingTimeInterval(window * 0.75)
        let early = windowStart.addingTimeInterval(window * 0.25)
        let points = PacingSampleBuffer.trajectory(
            [
                PacingSample(date: late, utilization: 120),  // over 100 -> clamp
                PacingSample(date: early, utilization: 10),
            ],
            resetDate: reset, windowDuration: window
        )
        #expect(points.count == 2)
        #expect(points[0].expected < points[1].expected) // sorted ascending
        #expect(points[1].actual == 100)                  // clamped
    }

    @Test("trajectory is empty without a reset window")
    func trajectoryEmptyWithoutWindow() {
        let s = [PacingSample(date: Date(timeIntervalSince1970: 1), utilization: 10)]
        #expect(PacingSampleBuffer.trajectory(s, resetDate: nil, windowDuration: window).isEmpty)
    }
}
