import Foundation

final class MockSharedFileService: SharedFileServiceProtocol, @unchecked Sendable {
    var fileURL: URL { URL(fileURLWithPath: "/tmp/mock-shared.json") }

    var _cachedUsage: CachedUsage?
    var _lastSyncDate: Date?
    var _theme: ThemeColors = .default
    var _thresholds: UsageThresholds = .default
    var _smartColorEnabled: Bool = true
    var updateAfterSyncCallCount = 0
    var updateThemeCallCount = 0
    var updateSmartColorCallCount = 0

    var isConfigured: Bool { _cachedUsage != nil }

    var cachedUsage: CachedUsage? { _cachedUsage }
    var lastSyncDate: Date? { _lastSyncDate }
    var theme: ThemeColors { _theme }
    var thresholds: UsageThresholds { _thresholds }
    var smartColorEnabled: Bool { _smartColorEnabled }

    func updateAfterSync(usage: CachedUsage, syncDate: Date) {
        updateAfterSyncCallCount += 1
        _cachedUsage = usage
        _lastSyncDate = syncDate
    }

    func updateTheme(_ theme: ThemeColors, thresholds: UsageThresholds) {
        updateThemeCallCount += 1
        _theme = theme
        _thresholds = thresholds
    }

    func updateSmartColorEnabled(_ enabled: Bool) {
        updateSmartColorCallCount += 1
        _smartColorEnabled = enabled
    }

    func invalidateCache() {}

    func clear() {
        _cachedUsage = nil
        _lastSyncDate = nil
    }
}
