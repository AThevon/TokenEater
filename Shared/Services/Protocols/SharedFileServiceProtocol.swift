import Foundation

protocol SharedFileServiceProtocol: Sendable {
    var fileURL: URL { get }
    var isConfigured: Bool { get }
    var cachedUsage: CachedUsage? { get }
    var lastSyncDate: Date? { get }
    var theme: ThemeColors { get }
    var thresholds: UsageThresholds { get }
    var smartColorEnabled: Bool { get }
    var smartColorProfile: SmartColorProfile { get }
    var pacingSchedule: PacingSchedule { get }
    var lastWeekDailyTotals: [Int]? { get }
    var lastWeekTotalsRefreshedAt: Date? { get }
    /// The tracked Claude accounts as the widget's account picker sees them,
    /// nil until the app first writes them.
    var accountsIndex: [AccountIndexEntry]? { get }

    func invalidateCache()
    func updateAfterSync(usage: CachedUsage, syncDate: Date)
    func updateTheme(_ theme: ThemeColors, thresholds: UsageThresholds)
    func updateSmartColorEnabled(_ enabled: Bool)
    func updateSmartColorProfile(_ profile: SmartColorProfile)
    func updatePacingSchedule(_ schedule: PacingSchedule)
    func updateLastWeekDailyTotals(_ totals: [Int], refreshedAt: Date)
    func updateAccountsIndex(_ index: [AccountIndexEntry])
    func clear()
}
