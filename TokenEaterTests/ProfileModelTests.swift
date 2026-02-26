import Testing
import Foundation

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
        #expect(PlanType(from: profile.account) == .max)
    }

    @Test("PlanType derives correctly from account flags")
    func planTypeDerivation() {
        let proAccount = AccountInfo(uuid: "", fullName: "", displayName: "", email: "", hasClaudeMax: false, hasClaudePro: true)
        let maxAccount = AccountInfo(uuid: "", fullName: "", displayName: "", email: "", hasClaudeMax: true, hasClaudePro: false)
        let freeAccount = AccountInfo(uuid: "", fullName: "", displayName: "", email: "", hasClaudeMax: false, hasClaudePro: false)

        #expect(PlanType(from: proAccount) == .pro)
        #expect(PlanType(from: maxAccount) == .max)
        #expect(PlanType(from: freeAccount) == .free)
    }
}
