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

    func invalidateCache()
    func updateAfterSync(usage: CachedUsage, syncDate: Date)
    func updateTheme(_ theme: ThemeColors, thresholds: UsageThresholds)
    func updateSmartColorEnabled(_ enabled: Bool)
    func updateSmartColorProfile(_ profile: SmartColorProfile)
    func clear()
}
