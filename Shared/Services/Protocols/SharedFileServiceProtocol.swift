import Foundation

protocol SharedFileServiceProtocol: Sendable {
    var isConfigured: Bool { get }
    var oauthToken: String? { get nonmutating set }
    var cachedUsage: CachedUsage? { get }
    var lastSyncDate: Date? { get }
    var theme: ThemeColors { get }
    var thresholds: UsageThresholds { get }

    func updateAfterSync(usage: CachedUsage, syncDate: Date)
    func updateTheme(_ theme: ThemeColors, thresholds: UsageThresholds)
    func clear()
}
