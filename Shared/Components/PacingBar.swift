import SwiftUI

struct PacingBar: View {
    let actual: Double
    let expected: Double
    let zone: PacingZone
    let gradient: LinearGradient
    let compact: Bool

    init(actual: Double, expected: Double, zone: PacingZone, gradient: LinearGradient, compact: Bool = false) {
        self.actual = actual
        self.expected = expected
        self.zone = zone
        self.gradient = gradient
        self.compact = compact
    }

    @State private var animatedActual: Double = 0
    @State private var pulsing = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: compact ? 2 : 4)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: compact ? 4 : 8)

                RoundedRectangle(cornerRadius: compact ? 2 : 4)
                    .fill(gradient)
                    .frame(width: max(0, geo.size.width * CGFloat(min(animatedActual, 100)) / 100), height: compact ? 4 : 8)

                idealMarker
                    .offset(x: geo.size.width * CGFloat(min(expected, 100)) / 100 - (compact ? 3 : 5))

                if !compact {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: .white.opacity(0.5), radius: pulsing ? 6 : 2)
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

    private var idealMarker: some View {
        let size: CGFloat = compact ? 6 : 10
        return Path { path in
            path.move(to: CGPoint(x: size / 2, y: 0))
            path.addLine(to: CGPoint(x: size, y: size))
            path.addLine(to: CGPoint(x: 0, y: size))
            path.closeSubpath()
        }
        .fill(Color.white.opacity(0.5))
        .frame(width: size, height: size)
    }
}
