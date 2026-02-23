import SwiftUI
import WidgetKit

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case prerequisites = 1
    case connection = 2
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
    case failed(String)
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
    @Published var isDetailedMode = false
    @Published var claudeCodeStatus: ClaudeCodeStatus = .checking
    @Published var connectionStatus: ConnectionStatus = .idle

    func checkClaudeCode() {
        claudeCodeStatus = .checking
        // Small delay so the UI has time to show "checking" state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.claudeCodeStatus = KeychainOAuthReader.tokenExists() ? .detected : .notFound
        }
    }

    func connect() {
        connectionStatus = .connecting

        guard let oauth = KeychainOAuthReader.readClaudeCodeToken() else {
            connectionStatus = .failed(String(localized: "onboarding.connection.failed.notoken"))
            return
        }

        SharedContainer.oauthToken = oauth.accessToken

        Task {
            do {
                let usage = try await ClaudeAPIClient.shared.fetchUsage()
                connectionStatus = .success(usage)
            } catch {
                connectionStatus = .failed(error.localizedDescription)
            }
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        WidgetCenter.shared.reloadAllTimelines()
    }

    func goNext() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = next
        }
    }

    func goBack() {
        guard let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = prev
        }
    }
}
