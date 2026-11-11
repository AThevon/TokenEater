import Foundation
import SwiftUI

struct ProfileResponse: Codable {
    let account: AccountInfo
    let organization: OrganizationInfo?
}

struct AccountInfo: Codable {
    let uuid: String
    let fullName: String
    let displayName: String
    let email: String
    let hasClaudeMax: Bool
    let hasClaudePro: Bool

    enum CodingKeys: String, CodingKey {
        case uuid
        case fullName = "full_name"
        case displayName = "display_name"
        case email
        case hasClaudeMax = "has_claude_max"
        case hasClaudePro = "has_claude_pro"
    }
}

struct OrganizationInfo: Codable {
    let uuid: String
    let name: String
    let organizationType: String
    let billingType: String
    let rateLimitTier: String
    /// The plan's marketing name ("Ultra"). The only field that tells an
    /// Ultra subscription from a Max 20x one: both report
    /// `organization_type` "claude_max", `rate_limit_tier`
    /// "default_claude_max_20x" and `has_claude_max`.
    let planDisplayName: String?
    /// The same name as a label ("Ultra plan"), read when the name is absent.
    let planDisplayLabel: String?

    enum CodingKeys: String, CodingKey {
        case uuid, name
        case organizationType = "organization_type"
        case billingType = "billing_type"
        case rateLimitTier = "rate_limit_tier"
        case planDisplayName = "plan_display_name"
        case planDisplayLabel = "plan_display_label"
    }

    init(
        uuid: String,
        name: String,
        organizationType: String,
        billingType: String,
        rateLimitTier: String,
        planDisplayName: String? = nil,
        planDisplayLabel: String? = nil
    ) {
        self.uuid = uuid
        self.name = name
        self.organizationType = organizationType
        self.billingType = billingType
        self.rateLimitTier = rateLimitTier
        self.planDisplayName = planDisplayName
        self.planDisplayLabel = planDisplayLabel
    }

    // The plan names are read leniently: a missing or odd one must never cost
    // the profile, which also carries the identity the accounts rely on.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decode(String.self, forKey: .uuid)
        name = try container.decode(String.self, forKey: .name)
        organizationType = try container.decode(String.self, forKey: .organizationType)
        billingType = try container.decode(String.self, forKey: .billingType)
        rateLimitTier = try container.decode(String.self, forKey: .rateLimitTier)
        planDisplayName = try? container.decodeIfPresent(String.self, forKey: .planDisplayName)
        planDisplayLabel = try? container.decodeIfPresent(String.self, forKey: .planDisplayLabel)
    }

    /// Whether the organization's plan is Claude Ultra, the plan with a
    /// weekly limit and no 5-hour session window.
    var isUltraPlan: Bool {
        [planDisplayName, planDisplayLabel].contains { name in
            guard let name else { return false }
            return name.lowercased().split(whereSeparator: { !$0.isLetter }).contains("ultra")
        }
    }
}

enum PlanType: String, Codable {
    case pro, max, ultra, team, enterprise, free, unknown

    init(from account: AccountInfo, organization: OrganizationInfo?) {
        // Checked before the flags: an Ultra subscription also reports
        // `has_claude_max`, and only its plan name sets it apart.
        if organization?.isUltraPlan == true { self = .ultra }
        else if account.hasClaudeMax { self = .max }
        else if account.hasClaudePro { self = .pro }
        else if let orgType = organization?.organizationType {
            switch orgType {
            case "claude_team": self = .team
            case "claude_enterprise": self = .enterprise
            default: self = .free
            }
        }
        else { self = .free }
    }

    var displayLabel: String {
        switch self {
        case .pro: return "PRO"
        case .max: return "MAX"
        case .ultra: return "ULTRA"
        case .team: return "TEAM"
        case .enterprise: return "ENTERPRISE"
        case .free: return "FREE"
        case .unknown: return ""
        }
    }

    var badgeColor: Color {
        switch self {
        case .max: return .purple
        case .ultra: return .pink
        case .pro: return .blue
        case .team: return .teal
        case .enterprise: return .orange
        case .free: return .gray
        case .unknown: return .clear
        }
    }

    /// Whether the plan is known to come without the 5-hour session window.
    /// Only a fallback for before any usage has landed: once it has, whether
    /// the response carries the window is the fact that counts
    /// (`UsageStore.hasSessionWindow`).
    var lacksSessionWindow: Bool { self == .ultra }
}

extension String {
    var formattedRateLimitTier: String {
        let stripped = replacingOccurrences(of: "default_claude_", with: "")
        let spaced = stripped.replacingOccurrences(of: "_", with: " ")
        guard let first = spaced.first else { return spaced }
        return String(first).uppercased() + spaced.dropFirst()
    }
}
