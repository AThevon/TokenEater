import SwiftUI

struct RingGauge: View {
    let percentage: Int
    let gradient: LinearGradient
    let size: CGFloat
    let lineWidth: CGFloat
    let glowColor: Color
    let glowRadius: CGFloat

    init(
        percentage: Int,
        gradient: LinearGradient,
        size: CGFloat = 200,
        lineWidth: CGFloat? = nil,
        glowColor: Color = .clear,
        glowRadius: CGFloat = 0
    ) {
        self.percentage = percentage
        self.gradient = gradient
        self.size = size
        self.lineWidth = lineWidth ?? max(size * 0.08, 4)
        self.glowColor = glowColor
        self.glowRadius = glowRadius
    }

    @State private var animatedPct: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: animatedPct / 100)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: glowColor.opacity(0.6), radius: glowRadius)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animatedPct = Double(percentage)
            }
        }
        .onChange(of: percentage) { _, newValue in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animatedPct = Double(newValue)
            }
        }
    }
}
