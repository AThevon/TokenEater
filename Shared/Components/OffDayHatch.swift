import SwiftUI

/// Subtle diagonal hatch drawn over the off-day spans of a pacing track, so the
/// excluded days read as "doesn't count" without changing the track height.
/// `ranges` are x-fractions (0...1) of the calendar window, already merged for
/// contiguous off-days. Drawn behind the usage fill; sized to fill its parent.
struct OffDayHatch: View {
    let ranges: [ClosedRange<Double>]
    var cornerRadius: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            var ctx = context
            ctx.clip(to: Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: cornerRadius))
            for r in ranges {
                let x0 = r.lowerBound * w
                let x1 = r.upperBound * w
                let rect = CGRect(x: x0, y: 0, width: max(0, x1 - x0), height: h)
                ctx.fill(Path(rect), with: .color(.white.opacity(0.04)))
                var hatchCtx = ctx
                hatchCtx.clip(to: Path(rect))
                var hatch = Path()
                var x = x0 - h
                while x < x1 {
                    hatch.move(to: CGPoint(x: x, y: h))
                    hatch.addLine(to: CGPoint(x: x + h, y: 0))
                    x += 4
                }
                hatchCtx.stroke(hatch, with: .color(.white.opacity(0.11)), lineWidth: 0.75)
            }
        }
        .allowsHitTesting(false)
    }
}
