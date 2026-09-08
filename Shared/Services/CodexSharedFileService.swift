import Foundation

/// Codex counterpart of `SharedFileService`, writing `codex.json` next to
/// `shared.json` in the directory the widget is already entitled to read.
///
/// A separate file rather than new keys in `shared.json` for three reasons:
/// several stores already read-modify-write that file on their own schedules,
/// so a fourth writer adds clobber risk; older widget builds keep decoding
/// `shared.json` untouched; and a provider can be cleared without disturbing
/// the other one.
final class CodexSharedFileService: CodexSharedFileServiceProtocol, @unchecked Sendable {

    // MARK: - Nested Types

    private struct SharedData: Codable {
        /// Guards future shape changes: a widget reading a version it does not
        /// know about renders "no data" rather than a half-decoded state.
        var schemaVersion: Int?
        var enabled: Bool?
        var pacingMargin: Double?
        var cachedUsage: CachedCodexUsage?
        var lastSyncDate: Date?
    }

    // MARK: - Type Properties

    private static let directoryName = "com.tokeneater.shared"
    private static let fileName = "codex.json"
    private static let currentSchemaVersion = 1

    // MARK: - Private Properties

    private let rootDirectoryURL: URL
    private let lock = NSLock()
    /// Per-process read cache. Each process (app, widget) owns its own service
    /// instance, so there is no cross-process staleness to worry about.
    private var cachedData: SharedData?

    // MARK: - Initializers

    init(rootDirectoryURL: URL? = nil) {
        self.rootDirectoryURL = rootDirectoryURL ?? URL(fileURLWithPath: Self.realHomeDirectory)
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(Self.directoryName)
    }

    /// Sandboxed processes get a container path from `FileManager`, so the real
    /// home comes from the passwd entry - the same rule `SharedFileService` uses.
    private static var realHomeDirectory: String {
        guard let pw = getpwuid(getuid()) else { return NSHomeDirectory() }
        return String(cString: pw.pointee.pw_dir)
    }

    // MARK: - CodexSharedFileServiceProtocol

    var fileURL: URL { rootDirectoryURL.appendingPathComponent(Self.fileName) }

    var isConfigured: Bool { cachedUsage != nil }

    var isEnabled: Bool { load().enabled ?? false }

    var cachedUsage: CachedCodexUsage? {
        let data = load()
        guard (data.schemaVersion ?? Self.currentSchemaVersion) <= Self.currentSchemaVersion else { return nil }
        return data.cachedUsage
    }

    var pacingMargin: Double { load().pacingMargin ?? 10 }

    var lastSyncDate: Date? { load().lastSyncDate }

    func invalidateCache() {
        lock.lock()
        cachedData = nil
        lock.unlock()
    }

    func updateAfterSync(usage: CachedCodexUsage, syncDate: Date) {
        var data = loadFresh()
        data.cachedUsage = usage
        data.lastSyncDate = syncDate
        save(data)
    }

    func updatePacingMargin(_ margin: Double) {
        var data = loadFresh()
        data.pacingMargin = margin
        save(data)
    }

    func updateEnabled(_ enabled: Bool) {
        var data = loadFresh()
        data.enabled = enabled
        if !enabled {
            // Drop the payload with the toggle so a disabled provider cannot
            // leave a stale snapshot on disk for the widget to render.
            data.cachedUsage = nil
            data.lastSyncDate = nil
        }
        save(data)
    }

    func clear() {
        save(SharedData(schemaVersion: Self.currentSchemaVersion, enabled: load().enabled, pacingMargin: pacingMargin))
    }

    // MARK: - Private Methods

    private func load() -> SharedData {
        lock.lock()
        if let cachedData {
            lock.unlock()
            return cachedData
        }
        lock.unlock()

        var result = SharedData()
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(readingItemAt: fileURL, options: [], error: &error) { url in
            guard let data = try? Data(contentsOf: url) else { return }
            if let decoded = try? JSONDecoder().decode(SharedData.self, from: data) {
                result = decoded
            }
        }

        lock.lock()
        cachedData = result
        lock.unlock()
        return result
    }

    private func loadFresh() -> SharedData {
        invalidateCache()
        return load()
    }

    private func save(_ shared: SharedData) {
        var payload = shared
        payload.schemaVersion = Self.currentSchemaVersion

        try? FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)

        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &error) { url in
            try? JSONEncoder().encode(payload).write(to: url, options: .atomic)
        }

        lock.lock()
        cachedData = payload
        lock.unlock()
    }
}
