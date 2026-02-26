import SwiftUI

struct AnimatedGradient: View {
    let baseColors: [Color]
    let animationDuration: Double

    @State private var start = UnitPoint(x: 0, y: 0)
    @State private var end = UnitPoint(x: 1, y: 1)

    init(baseColors: [Color] = [Color(red: 0.04, green: 0.04, blue: 0.10), Color(red: 0.08, green: 0.08, blue: 0.16)], animationDuration: Double = 30) {
        self.baseColors = baseColors
        self.animationDuration = animationDuration
    }

    var body: some View {
        LinearGradient(colors: baseColors, startPoint: start, endPoint: end)
            .onAppear {
                withAnimation(.easeInOut(duration: animationDuration).repeatForever(autoreverses: true)) {
                    start = UnitPoint(x: 1, y: 0)
                    end = UnitPoint(x: 0, y: 1)
                }
            }
    }
}
