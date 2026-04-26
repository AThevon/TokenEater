import Foundation
import SwiftUI
import AppKit

/// Smart-color v2 risk model. Pure functional layer - no UI, no I/O,
/// no state. The math sits here so it can be unit-tested in isolation
/// (see `SmartColorTests`); the `ThemeColors` extension below adapts
/// the result back to the existing public API (`smartGaugeColor`,
/// `smartLevel`, etc.).
///
/// Design rationale + invariants are documented in the project notes
/// under "Smart Color v2". Short version:
/// - `risk` is a continuous score in [0, 1] derived from three
///   independent sources (absolute, projection, pacing).
/// - Each source uses `smoothstep` for C1 continuity, so the output
///   never exhibits cliffs around threshold/margin/time-remaining
///   boundaries.
/// - Confidence weighting on the time-derived sources (projection,
///   pacing) suppresses early-window noise.
/// - The discrete zone (chill/onTrack/warning/hot) is derived with
///   optional hysteresis to prevent flicker when the risk oscillates
///   around a band boundary.
enum SmartColor {

    // MARK: - Mathematical primitives

    /// Hermite-smoothed step function. Continuous (C1) clamp from a to b.
    /// Returns 0 when x <= a, 1 when x >= b, smoothly interpolated in between.
    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        guard a < b else { return x >= b ? 1 : 0 }
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// Confidence in the rate estimate, growing from 0 to ~1 across the
    /// window. Used to dampen projection / pacing risk early when the
    /// rate computed from a few elapsed minutes is noisy. The growth
    /// rate `k` is profile-tunable.
    static func confidence(e: Double, k: Double = 5.0) -> Double {
        1 - exp(-k * max(0, e))
    }

    // MARK: - Risk components

    /// Component A - absolute risk: how close to the limit, irrespective
    /// of pacing. Drives the "98% must always feel red" property.
    static func absoluteRisk(u: Double, θw: Double, θc: Double) -> Double {
        smoothstep(θw, θc, u)
    }

    /// Component B - projection risk: at the current consumption rate,
    /// how much over the limit will we end the window? Saturates at the
    /// profile-defined `projUpper` (default 1.4 = hitting the limit at
    /// ~71% of the window). Weighted by confidence so the early-window
    /// 5%/1% scenario doesn't scream.
    static func projectionRisk(u: Double, e: Double, params: SmartColorParameters = .default) -> Double {
        guard u > 0.0001, e > 0.0001 else { return 0 }
        let projected = u / e
        let raw = smoothstep(1.0, params.projUpper, projected)
        return raw * confidence(e: e, k: params.k)
    }

    /// Component C - pacing risk: gap between actual utilization and the
    /// linear pace. Only positive deltas (ahead of schedule) escalate.
    /// 0 inside the user's `m` margin, ramps to 1 as delta grows 15pp
    /// past m. Same confidence weighting as projection.
    static func pacingRisk(u: Double, e: Double, m: Double, params: SmartColorParameters = .default) -> Double {
        let delta = u - e
        let raw = smoothstep(m, m + 0.15, delta)
        return raw * confidence(e: e, k: params.k)
    }

    /// Combines the three components via `max`. The most conservative
    /// signal wins - none can mask another's red flag. Hard-caps at 1.0
    /// when utilization >= 100%.
    ///
    /// The absolute component is dampened by **projection health** so we
    /// don't fire a "you've burnt a lot" alert when the current rate
    /// projects a comfortable finish under the limit. Concretely:
    ///
    /// ```text
    /// projectionHealth = smoothstep(0.7, 1.0, u / e)
    /// a = absoluteRisk × projectionHealth
    /// ```
    ///
    /// At `u/e ≥ 1` (you'll hit or overshoot the limit), `projectionHealth`
    /// saturates to 1 and `a` fires at full strength - the 98%/30min hard
    /// flag is preserved. At `u/e ≤ 0.7` (you'll finish well below), the
    /// multiplier drops to 0 and absolute is suppressed - quieting the
    /// false alarm at e.g. 72% with calm pacing where the v1+early-v2
    /// behaviour would have shown amber despite no real risk.
    ///
    /// `combinedRisk` is the only place this dampening lives. The pure
    /// `absoluteRisk` function stays untouched so the no-reset fallback
    /// (`smartRisk` -> `absoluteRisk` directly) keeps the raw consumption
    /// signal when no projection data is available.
    static func combinedRisk(u: Double, e: Double, θw: Double, θc: Double, m: Double, params: SmartColorParameters = .default) -> Double {
        if u >= 1.0 { return 1.0 }
        let aRaw = absoluteRisk(u: u, θw: θw, θc: θc)
        let projectionHealth: Double = {
            guard e > 0.0001 else { return 1.0 }
            return smoothstep(0.7, 1.0, u / e)
        }()
        let a = aRaw * projectionHealth
        let b = projectionRisk(u: u, e: e, params: params)
        let c = pacingRisk(u: u, e: e, m: m, params: params)
        return max(a, max(b, c))
    }

    // MARK: - Color interpolation

    /// Continuous color across 4 anchor stops:
    /// - 0.00 -> normal (chill)
    /// - 0.30 -> normal (still chill)
    /// - 0.55 -> warning (orange)
    /// - 0.85 -> critical (red)
    /// - 1.00 -> critical
    /// Linear RGBA interpolation between adjacent stops avoids visible
    /// banding even though the underlying zones are discrete.
    static func colorForRisk(_ risk: Double, theme: ThemeColors) -> Color {
        let r = max(0, min(1, risk))
        let normal = Color(hex: theme.gaugeNormal)
        let warning = Color(hex: theme.gaugeWarning)
        let critical = Color(hex: theme.gaugeCritical)

        if r <= 0.30 { return normal }
        if r >= 0.85 { return critical }
        if r <= 0.55 {
            let t = (r - 0.30) / 0.25
            return interpolate(normal, warning, t: t)
        }
        let t = (r - 0.55) / 0.30
        return interpolate(warning, critical, t: t)
    }

    /// NSColor variant for AppKit surfaces (menu bar, popover chrome).
    static func nsColorForRisk(_ risk: Double, theme: ThemeColors) -> NSColor {
        let r = max(0, min(1, risk))
        let normal = NSColor(hex: theme.gaugeNormal)
        let warning = NSColor(hex: theme.gaugeWarning)
        let critical = NSColor(hex: theme.gaugeCritical)

        if r <= 0.30 { return normal }
        if r >= 0.85 { return critical }
        if r <= 0.55 {
            let t = CGFloat((r - 0.30) / 0.25)
            return interpolateNS(normal, warning, t: t)
        }
        let t = CGFloat((r - 0.55) / 0.30)
        return interpolateNS(warning, critical, t: t)
    }

    private static func interpolate(_ a: Color, _ b: Color, t: Double) -> Color {
        let nsA = NSColor(a).usingColorSpace(.sRGB) ?? .gray
        let nsB = NSColor(b).usingColorSpace(.sRGB) ?? .gray
        let f = CGFloat(max(0, min(1, t)))
        return Color(
            red:   Double(nsA.redComponent   + (nsB.redComponent   - nsA.redComponent)   * f),
            green: Double(nsA.greenComponent + (nsB.greenComponent - nsA.greenComponent) * f),
            blue:  Double(nsA.blueComponent  + (nsB.blueComponent  - nsA.blueComponent)  * f),
            opacity: Double(nsA.alphaComponent + (nsB.alphaComponent - nsA.alphaComponent) * f)
        )
    }

    private static func interpolateNS(_ a: NSColor, _ b: NSColor, t: CGFloat) -> NSColor {
        let aRGB = a.usingColorSpace(.sRGB) ?? a
        let bRGB = b.usingColorSpace(.sRGB) ?? b
        let f = max(0, min(1, t))
        return NSColor(
            srgbRed: aRGB.redComponent   + (bRGB.redComponent   - aRGB.redComponent)   * f,
            green:   aRGB.greenComponent + (bRGB.greenComponent - aRGB.greenComponent) * f,
            blue:    aRGB.blueComponent  + (bRGB.blueComponent  - aRGB.blueComponent)  * f,
            alpha:   aRGB.alphaComponent + (bRGB.alphaComponent - aRGB.alphaComponent) * f
        )
    }

    // MARK: - Zone derivation

    /// Discrete zone for risk, with optional hysteresis. When `previous`
    /// is provided, transitions in the falling direction need an extra
    /// 5pp buffer to avoid flicker around a boundary.
    ///
    /// Rising thresholds (cold start):
    ///   chill < 0.30 <= onTrack < 0.55 <= warning < 0.78 <= hot
    ///
    /// Falling thresholds (held by previous zone):
    ///   keep hot until r < 0.73; keep warning until r < 0.50;
    ///   keep onTrack until r < 0.25.
    static func zoneForRisk(_ risk: Double, previous: PacingZone? = nil, params: SmartColorParameters = .default) -> PacingZone {
        let r = max(0, min(1, risk))
        let rising = (chill: params.chillThreshold, warning: params.warningThreshold, hot: params.hotThreshold)
        let falling = (chill: params.fallingChill, warning: params.fallingWarning, hot: params.fallingHot)

        guard let previous else {
            return zoneFromRising(r, rising: rising)
        }

        switch previous {
        case .chill:
            return zoneFromRising(r, rising: rising)
        case .onTrack:
            if r >= rising.hot     { return .hot }
            if r >= rising.warning { return .warning }
            if r <  falling.chill  { return .chill }
            return .onTrack
        case .warning:
            if r >= rising.hot     { return .hot }
            if r <  falling.chill  { return .chill }
            if r <  falling.warning { return .onTrack }
            return .warning
        case .hot:
            if r <  falling.chill   { return .chill }
            if r <  falling.warning { return .onTrack }
            if r <  falling.hot     { return .warning }
            return .hot
        }
    }

    private static func zoneFromRising(_ r: Double, rising: (chill: Double, warning: Double, hot: Double)) -> PacingZone {
        if r >= rising.hot     { return .hot }
        if r >= rising.warning { return .warning }
        if r >= rising.chill   { return .onTrack }
        return .chill
    }

    // MARK: - Legacy 3-level mapping

    /// Maps the continuous risk back to the legacy `SmartLevel` enum
    /// used by `NotificationService` and other call sites that haven't
    /// been migrated to the 4-zone system. Boundaries chosen so
    /// `.warning` aligns with the orange band and `.critical` with the
    /// red band.
    static func legacyLevel(forRisk risk: Double) -> ThemeColors.SmartLevel {
        if risk >= 0.78 { return .critical }
        if risk >= 0.50 { return .warning }
        return .normal
    }
}
