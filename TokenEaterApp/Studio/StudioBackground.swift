import SwiftUI

/// Ambient background of the Studio space -> a slow violet/blue aurora
/// drifting over the base dark, darkened towards the edges (vignette) so the
/// switcher cards and the artboard stay the focal point. The drift freezes
/// into a static gradient under Reduce Motion.
struct StudioBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var drift = false

    var body: some View {
        ZStack {
            DS.Palette.bgBase

            RadialGradient(
                colors: [DS.Palette.accentStudio.opacity(0.15), .clear],
                center: drift ? UnitPoint(x: 0.70, y: 0.10) : UnitPoint(x: 0.14, y: 0.24),
                startRadius: 0,
                endRadius: 480
            )

            RadialGradient(
                colors: [DS.Palette.semanticInfo.opacity(0.09), .clear],
                center: drift ? UnitPoint(x: 0.22, y: 0.86) : UnitPoint(x: 0.86, y: 0.66),
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
        .onAppear {
            startDriftIfAllowed()
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                withAnimation(.easeInOut(duration: 0.5)) { drift = false }
            } else {
                startDriftIfAllowed()
            }
        }
    }

    private func startDriftIfAllowed() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 26).repeatForever(autoreverses: true)) {
            drift = true
        }
    }
}
