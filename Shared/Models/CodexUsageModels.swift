import Foundation

// MARK: - API Response

/// Decoded `GET https://chatgpt.com/backend-api/wham/usage` payload.
///
/// Identity fields the endpoint also returns (`email`, `user_id`, `account_id`)
/// are deliberately NOT modelled: this type is persisted verbatim to
/// `codex.json` for the sandboxed widget, and the widget has no business
/// knowing who the user is. The account id the app itself needs already comes
/// from `auth.json` via `CodexCredentials`.
///
/// Every field decodes tolerantly, like `UsageResponse`: an unknown or
/// malformed sub-object degrades to nil instead of failing the whole response,
/// because this is an undocumented internal endpoint that can change shape.
struct CodexUsageResponse: Codable, Equatable {
    /// Raw plan string (`plus`, `pro`, `prolite`, `team`, `business`, ...).
    /// Kept verbatim so an unreleased plan still renders as a badge.
    let planType: String?
    /// The account-wide Codex limit. nil for API-key accounts, which have no
    /// rolling windows at all.
    let rateLimit: CodexRateLimit?
    /// Per-model pools (e.g. `limit_name: "GPT-5.3-Codex-Spark"`). Decoded
    /// lossily so one unfamiliar entry never costs us the rest.
    let additionalRateLimits: [CodexAdditionalRateLimit]
    let credits: CodexCredits?
    let spendControl: CodexSpendControl?
    /// Why requests are blocked, when they are (`rate_limit_reached`,
    /// `workspace_owner_credits_depleted`, ...). nil when nothing is blocked.
    let rateLimitReachedType: String?
    /// Banked "reset this window now" credits. Displayed only; TokenEater never
    /// calls the endpoint that spends one.
    let resetCreditsAvailable: Int?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case additionalRateLimits = "additional_rate_limits"
        case credits
        case spendControl = "spend_control"
        case rateLimitReachedType = "rate_limit_reached_type"
        case resetCreditsAvailable
    }

    /// Keys read in `init(from:)` only, kept out of `CodingKeys` so the
    /// synthesized `Encodable` stays property-aligned.
    private enum FallbackKeys: String, CodingKey {
        case rateLimitResetCredits = "rate_limit_reset_credits"
    }

    private enum ResetCreditsKeys: String, CodingKey {
        case availableCount = "available_count"
    }

    init(
        planType: String? = nil,
        rateLimit: CodexRateLimit? = nil,
        additionalRateLimits: [CodexAdditionalRateLimit] = [],
        credits: CodexCredits? = nil,
        spendControl: CodexSpendControl? = nil,
        rateLimitReachedType: String? = nil,
        resetCreditsAvailable: Int? = nil
    ) {
        self.planType = planType
        self.rateLimit = rateLimit
        self.additionalRateLimits = additionalRateLimits
        self.credits = credits
        self.spendControl = spendControl
        self.rateLimitReachedType = rateLimitReachedType
        self.resetCreditsAvailable = resetCreditsAvailable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planType = try? container.decode(String.self, forKey: .planType)
        rateLimit = try? container.decode(CodexRateLimit.self, forKey: .rateLimit)
        additionalRateLimits = container.decodeLossyArray(CodexAdditionalRateLimit.self, forKey: .additionalRateLimits)
        credits = try? container.decode(CodexCredits.self, forKey: .credits)
        spendControl = try? container.decode(CodexSpendControl.self, forKey: .spendControl)

        // The live API sends null, the OpenAPI model declares `{type: "..."}`
        // and the rollout logs a bare string. Accept all three shapes.
        if let raw = try? container.decode(String.self, forKey: .rateLimitReachedType) {
            rateLimitReachedType = raw
        } else if let nested = try? container.nestedContainer(keyedBy: ReachedTypeKeys.self, forKey: .rateLimitReachedType) {
            rateLimitReachedType = try? nested.decode(String.self, forKey: .type)
        } else {
            rateLimitReachedType = nil
        }

        // Read from our own flat key first (re-decoding `codex.json`), then from
        // the API's nested object.
        if let flat = try? container.decode(Int.self, forKey: .resetCreditsAvailable) {
            resetCreditsAvailable = flat
        } else if let fallback = try? decoder.container(keyedBy: FallbackKeys.self),
                  let nested = try? fallback.nestedContainer(keyedBy: ResetCreditsKeys.self, forKey: .rateLimitResetCredits) {
            resetCreditsAvailable = try? nested.decode(Int.self, forKey: .availableCount)
        } else {
            resetCreditsAvailable = nil
        }
    }

    private enum ReachedTypeKeys: String, CodingKey {
        case type
    }

    /// True when the server itself says the account is blocked, which beats any
    /// percentage we could compute.
    var isLimitReached: Bool {
        rateLimit?.limitReached == true || rateLimit?.allowed == false
    }
}

// MARK: - Rate limit

struct CodexRateLimit: Codable, Equatable {
    let allowed: Bool?
    let limitReached: Bool?
    let primaryWindow: CodexRateWindow?
    let secondaryWindow: CodexRateWindow?

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    init(
        allowed: Bool? = nil,
        limitReached: Bool? = nil,
        primaryWindow: CodexRateWindow? = nil,
        secondaryWindow: CodexRateWindow? = nil
    ) {
        self.allowed = allowed
        self.limitReached = limitReached
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allowed = try? container.decode(Bool.self, forKey: .allowed)
        limitReached = try? container.decode(Bool.self, forKey: .limitReached)
        primaryWindow = try? container.decode(CodexRateWindow.self, forKey: .primaryWindow)
        secondaryWindow = try? container.decode(CodexRateWindow.self, forKey: .secondaryWindow)
    }

    /// Both windows in payload order, dropping the ones the plan doesn't have.
    /// Order is NOT semantic: on a weekly-only plan the primary window IS the
    /// weekly one (see `CodexWindowKind`).
    var windows: [CodexRateWindow] {
        [primaryWindow, secondaryWindow].compactMap { $0 }
    }
}

/// One rolling window. `used_percent` arrives as an integer from the API and as
/// a float from the rollout logs, so it is modelled as `Double` throughout.
struct CodexRateWindow: Codable, Equatable {
    let usedPercent: Double
    let limitWindowSeconds: Int
    let resetAfterSeconds: Int?
    /// Unix seconds. Always present in observed payloads.
    let resetAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }

    init(usedPercent: Double, limitWindowSeconds: Int, resetAfterSeconds: Int? = nil, resetAt: Int? = nil) {
        self.usedPercent = usedPercent
        self.limitWindowSeconds = limitWindowSeconds
        self.resetAfterSeconds = resetAfterSeconds
        self.resetAt = resetAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = (try? container.decode(Double.self, forKey: .usedPercent)) ?? 0
        limitWindowSeconds = (try? container.decode(Int.self, forKey: .limitWindowSeconds)) ?? 0
        resetAfterSeconds = try? container.decode(Int.self, forKey: .resetAfterSeconds)
        resetAt = try? container.decode(Int.self, forKey: .resetAt)
    }

    var windowDuration: TimeInterval { TimeInterval(limitWindowSeconds) }

    var resetDate: Date? {
        guard let resetAt, resetAt > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(resetAt))
    }

    var kind: CodexWindowKind { .classify(seconds: limitWindowSeconds) }

    /// Whole-number percentage for the UI.
    var pct: Int { Int(usedPercent.rounded()) }

    /// True when the window has not started: nothing used, and the whole window
    /// still ahead. The backend reports such a window as `reset_at = now +
    /// window` on every poll, so its deadline slides forward continuously.
    /// Surfaces that schedule against a deadline (reset reminders) must skip
    /// these; a reminder for a target that keeps moving would never be right.
    var isIdle: Bool {
        guard usedPercent == 0, limitWindowSeconds > 0, let resetAfterSeconds else { return false }
        return resetAfterSeconds >= limitWindowSeconds - 60
    }
}

// MARK: - Per-model pools

/// One entry of `additional_rate_limits`: a pool scoped to a specific model
/// (e.g. `GPT-5.3-Codex-Spark`) with its own pair of windows.
struct CodexAdditionalRateLimit: Codable, Equatable {
    let limitName: String?
    let meteredFeature: String?
    let rateLimit: CodexRateLimit?
    let normalModelSlug: String?

    enum CodingKeys: String, CodingKey {
        case limitName = "limit_name"
        case meteredFeature = "metered_feature"
        case rateLimit = "rate_limit"
        case normalModelSlug = "normal_model_slug"
    }

    init(limitName: String? = nil, meteredFeature: String? = nil, rateLimit: CodexRateLimit? = nil, normalModelSlug: String? = nil) {
        self.limitName = limitName
        self.meteredFeature = meteredFeature
        self.rateLimit = rateLimit
        self.normalModelSlug = normalModelSlug
    }

    /// Throws when the entry carries no usable rate limit, so `decodeLossyArray`
    /// drops it: an entry with nothing to show is worse than no entry at all,
    /// and would render as an empty row.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limitName = try? container.decode(String.self, forKey: .limitName)
        meteredFeature = try? container.decode(String.self, forKey: .meteredFeature)
        rateLimit = try container.decode(CodexRateLimit.self, forKey: .rateLimit)
        normalModelSlug = try? container.decode(String.self, forKey: .normalModelSlug)
    }

    /// Label for the UI: the model name when the backend gives one, else the
    /// metered-feature slug it is keyed by.
    var displayName: String? { limitName ?? meteredFeature }
}

// MARK: - Credits and spend control

/// Paid credits pool that supplements the plan quota. `balance` is a decimal
/// string on the wire, never a number.
struct CodexCredits: Codable, Equatable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let overageLimitReached: Bool?
    let balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case overageLimitReached = "overage_limit_reached"
        case balance
    }

    init(hasCredits: Bool? = nil, unlimited: Bool? = nil, overageLimitReached: Bool? = nil, balance: String? = nil) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.overageLimitReached = overageLimitReached
        self.balance = balance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = try? container.decode(Bool.self, forKey: .hasCredits)
        unlimited = try? container.decode(Bool.self, forKey: .unlimited)
        overageLimitReached = try? container.decode(Bool.self, forKey: .overageLimitReached)
        balance = try? container.decode(String.self, forKey: .balance)
    }

    /// True when there is a pool worth showing: either a real balance or an
    /// unlimited grant.
    var isPresentable: Bool {
        if unlimited == true { return true }
        guard hasCredits == true else { return false }
        return (numericBalance ?? 0) > 0 || balance != nil
    }

    var numericBalance: Double? {
        guard let balance else { return nil }
        return Double(balance)
    }
}

/// Workspace-level spending cap (Business / Enterprise members).
struct CodexSpendControl: Codable, Equatable {
    let reached: Bool?
    let individualLimit: Double?

    enum CodingKeys: String, CodingKey {
        case reached
        case individualLimit = "individual_limit"
    }

    init(reached: Bool? = nil, individualLimit: Double? = nil) {
        self.reached = reached
        self.individualLimit = individualLimit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reached = try? container.decode(Bool.self, forKey: .reached)
        // The backend sends either a scalar cap or a whole object describing it.
        if let scalar = try? container.decode(Double.self, forKey: .individualLimit) {
            individualLimit = scalar
        } else if let nested = try? container.nestedContainer(keyedBy: IndividualLimitKeys.self, forKey: .individualLimit) {
            individualLimit = try? nested.decode(Double.self, forKey: .limit)
        } else {
            individualLimit = nil
        }
    }

    private enum IndividualLimitKeys: String, CodingKey {
        case limit
    }
}

// MARK: - Cached usage (for the widget and offline support)

struct CachedCodexUsage: Codable, Equatable {
    let usage: CodexUsageResponse
    let fetchDate: Date
}
