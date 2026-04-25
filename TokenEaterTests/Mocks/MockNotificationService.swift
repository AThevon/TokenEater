import Foundation
import UserNotifications

final class MockNotificationService: NotificationServiceProtocol {
    var permissionRequested = false
    var lastEvaluation: (
        fiveHour: MetricSnapshot,
        sevenDay: MetricSnapshot,
        sonnet: MetricSnapshot,
        design: MetricSnapshot,
        sessionPacing: PacingZone?,
        weeklyPacing: PacingZone?,
        extraUsage: ExtraUsage?,
        toggles: NotificationToggles
    )?
    var lastTokenExpiredFire: Bool?
    var lastReminderSchedule: (
        sessionResetsAt: Date?,
        weeklyResetsAt: Date?,
        toggles: NotificationToggles
    )?
    var stubbedAuthStatus: UNAuthorizationStatus = .notDetermined
    var testSent = false

    func setupDelegate() {}
    func requestPermission() { permissionRequested = true }
    func checkAuthorizationStatus() async -> UNAuthorizationStatus { stubbedAuthStatus }
    func sendTest() { testSent = true }

    func evaluate(
        fiveHour: MetricSnapshot,
        sevenDay: MetricSnapshot,
        sonnet: MetricSnapshot,
        design: MetricSnapshot,
        sessionPacing: PacingZone?,
        weeklyPacing: PacingZone?,
        extraUsage: ExtraUsage?,
        toggles: NotificationToggles
    ) {
        lastEvaluation = (fiveHour, sevenDay, sonnet, design, sessionPacing, weeklyPacing, extraUsage, toggles)
    }

    func notifyTokenExpired(toggle: Bool) {
        lastTokenExpiredFire = toggle
    }

    func scheduleResetReminders(
        sessionResetsAt: Date?,
        weeklyResetsAt: Date?,
        toggles: NotificationToggles
    ) {
        lastReminderSchedule = (sessionResetsAt, weeklyResetsAt, toggles)
    }
}
