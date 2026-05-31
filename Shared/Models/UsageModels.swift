import Foundation

// MARK: - API Response

struct UsageResponse: Codable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?
    let sevenDaySonnet: UsageBucket?
    let sevenDayOauthApps: UsageBucket?
    let sevenDayOpus: UsageBucket?
    let sevenDayCowork: UsageBucket?
    /// Claude Design. Anthropic codenamed it `seven_day_omelette` during the
    /// initial rollout, then moved the quota under `omelette_promotional` (the
    /// legacy key now returns null on migrated accounts). We read both and keep
    /// whichever is populated so the Design card survives the rename. Exposed as
    /// `sevenDayDesign` internally and labelled "Design" in the UI.
    let sevenDayDesign: UsageBucket?
    /// New paid-credits pool that surfaced alongside Design. Rendered as a
    /// dedicated card rather than a ring, only visible when `isEnabled` is true.
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case sevenDayOpus = "seven_day_opus"
        case sevenDayCowork = "seven_day_cowork"
        case sevenDayDesign = "seven_day_omelette"
        case extraUsage = "extra_usage"
    }

    /// Keys with no backing stored property, read in `init(from:)` only. Kept
    /// out of `CodingKeys` so the synthesized `Encodable` stays property-aligned.
    private enum FallbackKeys: String, CodingKey {
        /// Post-rollout home of the Claude Design quota (was `seven_day_omelette`).
        case sevenDayDesignPromo = "omelette_promotional"
    }

    init(
        fiveHour: UsageBucket? = nil,
        sevenDay: UsageBucket? = nil,
        sevenDaySonnet: UsageBucket? = nil,
        sevenDayOauthApps: UsageBucket? = nil,
        sevenDayOpus: UsageBucket? = nil,
        sevenDayCowork: UsageBucket? = nil,
        sevenDayDesign: UsageBucket? = nil,
        extraUsage: ExtraUsage? = nil
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
        self.sevenDayOauthApps = sevenDayOauthApps
        self.sevenDayOpus = sevenDayOpus
        self.sevenDayCowork = sevenDayCowork
        self.sevenDayDesign = sevenDayDesign
        self.extraUsage = extraUsage
    }

    // Decode tolerantly: unknown keys are ignored, broken buckets become nil
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try? container.decode(UsageBucket.self, forKey: .fiveHour)
        sevenDay = try? container.decode(UsageBucket.self, forKey: .sevenDay)
        sevenDaySonnet = try? container.decode(UsageBucket.self, forKey: .sevenDaySonnet)
        sevenDayOauthApps = try? container.decode(UsageBucket.self, forKey: .sevenDayOauthApps)
        sevenDayOpus = try? container.decode(UsageBucket.self, forKey: .sevenDayOpus)
        sevenDayCowork = try? container.decode(UsageBucket.self, forKey: .sevenDayCowork)
        // Prefer the legacy key, fall back to the promotional one Anthropic
        // migrated the quota to. Either may be null/absent on a given account.
        let designLegacy = try? container.decode(UsageBucket.self, forKey: .sevenDayDesign)
        let fallback = try? decoder.container(keyedBy: FallbackKeys.self)
        let designPromo = fallback.flatMap { try? $0.decode(UsageBucket.self, forKey: .sevenDayDesignPromo) }
        sevenDayDesign = designLegacy ?? designPromo
        extraUsage = try? container.decode(ExtraUsage.self, forKey: .extraUsage)
    }
}

struct UsageBucket: Codable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601WithoutFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    var resetsAtDate: Date? {
        guard let resetsAt else { return nil }
        return Self.iso8601WithFractional.date(from: resetsAt)
            ?? Self.iso8601WithoutFractional.date(from: resetsAt)
    }
}

/// Paid-credits pool that supplements the free quota once the user enables it.
/// All numeric fields are optional because the API leaves them null until the
/// pool is configured.
struct ExtraUsage: Codable, Equatable {
    let isEnabled: Bool
    let monthlyLimit: Double?
    let usedCredits: Double?
    /// 0...100 percentage of used credits vs monthly limit. May be null if the
    /// pool is disabled or the limit is not set.
    let utilization: Double?
    /// ISO 4217 code (e.g. "USD") for formatting monetary values.
    let currency: String?
    /// Why the extra-usage lane is off when `isEnabled` is false. Known values:
    /// `org_level_disabled`, `org_level_disabled_until` (spending cap reached),
    /// `member_level_disabled`, `overage_not_provisioned`. Null when enabled or
    /// when the API omits it.
    let disabledReason: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
        case currency
        case disabledReason = "disabled_reason"
    }
}

// MARK: - Cached Usage (for offline support)

struct CachedUsage: Codable {
    let usage: UsageResponse
    let fetchDate: Date
}
