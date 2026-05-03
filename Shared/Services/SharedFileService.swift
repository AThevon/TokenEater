import Foundation

final class SharedFileService: SharedFileServiceProtocol, @unchecked Sendable {
    private static let appGroupID = "group.com.tokeneater"
    private static let legacyDirectoryName = "com.tokeneater.shared"
    private static let oldDirectoryName = "com.claudeusagewidget.shared"
    private static let fileName = "shared.json"

    private var realHomeDirectory: String {
        guard let pw = getpwuid(getuid()) else { return NSHomeDirectory() }
        return String(cString: pw.pointee.pw_dir)
    }

    /// Root directory for shared data. Prefers the App Group container (available
    /// once TokenEater ships with a paid Developer Team and the `group.com.tokeneater`
    /// App Group registered), falls back to the legacy `~/Library/Application Support/
    /// com.tokeneater.shared/` path during development builds and for users still on
    /// pre-v5.0 installs. Both app and widget evaluate this identically, so they
    /// always agree on where the shared file lives.
    private var rootDirectoryURL: URL {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupID
        ) {
            return container
        }
        return URL(fileURLWithPath: realHomeDirectory)
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(Self.legacyDirectoryName)
    }

    private var sharedFileURL: URL {
        rootDirectoryURL.appendingPathComponent(Self.fileName)
    }

    private var legacyHomeRelativeFileURL: URL {
        URL(fileURLWithPath: realHomeDirectory)
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(Self.legacyDirectoryName)
            .appendingPathComponent(Self.fileName)
    }

    private var oldProductFileURL: URL {
        URL(fileURLWithPath: realHomeDirectory)
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(Self.oldDirectoryName)
            .appendingPathComponent(Self.fileName)
    }

    init() {
        migrateFromOldProductName()
        migrateFromHomeRelativeToAppGroup()
    }

    // MARK: - Migrations

    /// v4.x migration: users who installed very early with the `com.claudeusagewidget.*`
    /// bundle IDs still have the old directory. Move its content into the new one.
    private func migrateFromOldProductName() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: oldProductFileURL.path) else { return }

        let legacyDir = legacyHomeRelativeFileURL.deletingLastPathComponent()
        try? fm.createDirectory(at: legacyDir, withIntermediateDirectories: true)

        if !fm.fileExists(atPath: legacyHomeRelativeFileURL.path) {
            try? fm.copyItem(at: oldProductFileURL, to: legacyHomeRelativeFileURL)
        }

        try? fm.removeItem(at: oldProductFileURL.deletingLastPathComponent())
    }

    /// v5.0 migration: once the App Group container becomes available (after the user
    /// upgrades to the signed build), copy any files still sitting in the legacy
    /// home-relative directory into the container so both app and widget agree on the
    /// new location. No-op when containerURL is nil (dev builds on Personal Team) or
    /// when the legacy directory is empty.
    private func migrateFromHomeRelativeToAppGroup() {
        let fm = FileManager.default
        guard let container = fm.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) else {
            return
        }

        let legacyDir = legacyHomeRelativeFileURL.deletingLastPathComponent()
        guard fm.fileExists(atPath: legacyDir.path) else { return }

        let items = (try? fm.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil)) ?? []
        guard !items.isEmpty else {
            try? fm.removeItem(at: legacyDir)
            return
        }

        try? fm.createDirectory(at: container, withIntermediateDirectories: true)
        var allCopiesOK = true
        for item in items {
            let dest = container.appendingPathComponent(item.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) {
                do {
                    try fm.copyItem(at: item, to: dest)
                } catch {
                    allCopiesOK = false
                }
            }
        }
        // Only remove the legacy directory if every file was successfully
        // copied into the container. Removing prematurely would lose user
        // data on permission/disk errors mid-migration.
        if allCopiesOK {
            try? fm.removeItem(at: legacyDir)
        }
    }

    // MARK: - SharedData (same JSON format as SharedContainer for backward compat)

    private struct SharedData: Codable {
        var cachedUsage: CachedUsage?
        var lastSyncDate: Date?
        var theme: ThemeColors?
        var thresholds: UsageThresholds?
        var smartColorEnabled: Bool?
        /// Persisted as the raw rawValue (e.g. "balanced") so older widget
        /// builds that don't know about the profile field still decode the
        /// rest of the JSON cleanly. Decoded back through the enum's
        /// `init?(rawValue:)` so an unknown future value falls back to nil
        /// (and the getter returns `.default`).
        var smartColorProfile: String?
        /// Last 7 days of token totals (oldest first, today last). Powers the
        /// History Sparkline widget without forcing the widget process to
        /// re-parse JSONL files. Updated by MonitoringInsightsStore once a
        /// day after its 7d bucketing computes.
        var lastWeekDailyTotals: [Int]?
        /// Date the lastWeekDailyTotals were last refreshed. Lets the widget
        /// degrade gracefully if data is older than 36h (label "stale").
        var lastWeekTotalsRefreshedAt: Date?
    }

    /// In-memory cache - avoids redundant disk reads within the same process.
    /// Each process (app, widget) has its own SharedFileService instance, so no cross-process staleness.
    private var cachedData: SharedData?

    private func load() -> SharedData {
        if let cached = cachedData { return cached }

        var result = SharedData()
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(readingItemAt: sharedFileURL, options: [], error: &error) { url in
            guard let data = try? Data(contentsOf: url) else { return }
            if let decoded = try? JSONDecoder().decode(SharedData.self, from: data) {
                result = decoded
            }
        }
        cachedData = result
        return result
    }

    private func save(_ shared: SharedData) {
        let dir = sharedFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: sharedFileURL, options: .forReplacing, error: &error) { url in
            try? JSONEncoder().encode(shared).write(to: url, options: .atomic)
        }
        cachedData = shared
    }

    // MARK: - SharedFileServiceProtocol

    var fileURL: URL { sharedFileURL }

    func invalidateCache() {
        cachedData = nil
    }

    var isConfigured: Bool { cachedUsage != nil }

    var cachedUsage: CachedUsage? {
        load().cachedUsage
    }

    var lastSyncDate: Date? {
        load().lastSyncDate
    }

    var theme: ThemeColors {
        load().theme ?? .default
    }

    var thresholds: UsageThresholds {
        load().thresholds ?? .default
    }

    var smartColorEnabled: Bool {
        load().smartColorEnabled ?? true
    }

    var smartColorProfile: SmartColorProfile {
        guard let raw = load().smartColorProfile,
              let profile = SmartColorProfile(rawValue: raw) else {
            return .default
        }
        return profile
    }

    func updateAfterSync(usage: CachedUsage, syncDate: Date) {
        var data = load()
        data.cachedUsage = usage
        data.lastSyncDate = syncDate
        save(data)
    }

    func updateTheme(_ theme: ThemeColors, thresholds: UsageThresholds) {
        var data = load()
        data.theme = theme
        data.thresholds = thresholds
        save(data)
    }

    func updateSmartColorEnabled(_ enabled: Bool) {
        var data = load()
        data.smartColorEnabled = enabled
        save(data)
    }

    func updateSmartColorProfile(_ profile: SmartColorProfile) {
        var data = load()
        data.smartColorProfile = profile.rawValue
        save(data)
    }

    /// Last 7 daily token totals (oldest first). nil until first MonitoringInsightsStore refresh.
    var lastWeekDailyTotals: [Int]? {
        load().lastWeekDailyTotals
    }

    var lastWeekTotalsRefreshedAt: Date? {
        load().lastWeekTotalsRefreshedAt
    }

    func updateLastWeekDailyTotals(_ totals: [Int], refreshedAt: Date = Date()) {
        var data = load()
        data.lastWeekDailyTotals = totals
        data.lastWeekTotalsRefreshedAt = refreshedAt
        save(data)
    }

    func clear() {
        let empty = SharedData()
        save(empty)
    }
}
