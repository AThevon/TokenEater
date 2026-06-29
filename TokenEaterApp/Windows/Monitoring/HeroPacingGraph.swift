import SwiftUI

/// Compact pacing visualisation for the hero card back. Plots
/// - the equilibrium diagonal (linear pacing from 0% to 100% over the
///   window, dashed, neutral colour),
/// - the user's actual trajectory line from origin to the current point
///   `(expectedUsage, actualUsage)` on the chart,
/// - a filled area showing the delta between the trajectory and the
///   equilibrium line, coloured by whether the user is ahead (warning)
///   or on/under pace (success).
///
/// Both axes are 0...100. `expectedUsage` doubles as "elapsed % of the
/// window" because linear pacing equates the two. So the trajectory
/// always reaches the same X-coordinate as where the equilibrium line
/// sits at that moment - the gap between them is the delta we visualise.
struct HeroPacingGraph: View {
    let actualUsage: Double
    let expectedUsage: Double
    let deltaColor: Color
    let trajectoryColor: Color

    var body: some View {
        GeometryReader { geo in
            let pad: CGFloat = 6
            let w = geo.size.width
            let h = geo.size.height
            let plotW = max(w - 2 * pad, 1)
            let plotH = max(h - 2 * pad, 1)

            let actualClamped = min(max(actualUsage, 0), 100)
            let expectedClamped = min(max(expectedUsage, 0), 100)

            let originPoint = CGPoint(x: pad, y: h - pad)
            let endDiagonal = CGPoint(x: pad + plotW, y: pad)
            let actualPoint = CGPoint(
                x: pad + plotW * expectedClamped / 100,
                y: h - pad - plotH * actualClamped / 100
            )
            let equilibriumAtX = CGPoint(
                x: actualPoint.x,
                y: h - pad - plotH * expectedClamped / 100
            )

            ZStack {
                // Subtle grid bg - 25/50/75% horizontal ticks for scale.
                Path { path in
                    for fraction in [0.25, 0.5, 0.75] {
                        let y = h - pad - plotH * fraction
                        path.move(to: CGPoint(x: pad, y: y))
                        path.addLine(to: CGPoint(x: pad + plotW, y: y))
                    }
                }
                .stroke(DS.Palette.glassBorderLo, style: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))

                // Equilibrium diagonal (linear pacing reference).
                Path { path in
                    path.move(to: originPoint)
                    path.addLine(to: endDiagonal)
                }
                .stroke(DS.Palette.textTertiary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                // Filled delta zone between the trajectory and equilibrium
                // at the current X coordinate. Triangle from origin to
                // both points so the fill grows / shrinks with the delta.
                Path { path in
                    path.move(to: originPoint)
                    path.addLine(to: actualPoint)
                    path.addLine(to: equilibriumAtX)
                    path.closeSubpath()
                }
                .fill(deltaColor.opacity(0.22))

                // Trajectory line - solid in the gauge colour.
                Path { path in
                    path.move(to: originPoint)
                    path.addLine(to: actualPoint)
                }
                .stroke(trajectoryColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))

                // Current point marker.
                Circle()
                    .fill(trajectoryColor)
                    .frame(width: 8, height: 8)
                    .dsGlow(trajectoryColor, radius: 5, opacity: 0.6)
                    .position(actualPoint)
            }
        }
    }
}
