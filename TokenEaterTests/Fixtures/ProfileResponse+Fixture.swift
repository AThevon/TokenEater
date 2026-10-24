import Foundation

extension ProfileResponse {
    static func fixture(
        accountUUID: String = "test-uuid",
        orgUUID: String = "org-uuid",
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
                uuid: accountUUID,
                fullName: fullName,
                displayName: displayName,
                email: email,
                hasClaudeMax: hasClaudeMax,
                hasClaudePro: hasClaudePro
            ),
            organization: orgName.map { name in
                OrganizationInfo(
                    uuid: orgUUID,
                    name: name,
                    organizationType: orgType,
                    billingType: "stripe",
                    rateLimitTier: rateLimitTier
                )
            }
        )
    }
}
