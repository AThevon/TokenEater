import SwiftUI

/// Environment-driven glow intensity. Every `.dsGlow()` call reads this from
/// the environment so a single setter on the App root applies to the entire
/// view tree -> no need to plumb the value through every call site.
private struct GlowIntensityKey: EnvironmentKey {
    static let defaultValue: DS.GlowIntensity = .glow
}

extension EnvironmentValues {
    var glowIntensity: DS.GlowIntensity {
        get { self[GlowIntensityKey.self] }
        set { self[GlowIntensityKey.self] = newValue }
    }
}

/// Applies `.shadow()` with radius + opacity scaled by the current `glowIntensity`
/// from the environment. When the intensity zeroes out radius or opacity, the
/// shadow is omitted entirely so SwiftUI can elide the render pass.
private struct DSGlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let opacity: Double
    let yOffset: CGFloat

    @Environment(\.glowIntensity) private var intensity

    func body(content: Content) -> some View {
        if intensity.radiusMultiplier > 0 && intensity.opacityMultiplier > 0 {
            content.shadow(
                color: color.opacity(opacity * intensity.opacityMultiplier),
                radius: radius * intensity.radiusMultiplier,
                y: yOffset
            )
        } else {
            content
        }
    }
}

extension View {
    /// Design-system glow that respects the user's `GlowIntensity` setting.
    ///
    /// Use this in place of `.shadow(color: color.opacity(o), radius: r)`:
    /// pass the base color (without opacity baked in), the desired radius,
    /// and the opacity multiplier. The current environment intensity scales
    /// both before SwiftUI applies the shadow.
    func dsGlow(
        _ color: Color,
        radius: CGFloat,
        opacity: Double = 0.6,
        y: CGFloat = 0
    ) -> some View {
        modifier(DSGlowModifier(color: color, radius: radius, opacity: opacity, yOffset: y))
    }
}
