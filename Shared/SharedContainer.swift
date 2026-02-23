import Foundation

enum SharedContainer {
    private static let directoryName = "com.claudeusagewidget.shared"
    private static let fileName = "shared.json"

    /// Real home directory (bypasses sandbox container redirection)
    private static var realHomeDirectory: String {
        guard let pw = getpwuid(getuid()) else { return NSHomeDirectory() }
        return String(cString: pw.pointee.pw_dir)
    }

    private static var sharedFileURL: URL {
        URL(fileURLWithPath: realHomeDirectory)
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(directoryName)
            .appendingPathComponent(fileName)
    }

    // MARK: - File-backed Storage

    private struct SharedData: Codable {
        var oauthToken: String?
        var cachedUsage: CachedUsage?
        var lastSyncDate: Date?
    }

    private static func load() -> SharedData {
        guard let data = try? Data(contentsOf: sharedFileURL) else {
            return SharedData()
        }
        return (try? JSONDecoder().decode(SharedData.self, from: data)) ?? SharedData()
    }

    private static func save(_ shared: SharedData) {
        let dir = sharedFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(shared).write(to: sharedFileURL, options: .atomic)
    }

    // MARK: - OAuth Token

    static var oauthToken: String? {
        get { load().oauthToken }
        set {
            var data = load()
            data.oauthToken = newValue
            save(data)
        }
    }

    // MARK: - Cached Usage

    static var cachedUsage: CachedUsage? {
        get { load().cachedUsage }
        set {
            var data = load()
            data.cachedUsage = newValue
            save(data)
        }
    }

    // MARK: - Last Sync Date

    static var lastSyncDate: Date? {
        get { load().lastSyncDate }
        set {
            var data = load()
            data.lastSyncDate = newValue
            save(data)
        }
    }

    // MARK: - Atomic Updates

    static func updateAfterSync(usage: CachedUsage, syncDate: Date) {
        var data = load()
        data.cachedUsage = usage
        data.lastSyncDate = syncDate
        save(data)
    }

    // MARK: - Convenience

    static var isConfigured: Bool {
        oauthToken != nil
    }

    static func clear() {
        save(SharedData())
    }
}
