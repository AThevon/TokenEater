import Testing
import Foundation
import SwiftUI

@Suite("ProfileModels")
struct ProfileModelTests {

    @Test("decodes profile JSON with all fields")
    func decodesFullProfile() throws {
        let json = """
        {
          "account": {
            "uuid": "abc",
            "full_name": "John Doe",
            "display_name": "John",
            "email": "john@example.com",
            "has_claude_max": false,
            "has_claude_pro": true
          },
          "organization": {
            "uuid": "org1",
            "name": "My Org",
            "organization_type": "claude_enterprise",
            "billing_type": "stripe_subscription_contracted",
            "rate_limit_tier": "default_claude_max_5x"
          }
        }
        """.data(using: .utf8)!

        let profile = try JSONDecoder().decode(ProfileResponse.self, from: json)
        #expect(profile.account.fullName == "John Doe")
        #expect(profile.account.hasClaudePro == true)
        #expect(profile.account.hasClaudeMax == false)
        #expect(profile.organization?.rateLimitTier == "default_claude_max_5x")
    }

    @Test("decodes profile with null organization")
    func decodesNullOrg() throws {
        let json = """
        {
          "account": {
            "uuid": "abc",
            "full_name": "Solo User",
            "display_name": "Solo",
            "email": "solo@example.com",
            "has_claude_max": true,
            "has_claude_pro": false
          },
          "organization": null
        }
        """.data(using: .utf8)!

        let profile = try JSONDecoder().decode(ProfileResponse.self, from: json)
        #expect(profile.organization == nil)
        #expect(PlanType(from: profile.account, organization: nil) == .max)
    }

    @Test("PlanType derives correctly from account flags")
    func planTypeDerivation() {
        let proAccount = AccountInfo(uuid: "", fullName: "", displayName: "", email: "", hasClaudeMax: false, hasClaudePro: true)
        let maxAccount = AccountInfo(uuid: "", fullName: "", displayName: "", email: "", hasClaudeMax: true, hasClaudePro: false)
        let freeAccount = AccountInfo(uuid: "", fullName: "", displayName: "", email: "", hasClaudeMax: false, hasClaudePro: false)

        #expect(PlanType(from: proAccount, organization: nil) == .pro)
        #expect(PlanType(from: maxAccount, organization: nil) == .max)
        #expect(PlanType(from: freeAccount, organization: nil) == .free)
    }

    // MARK: - Team / Enterprise plan derivation

    @Test("team plan derived from organization_type claude_team")
    func teamPlanFromOrgType() {
        let account = AccountInfo(uuid: "", fullName: "", displayName: "", email: "", hasClaudeMax: false, hasClaudePro: false)
        let org = OrganizationInfo(uuid: "", name: "Team Org", organizationType: "claude_team", billingType: "stripe", rateLimitTier: "default_claude_team")

        let plan = PlanType(from: account, organization: org)
        #expect(plan == .team)
    }

    @Test("enterprise plan derived from organization_type claude_enterprise")
    func enterprisePlanFromOrgType() {
        let account = AccountInfo(uuid: "", fullName: "", displayName: "", email: "", hasClaudeMax: false, hasClaudePro: false)
        let org = OrganizationInfo(uuid: "", name: "Enterprise Org", organizationType: "claude_enterprise", billingType: "stripe_subscription_contracted", rateLimitTier: "default_claude_max_5x")

        let plan = PlanType(from: account, organization: org)
        #expect(plan == .enterprise)
    }

    @Test("max account flag takes precedence over organization_type")
    func maxPrecedesOrgType() {
        let account = AccountInfo(uuid: "", fullName: "", displayName: "", email: "", hasClaudeMax: true, hasClaudePro: false)
        let org = OrganizationInfo(uuid: "", name: "Team Org", organizationType: "claude_team", billingType: "stripe", rateLimitTier: "default_claude_team")

        let plan = PlanType(from: account, organization: org)
        #expect(plan == .max)
    }

    @Test("pro account flag takes precedence over organization_type")
    func proPrecedesOrgType() {
        let account = AccountInfo(uuid: "", fullName: "", displayName: "", email: "", hasClaudeMax: false, hasClaudePro: true)
        let org = OrganizationInfo(uuid: "", name: "Enterprise Org", organizationType: "claude_enterprise", billingType: "stripe", rateLimitTier: "default_claude_enterprise")

        let plan = PlanType(from: account, organization: org)
        #expect(plan == .pro)
    }

    // MARK: - displayLabel

    @Test("displayLabel returns correct labels for all plan types")
    func displayLabels() {
        #expect(PlanType.pro.displayLabel == "PRO")
        #expect(PlanType.max.displayLabel == "MAX")
        #expect(PlanType.team.displayLabel == "TEAM")
        #expect(PlanType.enterprise.displayLabel == "ENTERPRISE")
        #expect(PlanType.free.displayLabel == "FREE")
        #expect(PlanType.unknown.displayLabel == "")
    }

    // MARK: - badgeColor

    @Test("badgeColor returns correct colors for all plan types")
    func badgeColors() {
        #expect(PlanType.max.badgeColor == .purple)
        #expect(PlanType.pro.badgeColor == .blue)
        #expect(PlanType.team.badgeColor == .teal)
        #expect(PlanType.enterprise.badgeColor == .orange)
        #expect(PlanType.free.badgeColor == .gray)
        #expect(PlanType.unknown.badgeColor == .clear)
    }

    // MARK: - formattedRateLimitTier

    @Test("formattedRateLimitTier strips prefix and formats correctly")
    func formattedRateLimitTier() {
        #expect("default_claude_max_5x".formattedRateLimitTier == "Max 5x")
        #expect("default_claude_team".formattedRateLimitTier == "Team")
        #expect("default_claude_enterprise".formattedRateLimitTier == "Enterprise")
        #expect("default_claude_pro".formattedRateLimitTier == "Pro")
        #expect("custom_tier".formattedRateLimitTier == "Custom tier")
    }
}
