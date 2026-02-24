import Foundation

final class SharedFileService: SharedFileServiceProtocol, @unchecked Sendable {
    private let newDirectoryName = "com.tokeneater.shared"
    private let oldDirectoryName = "com.claudeusagewidget.shared"
    private let fileName = "shared.json"

    private var realHomeDirectory: String {
        guard let pw = getpwuid(getuid()) else { return NSHomeDirectory() }
        return String(cString: pw.pointee.pw_dir)
    }

    private var sharedFileURL: URL {
        URL(fileURLWithPath: realHomeDirectory)
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(newDirectoryName)
            .appendingPathComponent(fileName)
    }

    private var oldSharedFileURL: URL {
        URL(fileURLWithPath: realHomeDirectory)
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(oldDirectoryName)
            .appendingPathComponent(fileName)
    }

    init() {
        migrateIfNeeded()
    }

    /// One-shot migration: copy data from old path to new path, then delete old directory.
    /// Kept forever — costs nothing, protects late updaters on Homebrew.
    private func migrateIfNeeded() {
        let fm = FileManager.default
        let oldDir = oldSharedFileURL.deletingLastPathComponent()
        let newDir = sharedFileURL.deletingLastPathComponent()

        guard fm.fileExists(atPath: oldSharedFileURL.path) else { return }

        // Ensure new directory exists
        try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)

        // Copy old file to new location (don't overwrite if new already exists)
        if !fm.fileExists(atPath: sharedFileURL.path) {
            try? fm.copyItem(at: oldSharedFileURL, to: sharedFileURL)
        }

        // Remove old directory
        try? fm.removeItem(at: oldDir)
    }

    // MARK: - SharedData (same JSON format as SharedContainer for backward compat)

    private struct SharedData: Codable {
        var oauthToken: String?
        var cachedUsage: CachedUsage?
        var lastSyncDate: Date?
        var theme: ThemeColors?
        var thresholds: UsageThresholds?
    }

    private func load() -> SharedData {
        guard let data = try? Data(contentsOf: sharedFileURL) else {
            return SharedData()
        }
        return (try? JSONDecoder().decode(SharedData.self, from: data)) ?? SharedData()
    }

    private func save(_ shared: SharedData) {
        let dir = sharedFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(shared).write(to: sharedFileURL, options: .atomic)
    }

    // MARK: - SharedFileServiceProtocol

    var isConfigured: Bool { oauthToken != nil }

    var oauthToken: String? {
        get { load().oauthToken }
        set {
            var data = load()
            data.oauthToken = newValue
            save(data)
        }
    }

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

    func clear() {
        save(SharedData())
    }
}
