import Foundation

// MARK: - API Response

struct UsageResponse: Codable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?
    let sevenDaySonnet: UsageBucket?
    let sevenDayOauthApps: UsageBucket?
    let sevenDayOpus: UsageBucket?
    let sevenDayCowork: UsageBucket?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case sevenDayOpus = "seven_day_opus"
        case sevenDayCowork = "seven_day_cowork"
    }

    init(fiveHour: UsageBucket? = nil, sevenDay: UsageBucket? = nil, sevenDaySonnet: UsageBucket? = nil,
         sevenDayOauthApps: UsageBucket? = nil, sevenDayOpus: UsageBucket? = nil, sevenDayCowork: UsageBucket? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
        self.sevenDayOauthApps = sevenDayOauthApps
        self.sevenDayOpus = sevenDayOpus
        self.sevenDayCowork = sevenDayCowork
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
    }
}

struct UsageBucket: Codable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var resetsAtDate: Date? {
        guard let resetsAt else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: resetsAt) {
            return date
        }
        let withoutFractional = ISO8601DateFormatter()
        withoutFractional.formatOptions = [.withInternetDateTime]
        return withoutFractional.date(from: resetsAt)
    }
}

// MARK: - Cached Usage (for offline support)

struct CachedUsage: Codable {
    let usage: UsageResponse
    let fetchDate: Date
}

// MARK: - Proxy Config (injectable — app uses UserDefaults, widget uses AppIntent)

struct ProxyConfig {
    var enabled: Bool
    var host: String
    var port: Int

    init(enabled: Bool = false, host: String = "127.0.0.1", port: Int = 1080) {
        self.enabled = enabled
        self.host = host
        self.port = port
    }
}

// MARK: - Local Cache (each target writes to its own sandbox Application Support)

enum LocalCache {
    private static let cacheFileName = "claude-usage-cache.json"

    private static var cacheURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent(cacheFileName)
    }

    static func write(_ cache: CachedUsage) {
        try? JSONEncoder().encode(cache).write(to: cacheURL)
    }

    static func read() -> CachedUsage? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(CachedUsage.self, from: data)
    }
}
