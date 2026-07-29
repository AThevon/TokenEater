import SwiftUI
import Foundation

/// Ambient background of the Studio space -> a slow violet/blue aurora
/// drifting over the base dark, darkened towards the edges (vignette) so the
/// switcher cards and the artboard stay the focal point.
///
/// Driven by a `TimelineView` capped at a low frame rate rather than a
/// per-frame `repeatForever` animation: the drift is imperceptibly slow, so
/// 12 fps looks identical while costing a fraction of the frame budget, and
/// `TimelineView` pauses itself whenever the window is occluded or not
/// frontmost. Under Reduce Motion it renders a single static frame.
struct StudioBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: reduceMotion)) { context in
            aurora(phase: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate)
        }
    }

    private func aurora(phase: TimeInterval) -> some View {
        // Two slow, coprime periods so the two glows never lock into an
        // obvious repeating pattern. 0...1 oscillators.
        let a = (sin(phase * (2 * .pi / 41)) + 1) / 2
        let b = (cos(phase * (2 * .pi / 53)) + 1) / 2

        return ZStack {
            DS.Palette.bgBase

            RadialGradient(
                colors: [DS.Palette.accentStudio.opacity(0.15), .clear],
                center: UnitPoint(x: 0.14 + 0.56 * a, y: 0.14 + 0.16 * b),
                startRadius: 0,
                endRadius: 480
            )

            RadialGradient(
                colors: [DS.Palette.semanticInfo.opacity(0.09), .clear],
                center: UnitPoint(x: 0.86 - 0.60 * a, y: 0.86 - 0.18 * b),
                startRadius: 0,
                endRadius: 520
            )

            // Vignette -> keeps the edges quiet so the work plane pops.
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.40)],
                center: .center,
                startRadius: 200,
                endRadius: 760
            )
        }
    }
}
