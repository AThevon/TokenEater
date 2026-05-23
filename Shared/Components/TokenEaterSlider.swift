import SwiftUI

/// A custom SwiftUI slider designed for macOS in both light and dark themes.
/// The native `Slider` barely honors `.tint()` on macOS - in light theme the
/// filled portion stays invisible, which is the original bug from #158.
///
/// This implementation builds the control from scratch with a Capsule track,
/// a tint-colored fill, a soft halo on hover/drag, and a white thumb that
/// grows subtly when interacted with. Drag updates bypass implicit animations
/// so the thumb tracks the cursor 1:1 with no spring overshoot, while hover
/// and release transitions use `.snappy` springs for a tactile, alive feel.
struct TokenEaterSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color
    let showsTicks: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isDragging = false

    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 14
    private let hoverScale: CGFloat = 1.2
    private let dragScale: CGFloat = 1.35
    private let haloRatio: CGFloat = 2.4
    private let tickWidth: CGFloat = 1.5

    init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double = 1,
        tint: Color = DS.Palette.accentSettings,
        showsTicks: Bool = false
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.tint = tint
        self.showsTicks = showsTicks
    }

    private var thumbScale: CGFloat {
        if isDragging { return dragScale }
        if isHovering { return hoverScale }
        return 1.0
    }

    private var haloOpacity: Double {
        if isDragging { return 0.32 }
        if isHovering { return 0.18 }
        return 0.0
    }

    private var stateAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0.0)
    }

    var body: some View {
        GeometryReader { geo in
            let trackWidth = max(0, geo.size.width - thumbSize)
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0
                ? max(0, min(1, (value - range.lowerBound) / span))
                : 0
            let thumbX = CGFloat(fraction) * trackWidth
            let filledWidth = thumbX + thumbSize / 2

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(isHovering || isDragging ? 0.18 : 0.12))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(tint)
                    .frame(width: filledWidth, height: trackHeight)

                if showsTicks, step > 0, span > 0 {
                    let stepCount = Int((span / step).rounded())
                    if stepCount > 1 {
                        ForEach(1..<stepCount, id: \.self) { i in
                            let stepValue = range.lowerBound + Double(i) * step
                            let stepFraction = (stepValue - range.lowerBound) / span
                            let isPassed = stepValue <= value
                            Rectangle()
                                .fill(isPassed ? Color.white.opacity(0.55) : Color.primary.opacity(0.32))
                                .frame(width: tickWidth, height: trackHeight - 1)
                                .offset(x: CGFloat(stepFraction) * trackWidth + thumbSize / 2 - tickWidth / 2)
                        }
                    }
                }

                Circle()
                    .fill(tint)
                    .frame(width: thumbSize * haloRatio, height: thumbSize * haloRatio)
                    .opacity(haloOpacity)
                    .blur(radius: isDragging ? 6 : 4)
                    .offset(x: thumbX + thumbSize / 2 - (thumbSize * haloRatio) / 2)
                    .allowsHitTesting(false)

                Circle()
                    .fill(Color.white)
                    .overlay(
                        Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(
                        color: Color.black.opacity(isDragging ? 0.28 : 0.16),
                        radius: isDragging ? 3 : 1.5,
                        y: isDragging ? 1.5 : 0.5
                    )
                    .frame(width: thumbSize, height: thumbSize)
                    .scaleEffect(thumbScale)
                    .offset(x: thumbX)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                        }
                        updateValue(cursorX: drag.location.x, trackWidth: trackWidth)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .animation(stateAnimation, value: isHovering)
            .animation(stateAnimation, value: isDragging)
            .accessibilityElement(children: .ignore)
            .accessibilityValue(Text(String(format: "%.0f", value)))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    let next = min(value + step, range.upperBound)
                    if next != value { value = next }
                case .decrement:
                    let prev = max(value - step, range.lowerBound)
                    if prev != value { value = prev }
                @unknown default:
                    break
                }
            }
        }
        // The slider's GeometryReader + ZStack centering renders the track at
        // a slightly lower visual position than adjacent text/icon baselines
        // in an HStack. Lift the rendering up by a few points without changing
        // the layout frame so the track aligns with the -/+ icons.
        .frame(height: thumbSize)
        .offset(y: -9)
    }

    private func updateValue(cursorX: CGFloat, trackWidth: CGFloat) {
        guard trackWidth > 0 else { return }
        let span = range.upperBound - range.lowerBound

        // Cursor position is where the thumb's center should land.
        // Subtract half the thumb to align center with the offset origin.
        let rawOffset = cursorX - thumbSize / 2
        let clampedOffset = max(0, min(trackWidth, rawOffset))
        let fraction = clampedOffset / trackWidth
        let raw = range.lowerBound + Double(fraction) * span
        let stepped = step > 0 ? (raw / step).rounded() * step : raw
        let clamped = min(max(stepped, range.lowerBound), range.upperBound)

        guard clamped != value else { return }
        // Bypass any ambient transactions so the thumb tracks the cursor
        // immediately, with no implicit spring interpolation on the offset.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            value = clamped
        }
    }
}
