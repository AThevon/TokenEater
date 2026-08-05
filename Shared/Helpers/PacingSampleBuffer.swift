import Foundation

/// Accumulates dated utilization readings within the current reset window and
/// turns them into chart coordinates for the hero pacing trajectory (#240).
///
/// The pacing graph used to draw a single straight segment from the window's
/// origin to the current point, because the app only ever knew one data point
/// (the live utilization). By keeping a short, windowed history of readings we
/// can plot the actual curve - flat early, steep late reads as a hockey stick,
/// which is exactly what the graph should reveal.
///
/// Pure and `now`-injectable so the windowing/capping is unit-testable.
enum PacingSampleBuffer {
    /// Safety cap on stored readings. A 5h window refreshed every ~few minutes
    /// yields well under this; the cap is a backstop against unbounded growth
    /// (e.g. a very short refresh interval left running for a long time).
    static let maxCount = 400

    /// Appends `utilization` at `now`, dropping any reading that predates the
    /// current window (`resetDate - windowDuration`) so a fresh window starts
    /// clean, and capping the total. Returns the samples unchanged (no append)
    /// when there is no reset window to place the point in - a reading with no
    /// window can't be positioned on the chart.
    static func append(
        _ samples: [PacingSample],
        utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        now: Date,
        maxCount: Int = maxCount
    ) -> [PacingSample] {
        guard let resetDate else { return samples }
        let windowStart = resetDate.addingTimeInterval(-windowDuration)
        // Keep only current-window readings strictly before `now`, so a new
        // window (reset jumped forward) discards the previous window's curve.
        var out = samples.filter { $0.date >= windowStart && $0.date < now }
        out.append(PacingSample(date: now, utilization: utilization))
        if out.count > maxCount {
            out = Array(out.suffix(maxCount))
        }
        return out
    }

    /// Maps the current-window samples into chart coordinates. `expected` is the
    /// elapsed fraction of the window as a percentage (x), `actual` the reading
    /// (y). Samples outside the current window are dropped; both axes clamp to
    /// 0...100. Returns an empty array when there is no window.
    static func trajectory(
        _ samples: [PacingSample],
        resetDate: Date?,
        windowDuration: TimeInterval
    ) -> [PacingTrajectoryPoint] {
        guard let resetDate, windowDuration > 0 else { return [] }
        let windowStart = resetDate.addingTimeInterval(-windowDuration)
        return samples
            .filter { $0.date >= windowStart && $0.date <= resetDate }
            .sorted { $0.date < $1.date }
            .map { sample in
                let frac = min(max(sample.date.timeIntervalSince(windowStart) / windowDuration, 0), 1)
                return PacingTrajectoryPoint(
                    expected: frac * 100,
                    actual: min(max(sample.utilization, 0), 100)
                )
            }
    }
}
