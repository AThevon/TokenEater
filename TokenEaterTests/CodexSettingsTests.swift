import Testing
import Foundation

@Suite("Codex settings", .serialized)
@MainActor
struct CodexSettingsTests {

    private let keys = [
        "codexEnabled",
        "notifCodexEnabled", "notifCodexTrackSession", "notifCodexTrackWeekly",
        "notifCodexWindowReset", "notifCodexResetReminderSession",
        "notifCodexResetReminderWeekly", "notifCodexTokenExpired",
    ]

    private func clean() {
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
    }

    // MARK: - Auto-enable

    @Test("a detected ChatGPT login turns the provider on by itself")
    func autoEnableOnDetection() {
        clean()
        defer { clean() }

        let store = SettingsStore(notificationService: MockNotificationService(), tokenProvider: MockTokenProvider(), sharedFileService: MockSharedFileService(), codexAuthStateProvider: { .chatgpt(accountId: "a", planType: "pro", expiresAt: nil) })

        #expect(store.codexEnabled)
    }

    @Test("a machine without Codex sees no change")
    func stayOffWhenNotInstalled() {
        clean()
        defer { clean() }

        #expect(!SettingsStore(notificationService: MockNotificationService(), tokenProvider: MockTokenProvider(), sharedFileService: MockSharedFileService(), codexAuthStateProvider: { .notInstalled }).codexEnabled)
    }

    @Test("an API-key login does not turn it on: there are no windows to track")
    func apiKeyDoesNotAutoEnable() {
        clean()
        defer { clean() }

        #expect(!SettingsStore(notificationService: MockNotificationService(), tokenProvider: MockTokenProvider(), sharedFileService: MockSharedFileService(), codexAuthStateProvider: { .apiKeyOnly }).codexEnabled)
    }

    @Test("the detection runs once: a user who turns it off is not overridden on the next launch")
    func detectionRunsOnce() {
        clean()
        defer { clean() }

        let first = SettingsStore(notificationService: MockNotificationService(), tokenProvider: MockTokenProvider(), sharedFileService: MockSharedFileService(), codexAuthStateProvider: { .chatgpt(accountId: "a", planType: "pro", expiresAt: nil) })
        #expect(first.codexEnabled)
        first.codexEnabled = false

        let second = SettingsStore(notificationService: MockNotificationService(), tokenProvider: MockTokenProvider(), sharedFileService: MockSharedFileService(), codexAuthStateProvider: { .chatgpt(accountId: "a", planType: "pro", expiresAt: nil) })
        #expect(!second.codexEnabled)
    }

    @Test("a later login does not flip the toggle on its own")
    func laterLoginDoesNotFlip() {
        clean()
        defer { clean() }

        _ = SettingsStore(notificationService: MockNotificationService(), tokenProvider: MockTokenProvider(), sharedFileService: MockSharedFileService(), codexAuthStateProvider: { .notInstalled })
        let afterLogin = SettingsStore(notificationService: MockNotificationService(), tokenProvider: MockTokenProvider(), sharedFileService: MockSharedFileService(), codexAuthStateProvider: { .chatgpt(accountId: "a", planType: "pro", expiresAt: nil) })

        #expect(!afterLogin.codexEnabled)
    }

    // MARK: - Notification toggles

    @Test("Codex notification defaults favour the alerts people install this for")
    func notificationDefaults() {
        clean()
        defer { clean() }

        let store = NotificationSettingsStore()

        #expect(store.codexEnabled)
        #expect(store.codexTrackSession)
        #expect(store.codexTrackWeekly)
        #expect(store.codexWindowReset)
        #expect(store.codexTokenExpired)
        // Scheduled reminders stay opt-in, like the Claude ones.
        #expect(!store.codexResetReminderSession)
        #expect(!store.codexResetReminderWeekly)
    }

    @Test("Codex toggles persist across store instances")
    func persistence() {
        clean()
        defer { clean() }

        let store = NotificationSettingsStore()
        store.codexWindowReset = false
        store.codexResetReminderWeekly = true

        let reloaded = NotificationSettingsStore()
        #expect(!reloaded.codexWindowReset)
        #expect(reloaded.codexResetReminderWeekly)
    }

    @Test("the bundle handed to the service mirrors the stored toggles")
    func togglesBundle() {
        clean()
        defer { clean() }

        let store = NotificationSettingsStore()
        store.codexEnabled = false
        store.codexTrackWeekly = false

        let bundle = store.codexToggles
        #expect(!bundle.enabled)
        #expect(!bundle.trackWeekly)
        #expect(bundle.trackSession)
    }
}
