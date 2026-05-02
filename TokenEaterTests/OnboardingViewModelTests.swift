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
        notificationService: NotificationServiceProtocol = MockNotificationService()
    ) -> OnboardingViewModel {
        cleanDefaults()
        return OnboardingViewModel(
            tokenProvider: tokenProvider,
            repository: repository,
            notificationService: notificationService
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
        // claudeCode + watchers = 2 ready out of 4
        #expect(vm.readyCount == 2)
        #expect(vm.totalSteps == 4)
    }
}
