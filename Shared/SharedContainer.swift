import Foundation

enum SharedContainer {
    static let suiteName = "group.com.claudeusagewidget.shared"

    private static let tokenKey = "oauthToken"
    private static let cachedUsageKey = "cachedUsage"
    private static let lastSyncDateKey = "lastSyncDate"

    private static let defaults = UserDefaults(suiteName: suiteName)

    // MARK: - OAuth Token

    static var oauthToken: String? {
        get { defaults?.string(forKey: tokenKey) }
        set { defaults?.set(newValue, forKey: tokenKey) }
    }

    // MARK: - Cached Usage

    static var cachedUsage: CachedUsage? {
        get {
            guard let data = defaults?.data(forKey: cachedUsageKey) else { return nil }
            return try? JSONDecoder().decode(CachedUsage.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults?.set(data, forKey: cachedUsageKey)
            } else {
                defaults?.removeObject(forKey: cachedUsageKey)
            }
        }
    }

    // MARK: - Last Sync Date

    static var lastSyncDate: Date? {
        get { defaults?.object(forKey: lastSyncDateKey) as? Date }
        set { defaults?.set(newValue, forKey: lastSyncDateKey) }
    }

    // MARK: - Convenience

    static var isConfigured: Bool {
        oauthToken != nil
    }

    static func clear() {
        defaults?.removeObject(forKey: tokenKey)
        defaults?.removeObject(forKey: cachedUsageKey)
        defaults?.removeObject(forKey: lastSyncDateKey)
    }
}
