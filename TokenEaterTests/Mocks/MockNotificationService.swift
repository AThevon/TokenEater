import Foundation
import UserNotifications

final class MockNotificationService: NotificationServiceProtocol {
    var permissionRequested = false
    var lastEvaluation: (
        fiveHour: MetricSnapshot,
        sevenDay: MetricSnapshot,
        sonnet: MetricSnapshot,
        fable: MetricSnapshot,
        sessionPacing: PacingZone?,
        weeklyPacing: PacingZone?,
        extraUsage: ExtraUsage?,
        toggles: NotificationToggles
    )?
    var lastTokenExpiredFire: NotificationToggles?
    var testedProviders: [MetricProvider?] = []
    var lastReminderSchedule: (
        sessionResetsAt: Date?,
        weeklyResetsAt: Date?,
        toggles: NotificationToggles
    )?
    var stubbedAuthStatus: UNAuthorizationStatus = .notDetermined
    var testSent = false
    var vendorHealthChecks: [(status: VendorStatus, toggles: NotificationToggles)] = []

    func setupDelegate() {}
    func requestPermission() { permissionRequested = true }
    func checkAuthorizationStatus() async -> UNAuthorizationStatus { stubbedAuthStatus }
    func sendTest(for provider: MetricProvider?) {
        testSent = true
        testedProviders.append(provider)
    }

    func evaluate(
        fiveHour: MetricSnapshot,
        sevenDay: MetricSnapshot,
        sonnet: MetricSnapshot,
        fable: MetricSnapshot,
        sessionPacing: PacingZone?,
        weeklyPacing: PacingZone?,
        extraUsage: ExtraUsage?,
        toggles: NotificationToggles
    ) {
        lastEvaluation = (fiveHour, sevenDay, sonnet, fable, sessionPacing, weeklyPacing, extraUsage, toggles)
    }

    func notifyTokenExpired(toggles: NotificationToggles) {
        lastTokenExpiredFire = toggles
    }

    func scheduleResetReminders(
        sessionResetsAt: Date?,
        weeklyResetsAt: Date?,
        toggles: NotificationToggles
    ) {
        lastReminderSchedule = (sessionResetsAt, weeklyResetsAt, toggles)
    }

    var codexEvaluations: [(windows: [CodexWindowSnapshot], toggles: NotificationToggles)] = []
    var codexTokenExpiredFires = 0
    var codexRemindersCancelled = 0

    func evaluateCodex(windows: [CodexWindowSnapshot], toggles: NotificationToggles) {
        codexEvaluations.append((windows, toggles))
    }

    func notifyCodexTokenExpired(toggles: NotificationToggles) {
        codexTokenExpiredFires += 1
    }

    func cancelCodexReminders() {
        codexRemindersCancelled += 1
    }

    func checkVendorHealth(_ status: VendorStatus, toggles: NotificationToggles) {
        vendorHealthChecks.append((status, toggles))
    }
}
