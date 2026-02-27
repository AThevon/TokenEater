import Foundation

extension ProfileResponse {
    static func fixture(
        fullName: String = "Test User",
        displayName: String = "Test",
        email: String = "test@example.com",
        hasClaudeMax: Bool = false,
        hasClaudePro: Bool = true,
        orgName: String? = "Test Org",
        orgType: String = "personal",
        rateLimitTier: String = "default_claude_pro"
    ) -> ProfileResponse {
        ProfileResponse(
            account: AccountInfo(
                uuid: "test-uuid",
                fullName: fullName,
                displayName: displayName,
                email: email,
                hasClaudeMax: hasClaudeMax,
                hasClaudePro: hasClaudePro
            ),
            organization: orgName.map { name in
                OrganizationInfo(
                    uuid: "org-uuid",
                    name: name,
                    organizationType: orgType,
                    billingType: "stripe",
                    rateLimitTier: rateLimitTier
                )
            }
        )
    }
}
