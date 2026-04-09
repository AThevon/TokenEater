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

    private let tokenProvider: TokenProviderProtocol
    private let repository: UsageRepositoryProtocol
    private let notificationService: NotificationServiceProtocol

    init(
        tokenProvider: TokenProviderProtocol = TokenProvider(),
        repository: UsageRepositoryProtocol = UsageRepository(),
        notificationService: NotificationServiceProtocol = NotificationService()
    ) {
        self.tokenProvider = tokenProvider
        self.repository = repository
        self.notificationService = notificationService
    }

    /// Whether the user might see a Keychain dialog (first connection attempt)
    var needsBootstrap: Bool { tokenProvider.currentToken() == nil }

    func checkClaudeCode() {
        claudeCodeStatus = .checking
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            // Check if a token source EXISTS (config.json or credentials file)
            // This doesn't require the decryption key — bootstrap happens in connect()
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
            logger.info("Bootstrap needed — reading Claude Safe Storage from Keychain")
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
            logger.error("No token after bootstrap — hasTokenSource=\(self.tokenProvider.hasTokenSource()), isBootstrapped=\(self.tokenProvider.isBootstrapped)")
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
