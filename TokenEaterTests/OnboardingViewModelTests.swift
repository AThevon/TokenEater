import Testing
import Foundation

private let settingsKeys = ["overlayEnabled", "hasCompletedOnboarding"]

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

    @Test("readyCount counts gates and optional toggles independently")
    func readyCountSemantics() {
        let vm = makeViewModel()
        vm.claudeCodeStatus = .detected
        vm.connectionStatus = .idle
        vm.watcherEnabled = true
        #expect(vm.readyCount == 2)
        #expect(vm.totalSteps == 5)
    }
    @Test("Codex is optional and only a usable enabled login counts toward progress")
    func codexProgress() {
        let vm = makeViewModel()
        vm.claudeCodeStatus = .detected
        vm.connectionStatus = .success(UsageResponse())
        vm.watcherEnabled = false
        vm.codexEnabled = true
        #expect(vm.canFinish)
        #expect(vm.readyCount == 2)
        vm.codexStatus = .chatgpt(accountId: nil, planType: "prolite", expiresAt: nil)
        #expect(vm.readyCount == 3)
        vm.codexEnabled = false
        #expect(vm.readyCount == 2)
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
        #expect(vm.readyCount == 2)
        #expect(vm.canFinish)
        vm.codexStatus = .apiKeyOnly
        #expect(vm.readyCount == 2)
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
