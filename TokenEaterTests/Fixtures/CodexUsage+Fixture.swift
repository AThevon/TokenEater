import Foundation

/// Redacted captures of the two payload shapes the endpoint actually returns,
/// recorded on 2026-09-08: a `prolite` account (weekly-only) and a `plus`-style
/// account (5h + weekly). See docs/codex-support/RESEARCH.md.
enum CodexFixtures {

    /// Weekly-only plan: the *primary* window is the 7-day one and there is no
    /// secondary. The shape that breaks any code assuming primary means session.
    static let proliteJSON = """
    {
      "user_id": "user-redacted",
      "account_id": "00000000-0000-0000-0000-000000000000",
      "email": "redacted@example.com",
      "plan_type": "prolite",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 18,
          "limit_window_seconds": 604800,
          "reset_after_seconds": 586117,
          "reset_at": 1789457646
        },
        "secondary_window": null
      },
      "code_review_rate_limit": null,
      "additional_rate_limits": [
        {
          "limit_name": "GPT-5.3-Codex-Spark",
          "metered_feature": "codex_bengalfox",
          "rate_limit": {
            "allowed": true,
            "limit_reached": false,
            "primary_window": {
              "used_percent": 0,
              "limit_window_seconds": 18000,
              "reset_after_seconds": 18000,
              "reset_at": 1788889530
            },
            "secondary_window": {
              "used_percent": 0,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 604800,
              "reset_at": 1789476330
            }
          },
          "normal_model_slug": null
        }
      ],
      "model_usage": { "gpt-6-astra": { "available": true, "available_at": null, "credits_would_enable": false } },
      "credits": {
        "has_credits": false,
        "unlimited": false,
        "overage_limit_reached": false,
        "balance": "0",
        "approx_local_messages": [0, 0],
        "approx_cloud_messages": [0, 0]
      },
      "spend_control": { "reached": false, "individual_limit": null },
      "rate_limit_reached_type": null,
      "promo": null,
      "rate_limit_reset_credits": { "available_count": 1, "applicable_available_count": 0 }
    }
    """

    /// Session + weekly plan, the `plus` / `pro` shape.
    static let plusJSON = """
    {
      "plan_type": "plus",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 42,
          "limit_window_seconds": 18000,
          "reset_after_seconds": 7200,
          "reset_at": 1789000000
        },
        "secondary_window": {
          "used_percent": 63,
          "limit_window_seconds": 604800,
          "reset_after_seconds": 200000,
          "reset_at": 1789200000
        }
      },
      "additional_rate_limits": [],
      "credits": { "has_credits": true, "unlimited": false, "overage_limit_reached": false, "balance": "12.50" },
      "spend_control": { "reached": false, "individual_limit": null },
      "rate_limit_reached_type": null
    }
    """

    /// API-key account: no `rate_limit` object at all.
    static let apiKeyJSON = """
    { "plan_type": null, "rate_limit": null, "additional_rate_limits": [] }
    """

    /// Blocked account, with the reached-type sent as the nested object shape
    /// the OpenAPI model declares.
    static let limitReachedJSON = """
    {
      "plan_type": "pro",
      "rate_limit": {
        "allowed": false,
        "limit_reached": true,
        "primary_window": { "used_percent": 100, "limit_window_seconds": 18000, "reset_after_seconds": 900, "reset_at": 1789000900 },
        "secondary_window": null
      },
      "additional_rate_limits": [
        { "limit_name": "Broken", "rate_limit": "not-an-object" }
      ],
      "rate_limit_reached_type": { "type": "rate_limit_reached" }
    }
    """

    /// Enterprise member with a monthly credit cap. `individual_limit` follows
    /// the upstream model (openai/codex `SpendControlLimitDetails`, sample from
    /// PR #24812): amounts are decimal strings, percentages and times integers.
    static let enterpriseSpendControlJSON = """
    {
      "plan_type": "enterprise",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": { "used_percent": 9, "limit_window_seconds": 18000, "reset_after_seconds": 12000, "reset_at": 1789000000 },
        "secondary_window": null
      },
      "additional_rate_limits": null,
      "credits": null,
      "spend_control": {
        "reached": false,
        "individual_limit": {
          "source": "workspace_default",
          "limit": "25000",
          "used": "8000",
          "remaining": "17000",
          "used_percent": 32,
          "remaining_percent": 68,
          "reset_after_seconds": 86400,
          "reset_at": 1778137680
        }
      },
      "rate_limit_reached_type": null
    }
    """

    /// `promax`, the plan upstream added on 2026-09-25, with the 5h + weekly
    /// pair the other Pro tiers report.
    static let promaxJSON = """
    {
      "plan_type": "promax",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": { "used_percent": 4, "limit_window_seconds": 18000, "reset_after_seconds": 15000, "reset_at": 1789000000 },
        "secondary_window": { "used_percent": 11, "limit_window_seconds": 604800, "reset_after_seconds": 400000, "reset_at": 1789400000 }
      },
      "additional_rate_limits": [],
      "spend_control": { "reached": false, "individual_limit": null },
      "rate_limit_reached_type": null
    }
    """

    static func decode(_ json: String) -> CodexUsageResponse {
        try! JSONDecoder().decode(CodexUsageResponse.self, from: Data(json.utf8))
    }

    // MARK: - Builders

    static func window(
        usedPercent: Double,
        windowSeconds: Int,
        resetAfterSeconds: Int? = nil,
        resetAt: Date
    ) -> CodexRateWindow {
        CodexRateWindow(
            usedPercent: usedPercent,
            limitWindowSeconds: windowSeconds,
            resetAfterSeconds: resetAfterSeconds,
            resetAt: Int(resetAt.timeIntervalSince1970)
        )
    }

    static func usage(
        plan: String? = "pro",
        primary: CodexRateWindow?,
        secondary: CodexRateWindow? = nil,
        limitReached: Bool = false,
        credits: CodexCredits? = nil
    ) -> CodexUsageResponse {
        CodexUsageResponse(
            planType: plan,
            rateLimit: CodexRateLimit(
                allowed: !limitReached,
                limitReached: limitReached,
                primaryWindow: primary,
                secondaryWindow: secondary
            ),
            credits: credits
        )
    }

    /// Unsigned JWT carrying the claims Codex tokens hold. Only the payload
    /// matters: nothing in the app verifies the signature.
    static func jwt(planType: String? = "pro", accountId: String? = "acct-1", exp: Date? = nil, iat: Date? = nil) -> String {
        var auth: [String: Any] = [:]
        if let planType { auth["chatgpt_plan_type"] = planType }
        if let accountId { auth["chatgpt_account_id"] = accountId }
        var payload: [String: Any] = ["https://api.openai.com/auth": auth]
        if let exp { payload["exp"] = exp.timeIntervalSince1970 }
        if let iat { payload["iat"] = iat.timeIntervalSince1970 }
        let body = try! JSONSerialization.data(withJSONObject: payload)
        return "\(base64URL(Data("{\"alg\":\"none\"}".utf8))).\(base64URL(body)).signature"
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func credentials(
        accessToken: String? = nil,
        accountId: String? = "acct-1",
        authMode: String? = "chatgpt",
        expiresAt: Date? = nil,
        planType: String? = "pro"
    ) -> CodexCredentials {
        CodexCredentials(
            accessToken: accessToken ?? jwt(planType: planType, accountId: accountId, exp: expiresAt),
            accountId: accountId,
            authMode: authMode,
            lastRefresh: nil,
            expiresAt: expiresAt,
            planType: planType
        )
    }
}
