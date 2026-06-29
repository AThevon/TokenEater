import SwiftUI

/// Shared press style for clickable cards (MetricTile + hero). On hover
/// the card lifts +1px and scales 1.01. On press it dips to 0.996 with
/// a subtle accent border flash for tactile feedback. No Y offset on
/// press (the user wanted "extra fin" - just a hint of depth dip).
struct CardPressStyle: ButtonStyle {
    let isHovered: Bool
    let accent: Color
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let scale: CGFloat = pressed ? 0.996 : (isHovered ? 1.01 : 1.0)
        let lift: CGFloat = isHovered ? -1 : 0

        return configuration.label
            .scaleEffect(scale)
            .offset(y: lift)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accent.opacity(pressed ? 0.45 : 0), lineWidth: 1)
            )
            // Snap-fast press (no overshoot) so the dip + bounce-back
            // is over before the flip animation even starts. Avoids
            // overlapping bounce springs that read as a blink.
            .animation(.spring(response: 0.10, dampingFraction: 0.95), value: pressed)
            .animation(.spring(response: 0.30, dampingFraction: 0.85), value: isHovered)
    }
}
