import Foundation

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
    case pro, max, free, unknown

    init(from account: AccountInfo) {
        if account.hasClaudeMax { self = .max }
        else if account.hasClaudePro { self = .pro }
        else { self = .free }
    }
}
