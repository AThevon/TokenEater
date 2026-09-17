import Testing
import Foundation

private let settingsKeys = ["overlayEnabled", "hasCompletedOnboarding", "claudeEnabled", "codexEnabled"]

private func cleanDefaults() {
    for key in settingsKeys {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

@Suite("OnboardingViewModel", .serialized)
@MainActor
struct OnboardingViewModelTests {

    private func makeViewModel(
        tokenProvider: TokenProviderProtocol = MockTokenProvider(),
        repository: UsageRepositoryProtocol = MockUsageRepository(),
        notificationService: NotificationServiceProtocol = MockNotificationService(),
        codexAuthStateProvider: @escaping () -> CodexAuthState = { .notInstalled }
    ) -> OnboardingViewModel {
        cleanDefaults()
        return OnboardingViewModel(
            tokenProvider: tokenProvider,
            repository: repository,
            notificationService: notificationService,
            codexAuthStateProvider: codexAuthStateProvider
        )
    }

    @Test("canFinish is false when both gates are pending")
    func gatingBothPending() {
        let vm = makeViewModel()
        vm.claudeCodeStatus = .checking
        vm.connectionStatus = .idle
        #expect(vm.canFinish == false)
    }

    @Test("canFinish is false when only Claude Code is detected")
    func gatingOnlyClaudeCode() {
        let vm = makeViewModel()
        vm.claudeCodeStatus = .detected
        vm.connectionStatus = .idle
        #expect(vm.canFinish == false)
    }

    @Test("canFinish is false when only Connect succeeded")
    func gatingOnlyConnect() {
        let vm = makeViewModel()
        vm.claudeCodeStatus = .notFound
        vm.connectionStatus = .success(UsageResponse())
        #expect(vm.canFinish == false)
    }

    @Test("canFinish is true when Claude Code detected + Connect success")
    func gatingBothSuccess() {
        let vm = makeViewModel()
        vm.claudeCodeStatus = .detected
        vm.connectionStatus = .success(UsageResponse())
        #expect(vm.canFinish == true)
    }

    @Test("canFinish is true when Claude Code detected + Connect rateLimited")
    func gatingRateLimitedCountsAsConnected() {
        let vm = makeViewModel()
        vm.claudeCodeStatus = .detected
        vm.connectionStatus = .rateLimited
        #expect(vm.canFinish == true)
    }

    @Test("canFinish is false when Connect failed")
    func gatingFailedDoesNotCount() {
        let vm = makeViewModel()
        vm.claudeCodeStatus = .detected
        vm.connectionStatus = .failed("nope")
        #expect(vm.canFinish == false)
    }

    @Test("A provider is one step, detection and authorization together")
    func readyCountSemantics() {
        let vm = makeViewModel()
        vm.claudeEnabled = true
        vm.codexEnabled = false
        vm.claudeCodeStatus = .detected
        vm.connectionStatus = .idle
        vm.watcherEnabled = true
        // Detected but not authorized is half of one card, not one of two:
        // only the watcher toggle is ready.
        #expect(vm.readyCount == 1)
        vm.connectionStatus = .success(UsageResponse())
        #expect(vm.readyCount == 2)
        // One tracked provider plus the two feature cards.
        #expect(vm.totalSteps == 3)
    }

    @Test("A provider switched off is not an unfinished step")
    func stepCountFollowsTheToggles() {
        let vm = makeViewModel(codexAuthStateProvider: { .chatgpt(accountId: "a", planType: "plus", expiresAt: Date().addingTimeInterval(86_400)) })
        vm.claudeEnabled = true
        vm.codexEnabled = true
        #expect(vm.totalSteps == 4)
        vm.codexEnabled = false
        // The bar used to count a provider the user had turned off, so it
        // could never fill for anyone who uses only one of the two.
        #expect(vm.totalSteps == 3)
    }

    @Test("Both providers speak the same five setup states")
    func setupStatesAreSymmetric() {
        let vm = makeViewModel()

        vm.claudeCodeStatus = .checking
        #expect(vm.setupState(for: .claude) == .checking)
        vm.claudeCodeStatus = .notFound
        #expect(vm.setupState(for: .claude) == .notInstalled)
        vm.claudeCodeStatus = .detected
        #expect(vm.setupState(for: .claude) == .needsAction)
        vm.connectionStatus = .success(UsageResponse())
        #expect(vm.setupState(for: .claude) == .ready)
        vm.connectionStatus = .failed("denied")
        #expect(vm.setupState(for: .claude) == .failed("denied"))

        vm.codexStatus = .notInstalled
        #expect(vm.setupState(for: .codex) == .notInstalled)
        vm.codexStatus = .noCredentials
        #expect(vm.setupState(for: .codex) == .needsAction)
        vm.codexStatus = .apiKeyOnly
        #expect(vm.setupState(for: .codex) == .needsAction)
        vm.codexStatus = .chatgpt(accountId: "a", planType: "plus", expiresAt: Date().addingTimeInterval(86_400))
        #expect(vm.setupState(for: .codex) == .ready)
        // An expired login is still a ChatGPT credential. Reporting it ready
        // would put "connected" over an app that cannot read anything.
        vm.codexStatus = .chatgpt(accountId: "a", planType: "plus", expiresAt: .distantPast)
        if case .failed = vm.setupState(for: .codex) {} else {
            Issue.record("an expired Codex login must report a failed state")
        }
    }

    @Test("Turning a provider off drops it out of the finish gate")
    func trackingGatesReadiness() {
        let vm = makeViewModel()
        vm.claudeCodeStatus = .detected
        vm.connectionStatus = .success(UsageResponse())
        #expect(vm.canFinish)
        // The wizard forbids this on the last provider; the model still has to
        // answer honestly, or Finish would let someone through to an app with
        // nothing switched on.
        vm.claudeEnabled = false
        #expect(vm.canFinish == false)
    }

    @Test("A working Codex login alone is enough to finish")
    func codexOnlyCanFinish() {
        let vm = makeViewModel(codexAuthStateProvider: { .chatgpt(accountId: "a", planType: "plus", expiresAt: Date().addingTimeInterval(86_400)) })
        vm.claudeCodeStatus = .notFound
        vm.connectionStatus = .idle
        vm.codexEnabled = true
        // Someone whose only subscription is ChatGPT used to be locked out of
        // the Finish button entirely.
        #expect(vm.canFinish)
    }
    @Test("Codex is optional and only a usable enabled login counts toward progress")
    func codexProgress() {
        let vm = makeViewModel()
        vm.claudeCodeStatus = .detected
        vm.connectionStatus = .success(UsageResponse())
        vm.watcherEnabled = false
        vm.codexEnabled = true
        #expect(vm.canFinish)
        #expect(vm.readyCount == 1)
        vm.codexStatus = .chatgpt(accountId: nil, planType: "prolite", expiresAt: nil)
        #expect(vm.readyCount == 2)
        vm.codexEnabled = false
        #expect(vm.readyCount == 1)
        #expect(vm.canFinish)
    }

    @Test("an expired or API-key Codex login does not count as ready or block Finish")
    func codexUnsupported() {
        let vm = makeViewModel()
        vm.claudeCodeStatus = .detected
        vm.connectionStatus = .rateLimited
        vm.watcherEnabled = false
        vm.codexEnabled = true
        vm.codexStatus = .chatgpt(accountId: nil, planType: "plus", expiresAt: .distantPast)
        #expect(vm.readyCount == 1)
        #expect(vm.canFinish)
        vm.codexStatus = .apiKeyOnly
        #expect(vm.readyCount == 1)
        #expect(vm.canFinish)
    }

    @Test("Codex detection can be refreshed after a CLI login")
    func codexRedetection() {
        var state = CodexAuthState.noCredentials
        let vm = makeViewModel(codexAuthStateProvider: { state })
        #expect(vm.codexStatus == .noCredentials)
        state = .chatgpt(accountId: nil, planType: "plus", expiresAt: nil)
        vm.checkCodex()
        #expect(vm.codexStatus.isTrackable)
    }

}
