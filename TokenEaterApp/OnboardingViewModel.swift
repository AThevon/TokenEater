import SwiftUI
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.tokeneater.app", category: "Onboarding")

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case prerequisites = 1
    case notifications = 2
    case agentWatchers = 3
    case connection = 4
}

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
    @Published var currentStep: OnboardingStep = .welcome
    @Published var isNavigatingForward: Bool = true
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            // Check if a token source EXISTS (config.json or credentials file)
            // This doesn't require the decryption key - bootstrap happens in connect()
            let hasSource = self.tokenProvider.hasTokenSource()
            self.claudeCodeStatus = hasSource ? .detected : .notFound
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

        // Bootstrap encryption key if needed (triggers one-time Keychain modal)
        if !tokenProvider.isBootstrapped {
            logger.info("Bootstrap needed - reading Claude Safe Storage from Keychain")
            do {
                try tokenProvider.bootstrap()
                logger.info("Bootstrap succeeded, isBootstrapped=\(self.tokenProvider.isBootstrapped)")
            } catch {
                logger.error("Bootstrap failed: \(error)")
                connectionStatus = .failed(String(localized: "onboarding.connection.failed.notoken"))
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }

        let token = tokenProvider.currentToken()
        logger.info("currentToken result: \(token != nil ? "got token (\(token!.prefix(10))...)" : "nil")")
        guard let token else {
            logger.error("No token after bootstrap - hasTokenSource=\(self.tokenProvider.hasTokenSource()), isBootstrapped=\(self.tokenProvider.isBootstrapped)")
            connectionStatus = .failed(String(localized: "onboarding.connection.failed.notoken"))
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        Task {
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
        }
    }

    func completeOnboarding() {
        WidgetReloader.scheduleReload()
    }

    func goNext() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        isNavigatingForward = true
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = next
        }
    }

    func goBack() {
        guard let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        isNavigatingForward = false
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = prev
        }
    }
}
