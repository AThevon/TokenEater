import SwiftUI

/// The provider marks.
///
/// Neither Anthropic nor OpenAI licenses its logo for this. Anthropic's
/// trademark guidelines permit their marks only in material they approve
/// beforehand, with no nominative carve-out, and OpenAI's brand kit forbids
/// anything that suggests endorsement. Using one official logo and not the
/// other would also break the symmetry the whole provider design rests on, so
/// the app draws its own.
///
/// One construction, not two logos: a 24-unit grid, a 9.6-unit outer radius, a
/// 2-unit stroke, round joins. What separates the providers is the order of
/// symmetry, eight for Claude's burst and six for OpenAI's rosette. A third
/// provider is another order on the same grid rather than a new asset to
/// negotiate.
///
/// Strokes rather than fills on purpose: these render small, and a filled
/// shape at 12 points loses its interior detail while a stroked one thins
/// evenly. The line width scales with the glyph and has a floor, the way SF
/// Symbols hold their optical weight.
///
/// Deliberately not SF Symbols. `sparkle` described a mood, and `terminal`
/// described Codex the CLI rather than OpenAI the provider.
struct ProviderGlyph: View {
    let provider: MetricProvider
    var size: CGFloat = 16

    var body: some View {
        Group {
            switch provider {
            case .claude:
                AsteriskGlyph()
                    .stroke(style: StrokeStyle(lineWidth: lineWidth(2.1, floor: 1.0), lineCap: .round))
            case .codex:
                RosetteGlyph()
                    .stroke(lineWidth: lineWidth(1.9, floor: 1.2))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func lineWidth(_ units: CGFloat, floor: CGFloat) -> CGFloat {
        max(floor, size * units / 24)
    }
}

/// Claude: three strokes through the centre, eight-fold symmetry counting the
/// implied axes. An asterisk belongs to typography rather than to a company,
/// which is exactly why it is safe to use here.
struct AsteriskGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 24
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for degrees in [-90.0, -30.0, 30.0] {
            let angle = degrees * .pi / 180
            let dx = cos(angle) * 9.6 * unit
            let dy = sin(angle) * 9.6 * unit
            path.move(to: CGPoint(x: centre.x - dx, y: centre.y - dy))
            path.addLine(to: CGPoint(x: centre.x + dx, y: centre.y + dy))
        }
        return path
    }
}

/// OpenAI: three ellipses at sixty degrees, so six-fold symmetry. It keeps the
/// symmetry of the official mark, which is the recognisable part, and not its
/// interlace, which is the part that would read as a redraw.
struct RosetteGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 24
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        // Flatter ellipses (ry around 3.7) make three crossed orbits, which reads
        // as an atom and, at this stroke weight, as a well-known JavaScript
        // logo. Opening them to ry 5.4 turns the crossings into six lobes
        // around a hexagonal void, which is the rosette we actually want, and
        // it still holds at 13 points where the flatter version muddied.
        let bounds = CGRect(
            x: centre.x - 9.2 * unit, y: centre.y - 5.4 * unit,
            width: 18.4 * unit, height: 10.8 * unit
        )
        var path = Path()
        for index in 0..<3 {
            let rotation = CGAffineTransform(translationX: -centre.x, y: -centre.y)
                .concatenating(CGAffineTransform(rotationAngle: Double(index) * .pi / 3))
                .concatenating(CGAffineTransform(translationX: centre.x, y: centre.y))
            path.addPath(Path(ellipseIn: bounds).applying(rotation))
        }
        return path
    }
}
