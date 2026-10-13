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
    /// New paid-credits pool. Rendered as a dedicated card rather than a ring,
    /// only visible when `isEnabled` is true.
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case sevenDayOpus = "seven_day_opus"
        case sevenDayCowork = "seven_day_cowork"
        case sevenDayFable = "seven_day_fable"
        case extraUsage = "extra_usage"
    }

    /// Keys with no backing stored property, read in `init(from:)` only. Kept
    /// out of `CodingKeys` so the synthesized `Encodable` stays property-aligned.
    private enum FallbackKeys: String, CodingKey {
        /// Array of per-scope limit entries: the session and weekly pools plus
        /// the per-model weekly quotas (`weekly_scoped`) that replaced the
        /// retired `seven_day_*` keys.
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
        extraUsage: ExtraUsage? = nil
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
        self.sevenDayOauthApps = sevenDayOauthApps
        self.sevenDayOpus = sevenDayOpus
        self.sevenDayCowork = sevenDayCowork
        self.sevenDayFable = sevenDayFable
        self.extraUsage = extraUsage
    }

    // Decode tolerantly: unknown keys are ignored, broken buckets become nil
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = try? decoder.container(keyedBy: FallbackKeys.self)

        // The `limits` array mirrors every pool the flat keys carry: `session`
        // is the 5h window, `weekly_all` the global week, and each model quota
        // is a `weekly_scoped` entry tagged with its display name (e.g.
        // "Fable"). Anthropic already nulled `seven_day_sonnet` / `_opus` in
        // favour of it, so it backfills any bucket the flat key left empty.
        // A flat key that carries a utilization always wins, so old-shape
        // accounts (populated keys, no `limits`) decode exactly as before. Decoded
        // lossily: one malformed entry must not take its siblings with it.
        let limits = fallback?.decodeLossyArray(UsageLimit.self, forKey: .limits) ?? []
        func bucket(_ key: CodingKeys, orLimit limit: UsageBucket? = nil) -> UsageBucket? {
            let raw = try? container.decodeIfPresent(RawUsageBucket.self, forKey: key)
            return UsageBucket.resolve(raw, fallback: limit)
        }

        fiveHour = bucket(.fiveHour, orLimit: UsageLimit.unscopedBucket(in: limits, kind: "session"))
        sevenDay = bucket(.sevenDay, orLimit: UsageLimit.unscopedBucket(in: limits, kind: "weekly_all"))
        sevenDaySonnet = bucket(.sevenDaySonnet, orLimit: UsageLimit.weeklyScopedBucket(in: limits, modelNamed: "Sonnet"))
        sevenDayOauthApps = bucket(.sevenDayOauthApps)
        sevenDayOpus = bucket(.sevenDayOpus, orLimit: UsageLimit.weeklyScopedBucket(in: limits, modelNamed: "Opus"))
        sevenDayCowork = bucket(.sevenDayCowork)
        sevenDayFable = bucket(.sevenDayFable, orLimit: UsageLimit.weeklyScopedBucket(in: limits, modelNamed: "Fable"))
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

    fileprivate static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    fileprivate static let iso8601WithoutFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    var resetsAtDate: Date? {
        guard let resetsAt else { return nil }
        return Self.iso8601WithFractional.date(from: resetsAt)
            ?? Self.iso8601WithoutFractional.date(from: resetsAt)
    }

    /// Picks between a flat-key bucket and its `limits` counterpart. A flat key
    /// with a utilization wins whole, `resets_at` included: a null reset there
    /// means no window is open, and borrowing a date from `limits` would invent
    /// a countdown. Only when its utilization is missing does the `limits`
    /// entry take over, keeping the flat reset if the entry has none. A bucket
    /// only exists when some source carries a utilization: a null one is
    /// unknown, not 0%, so the absent-vs-0% distinction survives.
    fileprivate static func resolve(_ raw: RawUsageBucket?, fallback: UsageBucket?) -> UsageBucket? {
        if let raw, let utilization = raw.utilization {
            return UsageBucket(utilization: utilization, resetsAt: raw.resetsAt)
        }
        guard let fallback else { return nil }
        return UsageBucket(utilization: fallback.utilization, resetsAt: fallback.resetsAt ?? raw?.resetsAt)
    }
}

extension UsageBucket {
    // In an extension so the memberwise initializer survives. Same leniency as
    // `RawUsageBucket`, except a missing or null utilization still throws:
    // there is no bucket to build without one.
    init(from decoder: Decoder) throws {
        let raw = try RawUsageBucket(from: decoder)
        guard let utilization = raw.utilization else {
            throw DecodingError.valueNotFound(Double.self, DecodingError.Context(
                codingPath: decoder.codingPath + [CodingKeys.utilization as CodingKey],
                debugDescription: "utilization is null or not a number"
            ))
        }
        self.init(utilization: utilization, resetsAt: raw.resetsAt)
    }
}

/// A usage bucket as the API sends it, read field by field so one odd field
/// never discards the other: a null `utilization` keeps `resets_at`, and a
/// numeric `resets_at` (epoch seconds) is normalized to an ISO 8601 string.
private struct RawUsageBucket: Decodable {
    let utilization: Double?
    let resetsAt: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: UsageBucket.CodingKeys.self)
        utilization = container.lenientDouble(forKey: .utilization)
        resetsAt = container.lenientTimestamp(forKey: .resetsAt)
    }
}

/// One entry in the `usage` response's `limits` array: the session and weekly
/// pools, plus per-model weekly quotas (as `weekly_scoped` entries carrying
/// the model's display name) that replaced the flat `seven_day_*` keys. Every
/// field is optional and read leniently so an unfamiliar entry never breaks
/// the decode.
struct UsageLimit: Codable {
    /// e.g. `session`, `weekly_all`, `weekly_scoped`.
    let kind: String?
    /// e.g. `session`, `weekly`.
    let group: String?
    /// Utilization as a whole-number percentage (the array uses `percent`,
    /// unlike the `seven_day_*` buckets which use `utilization`). Sent as an
    /// integer today; decoded into a Double like the buckets.
    let percent: Double?
    let resetsAt: String?
    /// Nil only when the API sent no scope at all (absent or null), i.e. the
    /// account-wide pool. Any other scope, including a malformed one or one
    /// limited to a surface rather than a model, decodes to a non-nil value so
    /// it can never pass for the account-wide pool.
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

    /// Adapts this entry into a `UsageBucket`, or nil when it carries no
    /// percentage (unknown is not 0%).
    var bucket: UsageBucket? {
        percent.map { UsageBucket(utilization: $0, resetsAt: resetsAt) }
    }

    /// Finds the first entry of `kind` that carries no scope at all (the
    /// account-wide `session` or `weekly_all` pool) and a percentage, and
    /// adapts it into a `UsageBucket`. Backs `five_hour` / `seven_day` when
    /// the flat key is null, missing or has no utilization.
    static func unscopedBucket(in limits: [UsageLimit], kind: String) -> UsageBucket? {
        limits.lazy.filter { $0.kind == kind && $0.scope == nil }.compactMap(\.bucket).first
    }

    /// Finds the `weekly_scoped` entry whose model display name matches `name`
    /// (case-insensitive) and adapts it into a `UsageBucket`, so callers can
    /// treat it identically to a `seven_day_*` bucket. Returns nil when there
    /// is no such entry (an old-shape account, or a model the user has not
    /// touched this week). Exact match keeps it conservative: it only ever adds
    /// a bucket, and never mistakes one model's quota for another's.
    static func weeklyScopedBucket(in limits: [UsageLimit], modelNamed name: String) -> UsageBucket? {
        let needle = name.lowercased()
        return limits.lazy.filter {
            $0.kind == "weekly_scoped" && $0.scope?.model?.displayName?.lowercased() == needle
        }.compactMap(\.bucket).first
    }
}

// Lenient decoders, in extensions so the memberwise initializers survive. A
// field of an unexpected type reads as nil instead of failing its whole entry.
extension UsageLimit {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try? container.decodeIfPresent(String.self, forKey: .kind),
            group: try? container.decodeIfPresent(String.self, forKey: .group),
            percent: container.lenientDouble(forKey: .percent),
            resetsAt: container.lenientTimestamp(forKey: .resetsAt),
            scope: container.lenientScope()
        )
    }
}

private extension KeyedDecodingContainer where Key == UsageLimit.CodingKeys {
    /// Nil when `scope` is absent or null; otherwise the decoded scope, or an
    /// empty one when it is malformed, so it still reads as scoped.
    func lenientScope() -> UsageLimit.Scope? {
        guard contains(.scope), (try? decodeNil(forKey: .scope)) == false else { return nil }
        return (try? decode(UsageLimit.Scope.self, forKey: .scope)) ?? UsageLimit.Scope(model: nil)
    }
}

extension UsageLimit.Scope {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(model: try? container.decodeIfPresent(Model.self, forKey: .model))
    }
}

extension UsageLimit.Scope.Model {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try? container.decodeIfPresent(String.self, forKey: .id),
            displayName: try? container.decodeIfPresent(String.self, forKey: .displayName)
        )
    }
}

private extension KeyedDecodingContainer {
    /// A finite JSON number (an integer lands here too). Null, absent, a
    /// string or anything else -> nil, so a bad value drops one field, never
    /// the entry, and never reaches an `Int(...)` conversion as NaN or inf.
    func lenientDouble(forKey key: Key) -> Double? {
        guard let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite else { return nil }
        return value
    }

    /// An ISO 8601 string as-is, or a Unix timestamp (seconds, or
    /// milliseconds when implausibly large for seconds) normalized to ISO
    /// 8601 so `resetsAtDate` parses it. Null, absent or anything else -> nil.
    func lenientTimestamp(forKey key: Key) -> String? {
        if let text = try? decodeIfPresent(String.self, forKey: key) { return text }
        if let epoch = try? decodeIfPresent(Double.self, forKey: key), epoch.isFinite {
            let seconds = epoch > 100_000_000_000 ? epoch / 1000 : epoch
            return UsageBucket.iso8601WithoutFractional.string(from: Date(timeIntervalSince1970: seconds))
        }
        return nil
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
