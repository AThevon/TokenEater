import SwiftUI
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.tokeneater.app", category: "Onboarding")

enum ClaudeCodeStatus {
    case checking
    case detected
    case notFound
}

enum ConnectionStatus {
    case idle
    case connecting
    case success(UsageResponse)
    case rateLimited
    case failed(String)
}

enum NotificationStatus {
    case unknown
    case authorized
    case denied
    case notYetAsked
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var claudeCodeStatus: ClaudeCodeStatus = .checking
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var notificationStatus: NotificationStatus = .unknown

    /// Bridges `SettingsStore.overlayEnabled` so the Watchers card can
    /// toggle directly without going through an environment object. Default
    /// reflects the current store value at init time so re-running the
    /// onboarding shows the user's existing preference.
    @Published var watcherEnabled: Bool

    /// Total number of cards the user can interact with. Used by the hero
    /// progress indicator. Hard-coded at 4 (Claude Code, Notifications,
    /// Watchers, Connect).
    let totalSteps: Int = 4

    private let tokenProvider: TokenProviderProtocol
    private let repository: UsageRepositoryProtocol
    private let notificationService: NotificationServiceProtocol
    private let settingsStore: SettingsStore

    init(
        tokenProvider: TokenProviderProtocol = TokenProvider(),
        repository: UsageRepositoryProtocol = UsageRepository(),
        notificationService: NotificationServiceProtocol = NotificationService(),
        settingsStore: SettingsStore? = nil
    ) {
        self.tokenProvider = tokenProvider
        self.repository = repository
        self.notificationService = notificationService
        let store = settingsStore ?? SettingsStore(
            notificationService: notificationService,
            tokenProvider: tokenProvider
        )
        self.settingsStore = store
        self.watcherEnabled = store.overlayEnabled
    }

    /// Whether the user might see a Keychain dialog (first connection attempt)
    var needsBootstrap: Bool { tokenProvider.currentToken() == nil }

    /// Gating rule for the Finish button. Both required cards must succeed:
    /// Claude Code detected AND Connect connected (rateLimited counts as
    /// connected because the token works - server is just throttling).
    var canFinish: Bool {
        guard claudeCodeStatus == .detected else { return false }
        switch connectionStatus {
        case .success, .rateLimited:
            return true
        default:
            return false
        }
    }

    /// Hero progress count - how many of the 4 cards are in their "ready"
    /// state. Both gates must be green; optional toggles count as ready
    /// when on (Watchers) or authorized (Notifications).
    var readyCount: Int {
        var count = 0
        if claudeCodeStatus == .detected { count += 1 }
        if notificationStatus == .authorized { count += 1 }
        if watcherEnabled { count += 1 }
        switch connectionStatus {
        case .success, .rateLimited:
            count += 1
        default:
            break
        }
        return count
    }

    /// Updates `SettingsStore.overlayEnabled` whenever the user flicks the
    /// Watchers toggle. Called from `WatchersCard`.
    func setWatcherEnabled(_ enabled: Bool) {
        watcherEnabled = enabled
        settingsStore.overlayEnabled = enabled
    }

    func checkClaudeCode() {
        claudeCodeStatus = .checking
        // Detect a token source OFF the main thread: hasTokenSource() can shell
        // out to /usr/bin/security, which may block for up to the reader's
        // watchdog timeout on macOS 26 (see #217). Running it on the main thread
        // froze onboarding and left the menu-bar item stuck.
        let provider = tokenProvider
        DispatchQueue.global(qos: .userInitiated).async {
            let hasSource = provider.hasTokenSource()
            DispatchQueue.main.async { [weak self] in
                self?.claudeCodeStatus = hasSource ? .detected : .notFound
            }
        }
    }

    func checkNotificationStatus() {
        Task {
            let status = await notificationService.checkAuthorizationStatus()
            switch status {
            case .authorized, .provisional, .ephemeral:
                notificationStatus = .authorized
            case .denied:
                notificationStatus = .denied
            case .notDetermined:
                notificationStatus = .notYetAsked
            @unknown default:
                notificationStatus = .unknown
            }
        }
    }

    func requestNotifications() {
        notificationService.requestPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkNotificationStatus()
        }
    }

    func sendTestNotification() {
        notificationService.sendTest()
    }

    func connect() {
        connectionStatus = .connecting
        NSApp.activate(ignoringOtherApps: true)

        let provider = tokenProvider
        Task {
            // Resolve the token OFF the main thread - currentToken() may shell
            // out to /usr/bin/security, which can block on macOS 26 (see #217).
            var token = await Self.tokenOffMain(provider)

            // Silent sources found nothing. This is the macOS 26 case where the
            // security shell-out hangs and TokenEater isn't yet in the Keychain
            // item's ACL. An interactive read surfaces the one-time "Always
            // Allow" prompt that grants access; afterwards the silent read
            // works. Gated on a missing token, so healthy setups never prompt.
            if token == nil {
                logger.info("No token via silent sources - attempting interactive Keychain grant")
                await Self.interactiveBootstrapOffMain(provider)
                token = await Self.tokenOffMain(provider)
            }

            guard let token else {
                logger.error("No token after interactive bootstrap - hasTokenSource=\(provider.hasTokenSource())")
                connectionStatus = .failed(String(localized: "onboarding.connection.failed.notoken"))
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            do {
                let usage = try await repository.testConnection(token: token, proxyConfig: nil)
                connectionStatus = .success(usage)
            } catch let error as APIError {
                if case .rateLimited = error {
                    connectionStatus = .rateLimited
                } else {
                    connectionStatus = .failed(error.localizedDescription)
                }
            } catch {
                connectionStatus = .failed(error.localizedDescription)
            }
            NSApp.activate(ignoringOtherApps: true)

            // A fresh ACL grant makes the silent detection succeed now - re-run
            // so the Claude Code card flips from "not found" to "detected".
            if claudeCodeStatus != .detected {
                checkClaudeCode()
            }
        }
    }

    /// Reads the current token off the main thread. `currentToken()` can spawn
    /// `/usr/bin/security`, which may block, so it must never run on the main
    /// thread during onboarding.
    private static func tokenOffMain(_ provider: TokenProviderProtocol) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: provider.currentToken())
            }
        }
    }

    /// Runs an interactive Keychain bootstrap off the main thread. This is the
    /// one read allowed to surface a Keychain prompt: granting "Always Allow"
    /// adds TokenEater to the "Claude Code-credentials" item ACL, after which
    /// silent reads succeed (the fix for the macOS 26 shell-out hang, #217).
    private static func interactiveBootstrapOffMain(_ provider: TokenProviderProtocol) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                try? provider.bootstrap()
                continuation.resume()
            }
        }
    }

    func completeOnboarding() {
        WidgetReloader.scheduleReload()
    }
}
