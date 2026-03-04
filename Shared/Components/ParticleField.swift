import SwiftUI

struct ParticleField: View {
    let particleCount: Int
    let speed: Double
    let color: Color
    let radius: CGFloat
    let isActive: Bool

    init(particleCount: Int = 20, speed: Double = 0.5, color: Color = .white, radius: CGFloat = 120, isActive: Bool = true) {
        self.particleCount = particleCount
        self.speed = speed
        self.color = color
        self.radius = radius
        self.isActive = isActive
    }

    var body: some View {
        if isActive {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                particleCanvas(time: timeline.date.timeIntervalSinceReferenceDate * (0.2 + speed * 0.8))
            }
        } else {
            particleCanvas(time: 0)
        }
    }

    private func particleCanvas(time: Double) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            for i in 0..<particleCount {
                let phase = Double(i) / Double(particleCount) * .pi * 2
                let orbitSpeed = 0.3 + Double(i % 5) * 0.15
                let angle = time * orbitSpeed + phase
                let r = radius * (0.7 + 0.3 * sin(time * 0.5 + phase))

                let x = center.x + cos(angle) * r
                let y = center.y + sin(angle) * r

                let opacity = 0.2 + 0.4 * (sin(time * 2 + phase) * 0.5 + 0.5)
                let dotSize = 1.5 + sin(time + phase) * 0.8

                let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
            }
        }
    }
}
