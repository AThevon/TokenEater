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

    enum CodingKeys: String, CodingKey {
        case uuid, name
        case organizationType = "organization_type"
        case billingType = "billing_type"
        case rateLimitTier = "rate_limit_tier"
    }
}

enum PlanType: String, Codable {
    case pro, max, team, enterprise, free, unknown

    init(from account: AccountInfo, organization: OrganizationInfo?) {
        if account.hasClaudeMax { self = .max }
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
        case .team: return "TEAM"
        case .enterprise: return "ENTERPRISE"
        case .free: return "FREE"
        case .unknown: return ""
        }
    }

    var badgeColor: Color {
        switch self {
        case .max: return .purple
        case .pro: return .blue
        case .team: return .teal
        case .enterprise: return .orange
        case .free: return .gray
        case .unknown: return .clear
        }
    }
}

extension String {
    var formattedRateLimitTier: String {
        let stripped = replacingOccurrences(of: "default_claude_", with: "")
        let spaced = stripped.replacingOccurrences(of: "_", with: " ")
        guard let first = spaced.first else { return spaced }
        return String(first).uppercased() + spaced.dropFirst()
    }
}
