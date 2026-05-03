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

    /// Root directory for shared data. Always uses the home-relative
    /// `~/Library/Application Support/com.tokeneater.shared/` path because :
    ///
    /// 1. The main app is desandboxed (post v5.0 Apple Dev migration), so
    ///    macOS happily returns a Group Container URL even without the
    ///    `application-groups` entitlement (no sandbox = no entitlement check).
    /// 2. The widget IS sandboxed (WidgetKit requirement) and its entitlement
    ///    does NOT declare the App Group (deferred to v5.x once provisioning
    ///    profiles are wired up), so `containerURL` returns nil.
    /// 3. Result : main app would write to the Group Container, widget would
    ///    read from the home-relative path -> they'd diverge silently.
    ///
    /// The home-relative path works for both : main app writes freely
    /// (desandboxed), widget reads via the `temporary-exception.files.
    /// home-relative-path.read-only` entitlement. They agree on the path.
    ///
    /// Will switch back to App Group lookup once we have provisioning profiles
    /// in CI and both entitlements files declare the group.
    private var rootDirectoryURL: URL {
        URL(fileURLWithPath: realHomeDirectory)
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
        migrateFromGroupContainerToHomeRelative()
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

    /// Reverse migration: previous v5.0 builds wrote to the App Group container
    /// (when running desandboxed - macOS hands out a Group Container path even
    /// without the entitlement) but the sandboxed widget couldn't read it.
    /// This pulls any data stranded there back to the home-relative path that
    /// both processes can see, then removes the Group Container directory.
    /// No-op when the container doesn't exist or is empty.
    private func migrateFromGroupContainerToHomeRelative() {
        let fm = FileManager.default
        guard let container = fm.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) else {
            return
        }
        guard fm.fileExists(atPath: container.path) else { return }

        let items = (try? fm.contentsOfDirectory(at: container, includingPropertiesForKeys: nil)) ?? []
        guard !items.isEmpty else {
            try? fm.removeItem(at: container)
            return
        }

        let homeDir = legacyHomeRelativeFileURL.deletingLastPathComponent()
        try? fm.createDirectory(at: homeDir, withIntermediateDirectories: true)
        var allCopiesOK = true
        for item in items {
            let dest = homeDir.appendingPathComponent(item.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) {
                do {
                    try fm.copyItem(at: item, to: dest)
                } catch {
                    allCopiesOK = false
                }
            }
        }
        if allCopiesOK {
            try? fm.removeItem(at: container)
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
