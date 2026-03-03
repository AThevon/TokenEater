import SwiftUI

struct AnimatedGradient: View {
    let baseColors: [Color]
    let animationDuration: Double
    let isActive: Bool

    @State private var start = UnitPoint(x: 0, y: 0)
    @State private var end = UnitPoint(x: 1, y: 1)

    init(baseColors: [Color] = [Color(red: 0.10, green: 0.10, blue: 0.12), Color(red: 0.14, green: 0.12, blue: 0.18)], animationDuration: Double = 30, isActive: Bool = true) {
        self.baseColors = baseColors
        self.animationDuration = animationDuration
        self.isActive = isActive
    }

    var body: some View {
        LinearGradient(colors: baseColors, startPoint: start, endPoint: end)
            .onChange(of: isActive) { _, active in
                if active {
                    withAnimation(.easeInOut(duration: animationDuration).repeatForever(autoreverses: true)) {
                        start = UnitPoint(x: 1, y: 0)
                        end = UnitPoint(x: 0, y: 1)
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        start = UnitPoint(x: 0, y: 0)
                        end = UnitPoint(x: 1, y: 1)
                    }
                }
            }
            .onAppear {
                if isActive {
                    withAnimation(.easeInOut(duration: animationDuration).repeatForever(autoreverses: true)) {
                        start = UnitPoint(x: 1, y: 0)
                        end = UnitPoint(x: 0, y: 1)
                    }
                }
            }
    }
}
