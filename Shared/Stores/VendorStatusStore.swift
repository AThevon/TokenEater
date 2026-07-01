import SwiftUI

/// Owns vendor outage state and an independent, self-accelerating poll loop.
/// Deliberately separate from `UsageStore` so an outage that breaks the usage
/// API can still be detected and notified.
@MainActor
final class VendorStatusStore: ObservableObject {
    @Published private(set) var statuses: [Vendor: VendorStatus] = [:]
    /// When the next poll is scheduled. Drives the menu-bar countdown.
    @Published private(set) var nextPollDate: Date?

    /// Healthy-state cadence in seconds (mirrors the user's poll-interval
    /// setting). Set by `StatusBarController`.
    var healthyPollInterval: TimeInterval = 300

    /// Live notification-toggle bundle provider, wired by `StatusBarController`
    /// once `SettingsStore` is available — same pattern as `UsageStore`.
    var notifTogglesProvider: (() -> NotificationToggles?)?

    /// Outage cadence: poll fast while degraded so recovery is caught quickly
    /// and the countdown stays meaningful.
    static let outagePollInterval: TimeInterval = 60

    private let statusService: StatusServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let monitoredVendors: [Vendor]
    private var pollTask: Task<Void, Never>?

    init(
        statusService: StatusServiceProtocol = StatusService(),
        notificationService: NotificationServiceProtocol = NotificationService(),
        monitoredVendors: [Vendor] = [.claude]
    ) {
        self.statusService = statusService
        self.notificationService = notificationService
        self.monitoredVendors = monitoredVendors
    }

    // MARK: - Derived state

    var worstHealth: VendorHealth { statuses.values.map(\.health).max() ?? .healthy }
    var isDegraded: Bool { worstHealth != .healthy }
    var claudeStatus: VendorStatus? { statuses[.claude] }

    static func pollInterval(forHealth health: VendorHealth, healthyInterval: TimeInterval) -> TimeInterval {
        health == .healthy ? healthyInterval : outagePollInterval
    }

    // MARK: - Lifecycle

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollOnce()
                let interval = Self.pollInterval(forHealth: self.worstHealth, healthyInterval: self.healthyPollInterval)
                self.nextPollDate = Date().addingTimeInterval(interval)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        nextPollDate = nil
        statuses = [:]
    }

    // MARK: - Poll

    func pollOnce() async {
        for vendor in monitoredVendors {
            do {
                let status = try await statusService.fetchStatus(for: vendor)
                statuses[vendor] = status
                if let toggles = notifTogglesProvider?() {
                    notificationService.checkVendorHealth(status, toggles: toggles)
                }
            } catch {
                // Our own connectivity failure: keep last-known health, mark
                // stale, never invent an outage and never notify.
                if var existing = statuses[vendor] {
                    existing.isStale = true
                    statuses[vendor] = existing
                }
            }
        }
    }
}
