import Foundation

/// User-selectable temperament for the smart-color algorithm. Names
/// describe the system's attitude (how readily it alerts). Each
/// profile dials internal knobs:
///
/// - `k` -> growth rate of `c(e) = 1 - exp(-k·e)`. Higher k = projection
///   and pacing count earlier in the window.
/// - `projUpper` -> upper bound of the projection-overflow smoothstep.
///   Lower = panics for smaller projected overflows.
/// - `absoluteLower` / `absoluteUpper` -> smoothstep bounds for the
///   absolute-risk component in smart mode.
/// - zone thresholds -> where the discrete bands switch on the [0,1]
///   risk continuum. Lower = more pessimistic mapping.
enum SmartColorProfile: String, CaseIterable, Codable, Sendable {
    case patient, balanced, vigilant

    static let `default`: SmartColorProfile = .balanced

    var parameters: SmartColorParameters {
        switch self {
        case .patient:
            return SmartColorParameters(
                k: 3.0,
                projUpper: 1.6,
                absoluteLower: 0.55,
                absoluteUpper: 1.05,
                chillThreshold: 0.38,
                warningThreshold: 0.62,
                hotThreshold: 0.85
            )
        case .balanced:
            return SmartColorParameters(
                k: 5.0,
                projUpper: 1.4,
                absoluteLower: 0.50,
                absoluteUpper: 1.00,
                chillThreshold: 0.30,
                warningThreshold: 0.55,
                hotThreshold: 0.78
            )
        case .vigilant:
            return SmartColorParameters(
                k: 8.0,
                projUpper: 1.2,
                absoluteLower: 0.45,
                absoluteUpper: 0.90,
                chillThreshold: 0.22,
                warningThreshold: 0.45,
                hotThreshold: 0.68
            )
        }
    }

    var displayLabelKey: String {
        "settings.smartColor.profile.\(rawValue)"
    }
}

/// Concrete tuning knobs consumed by `SmartColor` primitives. Falling
/// thresholds for hysteresis are derived as `rising - 0.05` so the
/// 5-percentage-point buffer scales with the chosen profile.
///
/// `absoluteLower` / `absoluteUpper` are the smoothstep bounds for the
/// absolute-risk component in smart mode. They replace the previous
/// reuse of the user's threshold sliders so smart mode is fully
/// self-calibrated by the chosen profile (the user's threshold sliders
/// only drive the threshold-mode coloring now).
struct SmartColorParameters: Equatable, Sendable {
    let k: Double
    let projUpper: Double
    let absoluteLower: Double
    let absoluteUpper: Double
    let chillThreshold: Double
    let warningThreshold: Double
    let hotThreshold: Double

    static let `default` = SmartColorProfile.balanced.parameters

    var fallingChill: Double { max(0, chillThreshold - 0.05) }
    var fallingWarning: Double { max(0, warningThreshold - 0.05) }
    var fallingHot: Double { max(0, hotThreshold - 0.05) }
}
