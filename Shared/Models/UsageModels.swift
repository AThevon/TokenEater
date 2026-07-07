import Foundation

// MARK: - API Response

struct UsageResponse: Codable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?
    let sevenDaySonnet: UsageBucket?
    let sevenDayOauthApps: UsageBucket?
    let sevenDayOpus: UsageBucket?
    let sevenDayCowork: UsageBucket?
    /// Claude Fable weekly limit. Two shapes exist in the wild: some accounts
    /// still get a dedicated `seven_day_fable` bucket, but migrated accounts
    /// instead carry it inside the `limits` array as a `weekly_scoped` entry
    /// tagged `scope.model.display_name == "Fable"`. `init(from:)` reads the
    /// dedicated key first and falls back to the array. Shown as a "Fable" tile.
    let sevenDayFable: UsageBucket?
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
        case sevenDayFable = "seven_day_fable"
        case sevenDayDesign = "seven_day_omelette"
        case extraUsage = "extra_usage"
    }

    /// Keys with no backing stored property, read in `init(from:)` only. Kept
    /// out of `CodingKeys` so the synthesized `Encodable` stays property-aligned.
    private enum FallbackKeys: String, CodingKey {
        /// Post-rollout home of the Claude Design quota (was `seven_day_omelette`).
        case sevenDayDesignPromo = "omelette_promotional"
        /// Array of per-scope limit entries. The new home of per-model weekly
        /// quotas (`weekly_scoped`) as Anthropic retires the `seven_day_*` keys.
        case limits
    }

    init(
        fiveHour: UsageBucket? = nil,
        sevenDay: UsageBucket? = nil,
        sevenDaySonnet: UsageBucket? = nil,
        sevenDayOauthApps: UsageBucket? = nil,
        sevenDayOpus: UsageBucket? = nil,
        sevenDayCowork: UsageBucket? = nil,
        sevenDayFable: UsageBucket? = nil,
        sevenDayDesign: UsageBucket? = nil,
        extraUsage: ExtraUsage? = nil
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
        self.sevenDayOauthApps = sevenDayOauthApps
        self.sevenDayOpus = sevenDayOpus
        self.sevenDayCowork = sevenDayCowork
        self.sevenDayFable = sevenDayFable
        self.sevenDayDesign = sevenDayDesign
        self.extraUsage = extraUsage
    }

    // Decode tolerantly: unknown keys are ignored, broken buckets become nil
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = try? decoder.container(keyedBy: FallbackKeys.self)

        // Per-model weekly quotas are migrating out of the flat `seven_day_*`
        // keys into the `limits` array, where each model appears as a
        // `weekly_scoped` entry tagged with its display name (e.g. "Fable"). On
        // migrated accounts the old keys return null, so we read `limits` and
        // use it to backfill any per-model bucket the top-level key left empty.
        // The top-level value always wins, so old-shape accounts (populated
        // `seven_day_*`, no `limits`) keep decoding exactly as before.
        let limits = fallback.flatMap { try? $0.decode([UsageLimit].self, forKey: .limits) } ?? []
        func scoped(_ modelName: String) -> UsageBucket? {
            UsageLimit.weeklyScopedBucket(in: limits, modelNamed: modelName)
        }

        fiveHour = try? container.decode(UsageBucket.self, forKey: .fiveHour)
        sevenDay = try? container.decode(UsageBucket.self, forKey: .sevenDay)
        sevenDaySonnet = (try? container.decode(UsageBucket.self, forKey: .sevenDaySonnet)) ?? scoped("Sonnet")
        sevenDayOauthApps = try? container.decode(UsageBucket.self, forKey: .sevenDayOauthApps)
        sevenDayOpus = (try? container.decode(UsageBucket.self, forKey: .sevenDayOpus)) ?? scoped("Opus")
        sevenDayCowork = try? container.decode(UsageBucket.self, forKey: .sevenDayCowork)
        sevenDayFable = (try? container.decode(UsageBucket.self, forKey: .sevenDayFable)) ?? scoped("Fable")
        // Prefer the legacy key, then the promotional key Anthropic migrated the
        // quota to, then the `limits` array. Any of them may be null/absent.
        let designLegacy = try? container.decode(UsageBucket.self, forKey: .sevenDayDesign)
        let designPromo = fallback.flatMap { try? $0.decode(UsageBucket.self, forKey: .sevenDayDesignPromo) }
        sevenDayDesign = designLegacy ?? designPromo ?? scoped("Design")
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

/// One entry in the `usage` response's `limits` array. Anthropic is moving
/// per-model weekly quotas here (as `weekly_scoped` entries carrying the
/// model's display name) from the flat `seven_day_*` keys. Every field is
/// optional so an unfamiliar entry never breaks the whole decode.
struct UsageLimit: Codable {
    /// e.g. `session`, `weekly_all`, `weekly_scoped`.
    let kind: String?
    /// e.g. `session`, `weekly`.
    let group: String?
    /// Utilization as a whole-number percentage (the array uses `percent`,
    /// unlike the `seven_day_*` buckets which use `utilization`).
    let percent: Double?
    let resetsAt: String?
    let scope: Scope?

    enum CodingKeys: String, CodingKey {
        case kind, group, percent
        case resetsAt = "resets_at"
        case scope
    }

    struct Scope: Codable {
        let model: Model?

        struct Model: Codable {
            let id: String?
            let displayName: String?

            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
            }
        }
    }

    /// Finds the `weekly_scoped` entry whose model display name matches `name`
    /// (case-insensitive) and adapts it into a `UsageBucket`, so callers can
    /// treat it identically to a `seven_day_*` bucket. Returns nil when there
    /// is no such entry — an old-shape account, or a model the user has not
    /// touched this week. Exact match keeps it conservative: it only ever adds
    /// a bucket, and never mistakes one model's quota for another's.
    static func weeklyScopedBucket(in limits: [UsageLimit], modelNamed name: String) -> UsageBucket? {
        let needle = name.lowercased()
        guard let match = limits.first(where: {
            $0.kind == "weekly_scoped" && $0.scope?.model?.displayName?.lowercased() == needle
        }) else { return nil }
        return UsageBucket(utilization: match.percent ?? 0, resetsAt: match.resetsAt)
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

    /// Utilization as a whole-number percentage. Prefers the API-provided
    /// `utilization`; falls back to `used / limit` when it is omitted but both
    /// amounts are present. 0 when there is no limit to divide by. Shared by
    /// the menu bar, the dashboard and the widgets so they never disagree.
    var percent: Int {
        if let util = utilization { return Int(util) }
        let used = usedCredits ?? 0
        let limit = monthlyLimit ?? 0
        return limit > 0 ? Int((used / limit) * 100) : 0
    }
}

// MARK: - Cached Usage (for offline support)

struct CachedUsage: Codable {
    let usage: UsageResponse
    let fetchDate: Date
}
