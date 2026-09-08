import Foundation

final class MockCodexSharedFileService: CodexSharedFileServiceProtocol, @unchecked Sendable {
    var _cachedUsage: CachedCodexUsage?
    var _lastSyncDate: Date?
    var pacingMargin: Double = 10
    var _isEnabled = false
    var updateAfterSyncCallCount = 0
    var updateEnabledCalls: [Bool] = []
    var clearCallCount = 0

    var fileURL: URL { URL(fileURLWithPath: "/tmp/mock-codex.json") }
    var isConfigured: Bool { _cachedUsage != nil }
    var isEnabled: Bool { _isEnabled }
    var cachedUsage: CachedCodexUsage? { _cachedUsage }
    var lastSyncDate: Date? { _lastSyncDate }

    func invalidateCache() {}

    func updateAfterSync(usage: CachedCodexUsage, syncDate: Date) {
        updateAfterSyncCallCount += 1
        _cachedUsage = usage
        _lastSyncDate = syncDate
    }

    func updatePacingMargin(_ margin: Double) { pacingMargin = margin }

    func updateEnabled(_ enabled: Bool) {
        updateEnabledCalls.append(enabled)
        _isEnabled = enabled
        if !enabled {
            _cachedUsage = nil
            _lastSyncDate = nil
        }
    }

    func clear() {
        clearCallCount += 1
        _cachedUsage = nil
        _lastSyncDate = nil
    }
}
