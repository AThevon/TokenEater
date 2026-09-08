import Foundation

protocol CodexSharedFileServiceProtocol: Sendable {
    var fileURL: URL { get }
    /// True when there is usage data to render.
    var isConfigured: Bool { get }
    /// Whether the user has Codex tracking turned on. Mirrored here so the
    /// widget can say "turned off" instead of "no data".
    var isEnabled: Bool { get }
    var cachedUsage: CachedCodexUsage? { get }
    var pacingMargin: Double { get }
    var lastSyncDate: Date? { get }

    func invalidateCache()
    func updateAfterSync(usage: CachedCodexUsage, syncDate: Date)
    func updatePacingMargin(_ margin: Double)
    func updateEnabled(_ enabled: Bool)
    func clear()
}
