import Foundation

final class MockSharedFileService: SharedFileServiceProtocol, @unchecked Sendable {
    var fileURL: URL = URL(fileURLWithPath: "/tmp/mock-shared.json")

    var _cachedUsage: CachedUsage?
    var _lastSyncDate: Date?
    var _theme: ThemeColors = .default
    var _thresholds: UsageThresholds = .default
    var _smartColorEnabled: Bool = true
    var _smartColorProfile: SmartColorProfile = .default
    var _pacingSchedule: PacingSchedule = .rolling
    var _lastWeekDailyTotals: [Int]?
    var _lastWeekTotalsRefreshedAt: Date?
    var _accountsIndex: [AccountIndexEntry]?
    var updateAccountsIndexCallCount = 0
    var updateAfterSyncCallCount = 0
    var updateThemeCallCount = 0
    var updateSmartColorCallCount = 0
    var updateSmartColorProfileCallCount = 0
    var updatePacingScheduleCallCount = 0
    var updateLastWeekDailyTotalsCallCount = 0

    var isConfigured: Bool { _cachedUsage != nil }

    var cachedUsage: CachedUsage? { _cachedUsage }
    var lastSyncDate: Date? { _lastSyncDate }
    var theme: ThemeColors { _theme }
    var thresholds: UsageThresholds { _thresholds }
    var smartColorEnabled: Bool { _smartColorEnabled }
    var smartColorProfile: SmartColorProfile { _smartColorProfile }
    var pacingSchedule: PacingSchedule { _pacingSchedule }
    var lastWeekDailyTotals: [Int]? { _lastWeekDailyTotals }
    var lastWeekTotalsRefreshedAt: Date? { _lastWeekTotalsRefreshedAt }
    var accountsIndex: [AccountIndexEntry]? { _accountsIndex }

    func updateAccountsIndex(_ index: [AccountIndexEntry]) {
        updateAccountsIndexCallCount += 1
        _accountsIndex = index
    }

    var clearAccountsIndexCallCount = 0

    func clearAccountsIndex() {
        clearAccountsIndexCallCount += 1
        _accountsIndex = nil
    }

    func updateAfterSync(usage: CachedUsage, syncDate: Date) {
        updateAfterSyncCallCount += 1
        _cachedUsage = usage
        _lastSyncDate = syncDate
    }

    var clearUsageCallCount = 0

    func clearUsage() {
        clearUsageCallCount += 1
        _cachedUsage = nil
        _lastSyncDate = nil
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

    func updateSmartColorProfile(_ profile: SmartColorProfile) {
        updateSmartColorProfileCallCount += 1
        _smartColorProfile = profile
    }

    func updatePacingSchedule(_ schedule: PacingSchedule) {
        updatePacingScheduleCallCount += 1
        _pacingSchedule = schedule
    }

    func updateLastWeekDailyTotals(_ totals: [Int], refreshedAt: Date) {
        updateLastWeekDailyTotalsCallCount += 1
        _lastWeekDailyTotals = totals
        _lastWeekTotalsRefreshedAt = refreshedAt
    }

    var invalidateCacheCallCount = 0

    func invalidateCache() { invalidateCacheCallCount += 1 }

    func clear() {
        _cachedUsage = nil
        _lastSyncDate = nil
    }
}
