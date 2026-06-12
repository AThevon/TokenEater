import SwiftUI

struct PacingBar: View {
    let actual: Double
    let expected: Double
    let zone: PacingZone
    let gradient: LinearGradient
    let compact: Bool
    /// Off-day spans (x-fractions of the calendar window) to hatch on the track.
    let offDayRanges: [ClosedRange<Double>]
    /// True when "now" falls on an off-day - mutes the ideal marker.
    let nowInOffDay: Bool
    /// Calendar-time x-fraction (0...1) to place the "now" marker at, used when a
    /// workweek schedule is active so the marker stays in the same coordinate
    /// space as `offDayRanges` (sits solid on active days, dashed on off days).
    /// nil keeps the classic `expected`-based (active-time %) marker position.
    let markerFraction: Double?

    init(actual: Double, expected: Double, zone: PacingZone, gradient: LinearGradient, compact: Bool = false, offDayRanges: [ClosedRange<Double>] = [], nowInOffDay: Bool = false, markerFraction: Double? = nil) {
        self.actual = actual
        self.expected = expected
        self.zone = zone
        self.gradient = gradient
        self.compact = compact
        self.offDayRanges = offDayRanges
        self.nowInOffDay = nowInOffDay
        self.markerFraction = markerFraction
    }

    @State private var animatedActual: Double = 0
    @State private var pulsing = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: compact ? 2 : 4)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: compact ? 4 : 8)

                if !offDayRanges.isEmpty {
                    OffDayHatch(ranges: offDayRanges, cornerRadius: compact ? 2 : 4)
                        .frame(height: compact ? 4 : 8)
                }

                RoundedRectangle(cornerRadius: compact ? 2 : 4)
                    .fill(gradient)
                    .frame(width: max(0, geo.size.width * CGFloat(min(animatedActual, 100)) / 100), height: compact ? 4 : 8)

                idealMarker
                    .offset(x: markerOffsetX(width: geo.size.width))

                if !compact {
                    Circle()
                        .fill(nowInOffDay ? Color.white.opacity(0.45) : Color.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: .white.opacity(nowInOffDay ? 0.2 : 0.5), radius: pulsing ? 6 : 2)
                        .offset(x: geo.size.width * CGFloat(min(animatedActual, 100)) / 100 - 5)
                }
            }
        }
        .frame(height: compact ? 10 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animatedActual = actual
            }
            if !compact {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
        }
        .onChange(of: actual) { _, newValue in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animatedActual = newValue
            }
        }
    }

    /// X offset for the ideal/now marker. When `markerFraction` is set (workweek
    /// active) the marker follows calendar time so it aligns with the off-day
    /// hatch; otherwise it follows the active-time `expected` percentage (#194).
    private func markerOffsetX(width: CGFloat) -> CGFloat {
        let nudge: CGFloat = compact ? 3 : 5
        if let f = markerFraction {
            return width * CGFloat(min(max(f, 0), 1)) - nudge
        }
        return width * CGFloat(min(expected, 100)) / 100 - nudge
    }

    private var idealMarker: some View {
        let size: CGFloat = compact ? 6 : 10
        return Path { path in
            path.move(to: CGPoint(x: size / 2, y: 0))
            path.addLine(to: CGPoint(x: size, y: size))
            path.addLine(to: CGPoint(x: 0, y: size))
            path.closeSubpath()
        }
        .fill(Color.white.opacity(nowInOffDay ? 0.25 : 0.5))
        .frame(width: size, height: size)
    }
}
