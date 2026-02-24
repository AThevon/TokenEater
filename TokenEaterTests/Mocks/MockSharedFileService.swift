import Foundation

final class MockSharedFileService: SharedFileServiceProtocol, @unchecked Sendable {
    var _oauthToken: String?
    var _cachedUsage: CachedUsage?
    var _lastSyncDate: Date?
    var _theme: ThemeColors = .default
    var _thresholds: UsageThresholds = .default
    var updateAfterSyncCallCount = 0
    var updateThemeCallCount = 0

    var isConfigured: Bool { _oauthToken != nil }

    var oauthToken: String? {
        get { _oauthToken }
        set { _oauthToken = newValue }
    }

    var cachedUsage: CachedUsage? { _cachedUsage }
    var lastSyncDate: Date? { _lastSyncDate }
    var theme: ThemeColors { _theme }
    var thresholds: UsageThresholds { _thresholds }

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

    func clear() {
        _oauthToken = nil
        _cachedUsage = nil
        _lastSyncDate = nil
    }
}
