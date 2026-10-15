import SwiftUI

// MARK: - Dotted track (a gauge with no scale)
//
// What a gauge draws when its metric has nothing to measure against: Extra
// Credits with no monthly limit, whose percentage is always 0. A row of
// evenly spaced dots reads as open-ended, where an empty track would read as
// "nothing spent". Shared by the popover, the dashboard card and the widgets
// so the uncapped state looks the same everywhere.

enum DottedTrack {
    /// Opacity of the dots over the track colour. Higher than a filled
    /// gauge's empty track: the dots carry the whole shape on their own.
    static let opacity: Double = 0.4

    /// Dot diameter for a gauge of `lineWidth`, never below 3 points so the
    /// smallest rings (a 46-point popover satellite) still show their dots.
    static func dotDiameter(lineWidth: CGFloat) -> CGFloat {
        max(lineWidth * 0.6, 3)
    }

    /// A round-dot stroke whose period divides `length` exactly. On a closed
    /// path (a ring) the last gap matches the others, so there is no seam; on
    /// an open one (an arc, a bar) a dot lands on each end.
    static func style(lineWidth: CGFloat, length: CGFloat, closed: Bool) -> StrokeStyle {
        let dot = dotDiameter(lineWidth: lineWidth)
        let target = max(lineWidth * 1.6, dot * 2)
        guard length > target else {
            return StrokeStyle(lineWidth: dot, lineCap: .round, dash: [0, max(target, 1)])
        }
        let count = (length / target).rounded()
        // An open path ends on a dot only if the last one falls inside it:
        // shave a hair off the period so rounding never pushes it past the end.
        let period = closed ? length / count : (length - 0.5) / count
        return StrokeStyle(lineWidth: dot, lineCap: .round, dash: [0, period])
    }
}

/// A full ring of dots, sized to its frame like `Circle()`. Starts at 12
/// o'clock like `RingGauge`, so it sits where the filled ring would.
struct DottedRing: View {
    let lineWidth: CGFloat
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            Circle()
                .stroke(
                    color.opacity(DottedTrack.opacity),
                    style: DottedTrack.style(lineWidth: lineWidth, length: .pi * side, closed: true)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: side, height: side)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

/// A horizontal line of dots in place of a progress bar, filling its frame's
/// width and centred in its height.
struct DottedBar: View {
    let lineWidth: CGFloat
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let inset = DottedTrack.dotDiameter(lineWidth: lineWidth) / 2
            let length = max(geo.size.width - inset * 2, 0)
            Path { p in
                p.move(to: CGPoint(x: inset, y: geo.size.height / 2))
                p.addLine(to: CGPoint(x: inset + length, y: geo.size.height / 2))
            }
            .stroke(
                color.opacity(DottedTrack.opacity),
                style: DottedTrack.style(lineWidth: lineWidth, length: length, closed: false)
            )
        }
    }
}
