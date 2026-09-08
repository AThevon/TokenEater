import Foundation
import SwiftUI

/// ChatGPT plan behind a Codex login, as reported by the usage endpoint (and,
/// offline, by the `chatgpt_plan_type` claim of the access token).
///
/// The backend enum is long and still growing (`guest`, `free_workspace`,
/// `quorum`, `k12`, ...), so unrecognised values are preserved verbatim rather
/// than collapsed into a single "unknown" bucket: a new plan then shows its own
/// name in the badge instead of disappearing.
enum CodexPlanType: Equatable {

    // MARK: - Enumeration Cases

    case free
    case plus
    case pro
    case proLite
    case team
    case business
    case enterprise
    case edu
    case other(String)
    case unknown

    // MARK: - Initializers

    init(rawPlan: String?) {
        guard let raw = rawPlan?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else {
            self = .unknown
            return
        }
        switch raw {
        case "free", "guest": self = .free
        case "plus", "go": self = .plus
        case "pro": self = .pro
        case "prolite": self = .proLite
        case "team", "free_workspace": self = .team
        case "business", "self_serve_business_prolite", "self_serve_business_usage_based": self = .business
        case "enterprise", "ent26", "enterprise_cbp_automation", "enterprise_cbp_usage_based": self = .enterprise
        case "edu", "education", "edu_plus", "edu_pro", "k12": self = .edu
        default: self = .other(raw)
        }
    }

    // MARK: - Public Properties

    var displayLabel: String {
        switch self {
        case .free: return "FREE"
        case .plus: return "PLUS"
        case .pro: return "PRO"
        case .proLite: return "PRO LITE"
        case .team: return "TEAM"
        case .business: return "BUSINESS"
        case .enterprise: return "ENTERPRISE"
        case .edu: return "EDU"
        case .other(let raw): return raw.replacingOccurrences(of: "_", with: " ").uppercased()
        case .unknown: return ""
        }
    }

    var badgeColor: Color {
        switch self {
        case .pro, .proLite: return .purple
        case .plus: return .blue
        case .team: return .teal
        case .business, .enterprise: return .orange
        case .edu: return .green
        case .free: return .gray
        case .other: return .gray
        case .unknown: return .clear
        }
    }
}
