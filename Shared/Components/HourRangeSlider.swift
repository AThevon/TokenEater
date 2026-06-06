import SwiftUI

/// Dual-thumb range slider over a 0...24h track, in the TokenEaterSlider visual
/// language (capsule track, tint-filled active span between the thumbs, white
/// thumbs that scale + halo on hover/drag). Drives the "active hours" window for
/// workweek pacing: the user sees and drags their work window directly instead
/// of picking from a native menu. Snaps to whole hours, keeps a 1h minimum gap.
struct HourRangeSlider: View {
    @Binding var startHour: Int   // 0...23
    @Binding var endHour: Int     // 1...24
    var tint: Color = DS.Palette.accentSettings

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeThumb: Thumb?
    @State private var isHovering = false

    private enum Thumb { case start, end }

    private let lower = 0
    private let upper = 24
    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 14
    private let hoverScale: CGFloat = 1.2
    private let dragScale: CGFloat = 1.35
    private let haloRatio: CGFloat = 2.4

    private var span: Double { Double(upper - lower) }
    private var stateAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0.0)
    }

    var body: some View {
        GeometryReader { geo in
            let trackWidth = max(0, geo.size.width - thumbSize)
            let startX = fraction(startHour) * trackWidth
            let endX = fraction(endHour) * trackWidth

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(isHovering || activeThumb != nil ? 0.18 : 0.12))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(tint)
                    .frame(width: max(0, endX - startX), height: trackHeight)
                    .offset(x: startX + thumbSize / 2)

                thumb(x: startX, kind: .start)
                thumb(x: endX, kind: .end)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if activeThumb == nil {
                            let dStart = abs(drag.location.x - (startX + thumbSize / 2))
                            let dEnd = abs(drag.location.x - (endX + thumbSize / 2))
                            activeThumb = dStart <= dEnd ? .start : .end
                        }
                        update(cursorX: drag.location.x, trackWidth: trackWidth)
                    }
                    .onEnded { _ in activeThumb = nil }
            )
            .animation(stateAnimation, value: isHovering)
            .animation(stateAnimation, value: activeThumb)
        }
        .frame(height: thumbSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "settings.pacing.workweek.hours")))
        .accessibilityValue(Text(String(format: "%02d:00 - %02d:00", startHour, endHour)))
    }

    private func fraction(_ hour: Int) -> CGFloat {
        CGFloat((Double(hour) - Double(lower)) / span)
    }

    private func thumb(x: CGFloat, kind: Thumb) -> some View {
        let isActive = activeThumb == kind
        let scale = isActive ? dragScale : (isHovering ? hoverScale : 1.0)
        return ZStack {
            Circle()
                .fill(tint)
                .frame(width: thumbSize * haloRatio, height: thumbSize * haloRatio)
                .opacity(isActive ? 0.32 : 0.0)
                .blur(radius: 6)
                .allowsHitTesting(false)
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(isActive ? 0.28 : 0.16), radius: isActive ? 3 : 1.5, y: isActive ? 1.5 : 0.5)
                .frame(width: thumbSize, height: thumbSize)
                .scaleEffect(scale)
        }
        .frame(width: thumbSize, height: thumbSize)
        .offset(x: x)
    }

    private func update(cursorX: CGFloat, trackWidth: CGFloat) {
        guard trackWidth > 0 else { return }
        let rawOffset = cursorX - thumbSize / 2
        let frac = Double(max(0, min(trackWidth, rawOffset)) / trackWidth)
        let hour = Int((Double(lower) + frac * span).rounded())

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            switch activeThumb {
            case .start:
                let clamped = min(max(hour, lower), endHour - 1)
                if clamped != startHour { startHour = clamped }
            case .end:
                let clamped = max(min(hour, upper), startHour + 1)
                if clamped != endHour { endHour = clamped }
            case .none:
                break
            }
        }
    }
}
