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

/// Where a provider is in its setup, whichever provider it is.
///
/// One vocabulary for both, so the card can be one card. The states are about
/// the credential, never about whether the user wants to track that provider:
/// tracking is a switch the user owns, and a provider can be perfectly ready
/// and deliberately off.
enum ProviderSetupState: Equatable {
    /// Looking at the machine.
    case checking
    /// The CLI that produces the credential is not installed.
    case notInstalled
    /// Installed, but something is needed before it works: a Keychain
    /// authorization for Claude, a ChatGPT sign-in for OpenAI.
    case needsAction
    /// Usable right now.
    case ready
    /// Tried and refused, or expired. Carries what to say about it.
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
    @Published var codexStatus: CodexAuthState
    /// Mirrors of the two tracking switches. The view model owns its own
    /// `SettingsStore` (environment objects are not reachable from a
    /// `@StateObject` initializer), so the cards write to the live store and
    /// mirror back here, and progress stays accurate either way.
    @Published var codexEnabled: Bool
    @Published var claudeEnabled: Bool
    @Published var claudeCodeStatus: ClaudeCodeStatus = .checking
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var notificationStatus: NotificationStatus = .unknown

    /// Bridges `SettingsStore.overlayEnabled` so the Watchers card can
    /// toggle directly without going through an environment object. Default
    /// reflects the current store value at init time so re-running the
    /// onboarding shows the user's existing preference.
    @Published var watcherEnabled: Bool

    /// Cards that can reach a ready state: one per provider the user is
    /// tracking, plus the two feature cards.
    ///
    /// A provider switched off is not an unfinished step. Counting it was what
    /// left the bar permanently short of full for anyone who only uses one of
    /// the two, which reads as "you did not finish" on a wizard they did in
    /// fact finish.
    var totalSteps: Int { (claudeEnabled ? 1 : 0) + (codexEnabled ? 1 : 0) + 2 }

    /// Where each provider stands. One vocabulary, so the two cards are the
    /// same card: see `ProviderSetupState`.
    func setupState(for provider: MetricProvider) -> ProviderSetupState {
        switch provider {
        case .claude:
            switch claudeCodeStatus {
            case .checking:
                return .checking
            case .notFound:
                return .notInstalled
            case .detected:
                switch connectionStatus {
                case .idle:                  return .needsAction
                case .connecting:            return .checking
                // Rate limited counts as connected: the token is fine and the
                // server is throttling.
                case .success, .rateLimited: return .ready
                case .failed(let message):   return .failed(message)
                }
            }

        case .codex:
            // Expiry first: an expired login is still a `.chatgpt` credential,
            // and reporting it as ready would hand the user a card that says
            // connected above an app that cannot read anything.
            if codexStatus.isExpired() {
                return .failed(String(localized: "codex.status.expired"))
            }
            switch codexStatus {
            case .notInstalled:              return .notInstalled
            case .noCredentials, .apiKeyOnly: return .needsAction
            case .chatgpt:                   return .ready
            }
        }
    }

    /// Claude is usable and tracked.
    var claudeReady: Bool { claudeEnabled && setupState(for: .claude) == .ready }

    /// Codex is usable and tracked.
    var codexReady: Bool { codexEnabled && setupState(for: .codex) == .ready }

    /// Pulls both switches back from the live store after a card wrote to it.
    func syncTracking(from store: SettingsStore) {
        claudeEnabled = store.claudeEnabled
        codexEnabled = store.codexEnabled
    }

    private let codexAuthStateProvider: () -> CodexAuthState
    private let tokenProvider: TokenProviderProtocol
    private let repository: UsageRepositoryProtocol
    private let notificationService: NotificationServiceProtocol
    private let settingsStore: SettingsStore

    init(
        tokenProvider: TokenProviderProtocol = TokenProvider(),
        repository: UsageRepositoryProtocol = UsageRepository(),
        notificationService: NotificationServiceProtocol = NotificationService(),
        settingsStore: SettingsStore? = nil,
        codexAuthStateProvider: @escaping () -> CodexAuthState = { CodexAuthReader().authState() }
    ) {
        self.codexAuthStateProvider = codexAuthStateProvider
        self.codexStatus = codexAuthStateProvider()
        self.tokenProvider = tokenProvider
        self.repository = repository
        self.notificationService = notificationService
        let store = settingsStore ?? SettingsStore(
            notificationService: notificationService,
            tokenProvider: tokenProvider
        )
        self.settingsStore = store
        self.watcherEnabled = store.overlayEnabled
        self.codexEnabled = store.codexEnabled
        self.claudeEnabled = store.claudeEnabled
    }

    /// Whether the user might see a Keychain dialog (first connection attempt)
    var needsBootstrap: Bool { tokenProvider.currentToken() == nil }

    /// Gating rule for the Finish button: at least one provider has to work.
    ///
    /// It used to require Claude specifically, which locked out someone whose
    /// only subscription is ChatGPT. The app tracks whatever the person
    /// actually uses, so one working provider is enough to be useful.
    var canFinish: Bool { claudeReady || codexReady }

    /// How many of the cards on screen are in their ready state. One per
    /// tracked provider, since detection and authorization are one card now,
    /// plus the feature toggles, which count when on (Watchers) or authorized
    /// (Notifications).
    var readyCount: Int {
        var count = 0
        if claudeReady { count += 1 }
        if codexReady { count += 1 }
        if notificationStatus == .authorized { count += 1 }
        if watcherEnabled { count += 1 }
        return min(count, totalSteps)
    }

    /// Updates `SettingsStore.overlayEnabled` whenever the user flicks the
    /// Watchers toggle. Called from `WatchersCard`.
    func setWatcherEnabled(_ enabled: Bool) {
        watcherEnabled = enabled
        settingsStore.overlayEnabled = enabled
    }

    func checkCodex() {
        codexStatus = codexAuthStateProvider()
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

        let provider = tokenProvider
        Task {
            // Resolve the token OFF the main thread - currentToken() may shell
            // out to /usr/bin/security, which can block on macOS 26 (see #217).
            // Only silent sources are used, so this never surfaces a Keychain
            // prompt.
            let token = await Self.tokenOffMain(provider)

            guard let token else {
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

    func completeOnboarding() {
        WidgetReloader.scheduleReload()
    }
}
