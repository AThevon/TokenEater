import Testing
import Foundation

@Suite("CodexUsageStore")
@MainActor
struct CodexUsageStoreTests {

    // MARK: - Helpers

    private struct SUT {
        let store: CodexUsageStore
        let repo: MockCodexUsageRepository
        let tokenProvider: MockCodexTokenProvider
        let sharedFile: MockCodexSharedFileService
        let notif: MockNotificationService
    }

    private func makeSUT(
        credentials: CodexCredentials? = CodexFixtures.credentials(),
        usage: CodexUsageResponse = CodexFixtures.decode(CodexFixtures.plusJSON),
        error: APIError? = nil,
        enabled: Bool = true
    ) -> SUT {
        let repo = MockCodexUsageRepository()
        repo.stubbedUsage = usage
        repo.stubbedError = error

        let tokenProvider = MockCodexTokenProvider()
        tokenProvider.credentials = credentials
        tokenProvider.stubbedAuthState = credentials == nil
            ? .noCredentials
            : .chatgpt(accountId: credentials?.accountId, planType: credentials?.planType, expiresAt: credentials?.expiresAt)

        let sharedFile = MockCodexSharedFileService()
        let notif = MockNotificationService()
        let store = CodexUsageStore(
            repository: repo,
            tokenProvider: tokenProvider,
            sharedFileService: sharedFile,
            notificationService: notif
        )
        store.notifTogglesProvider = { Self.toggles() }
        if enabled { store.setEnabled(true) }
        return SUT(store: store, repo: repo, tokenProvider: tokenProvider, sharedFile: sharedFile, notif: notif)
    }

    private static func toggles(codex: CodexNotificationToggles = .default) -> NotificationToggles {
        NotificationToggles(
            masterEnabled: true,
            trackFiveHour: true, trackWeekly: true, trackSonnet: true, trackFable: true,
            sendRecovery: true, pacingHot: true, pacingWarning: false,
            resetReminderSession: false, resetReminderWeekly: false,
            resetReminderSessionOffsetMinutes: 15, resetReminderWeeklyOffsetMinutes: 60,
            extraCredits: true, tokenExpired: true,
            smartColorEnabled: false,
            smartColorProfile: .default,
            pacingMargin: 10,
            thresholds: .default,
            vendorDegraded: true, vendorRestored: true,
            codex: codex
        )
    }

    // MARK: - Disabled provider

    @Test("nothing is polled while the provider is off")
    func disabledDoesNothing() async {
        let sut = makeSUT(enabled: false)

        await sut.store.refresh(force: true)

        #expect(sut.repo.refreshCallCount == 0)
        #expect(sut.store.windows.isEmpty)
    }

    @Test("turning the provider on starts it and mirrors the flag for the widget")
    func enablingStarts() async {
        let sut = makeSUT(enabled: false)

        sut.store.setEnabled(true)
        await sut.store.refresh(force: true)

        #expect(sut.store.isEnabled)
        #expect(sut.sharedFile.updateEnabledCalls == [true])
        #expect(sut.repo.refreshCallCount >= 1)
    }

    @Test("turning it off clears the state, the widget payload and any reminder")
    func disablingClears() async {
        let sut = makeSUT()
        await sut.store.refresh(force: true)
        #expect(!sut.store.windows.isEmpty)

        sut.store.setEnabled(false)

        #expect(!sut.store.isEnabled)
        #expect(sut.store.windows.isEmpty)
        #expect(sut.store.lastUsage == nil)
        #expect(sut.store.planType == .unknown)
        #expect(sut.sharedFile.updateEnabledCalls.last == false)
        #expect(sut.notif.codexRemindersCancelled == 1)
    }

    @Test("notification changes reach the service immediately without another API call")
    func notificationSettingsChange() async {
        let sut = makeSUT()
        await sut.store.refresh(force: true)
        let calls = sut.repo.refreshCallCount
        var toggles = Self.toggles()
        toggles.codex.enabled = false
        sut.store.notifTogglesProvider = { toggles }

        sut.store.refreshNotificationSettings()

        #expect(sut.repo.refreshCallCount == calls)
        #expect(sut.notif.codexEvaluations.last?.toggles.codex.enabled == false)
        sut.store.setEnabled(false)
    }

    @Test("turning Codex off during a request cannot restore usage or send notifications")
    func disableDuringRequest() async {
        let sut = makeSUT()
        sut.repo.onRefresh = { sut.store.setEnabled(false) }

        await sut.store.refresh(force: true)

        #expect(!sut.store.isEnabled)
        #expect(sut.store.windows.isEmpty)
        #expect(sut.store.lastUpdate == nil)
        #expect(sut.notif.codexEvaluations.isEmpty)
        #expect(sut.sharedFile.clearCallCount == 1)
    }

    // MARK: - Refresh

    @Test("no credentials leaves the store disconnected without calling the API")
    func noCredentials() async {
        let sut = makeSUT(credentials: nil)

        await sut.store.refresh(force: true)

        #expect(sut.store.errorState == .tokenUnavailable)
        #expect(!sut.store.hasConfig)
        #expect(sut.repo.refreshCallCount == 0)
    }

    @Test("a successful refresh publishes windows, plan, credits and clears the error")
    func successPopulatesState() async {
        let sut = makeSUT()

        await sut.store.refresh(force: true)

        #expect(sut.store.errorState == .none)
        #expect(sut.store.hasConfig)
        #expect(sut.store.windows.count == 2)
        #expect(sut.store.session?.pct == 42)
        #expect(sut.store.weekly?.pct == 63)
        #expect(sut.store.planType == .plus)
        #expect(sut.store.credits?.balance == "12.50")
        #expect(sut.store.lastUpdate != nil)
        #expect(sut.store.lastAPIError == nil)
    }

    @Test("a weekly-only plan publishes one weekly window and no session window")
    func weeklyOnlyPlan() async {
        let sut = makeSUT(usage: CodexFixtures.decode(CodexFixtures.proliteJSON))

        await sut.store.refresh(force: true)

        #expect(sut.store.windows.count == 1)
        #expect(sut.store.session == nil)
        #expect(sut.store.weekly?.pct == 18)
        #expect(sut.store.planType == .proLite)
    }

    @Test("the server's limit verdict is published for the UI to trust over percentages")
    func limitReached() async {
        let sut = makeSUT(usage: CodexFixtures.decode(CodexFixtures.limitReachedJSON))

        await sut.store.refresh(force: true)

        #expect(sut.store.limitReached)
    }

    @Test("a successful refresh evaluates Codex notifications once")
    func notifiesOnSuccess() async {
        let sut = makeSUT()

        await sut.store.refresh(force: true)

        #expect(sut.notif.codexEvaluations.count == 1)
        #expect(sut.notif.codexEvaluations.first?.windows.count == 2)
    }

    // MARK: - Throttling

    @Test("a refresh inside the interval is skipped unless forced")
    func intervalGate() async {
        let sut = makeSUT()
        sut.store.refreshIntervalSeconds = 300
        await sut.store.refresh(force: true)
        let callsAfterFirst = sut.repo.refreshCallCount

        await sut.store.refresh()

        #expect(sut.repo.refreshCallCount == callsAfterFirst)

        await sut.store.refresh(force: true)
        #expect(sut.repo.refreshCallCount == callsAfterFirst + 1)
    }

    // MARK: - Errors

    @Test("a 401 invalidates the cache and retries once with the token Codex just wrote")
    func retriesOnceAfterUnauthorized() async {
        let sut = makeSUT()
        sut.repo.stubbedErrorOnce = .tokenExpired(endpoint: "/backend-api/wham/usage", statusCode: 401)
        sut.tokenProvider.credentialsAfterInvalidate = CodexFixtures.credentials(accessToken: "refreshed-token")

        await sut.store.refresh(force: true)

        #expect(sut.tokenProvider.invalidateCount == 1)
        #expect(sut.repo.refreshCallCount == 2)
        #expect(sut.repo.credentialsSeen.last?.accessToken == "refreshed-token")
        #expect(sut.store.errorState == .none)
    }

    @Test("a 401 with no fresher token surfaces the expired state and notifies once")
    func unauthorizedWithoutFreshToken() async {
        let sut = makeSUT(error: .tokenExpired(endpoint: "/backend-api/wham/usage", statusCode: 401))

        await sut.store.refresh(force: true)

        #expect(sut.store.errorState == .tokenUnavailable)
        #expect(sut.store.isDisconnected)
        #expect(sut.notif.codexTokenExpiredFires == 1)
        #expect(sut.store.lastAPIError?.httpStatusCode == 401)
    }

    @Test("an already-expired token short-circuits before any request")
    func expiredTokenSkipsRequest() async {
        let sut = makeSUT(credentials: CodexFixtures.credentials(expiresAt: Date().addingTimeInterval(-60)))

        await sut.store.refresh(force: true)

        #expect(sut.repo.refreshCallCount == 0)
        #expect(sut.store.errorState == .tokenUnavailable)
        #expect(sut.notif.codexTokenExpiredFires == 1)
    }

    @Test("an expired token still tries once with a fresher one found on disk")
    func expiredTokenUsesRefreshedOne() async {
        let sut = makeSUT(credentials: CodexFixtures.credentials(expiresAt: Date().addingTimeInterval(-60)))
        sut.tokenProvider.credentialsAfterInvalidate = CodexFixtures.credentials(
            accessToken: "fresh",
            expiresAt: Date().addingTimeInterval(864_000)
        )

        await sut.store.refresh(force: true)

        #expect(sut.repo.refreshCallCount == 1)
        #expect(sut.store.errorState == .none)
    }

    @Test("a 429 backs off and blocks the next unforced refresh")
    func rateLimited() async {
        let sut = makeSUT(error: .rateLimited(retryAfter: nil, retryAfterRaw: nil, endpoint: "/backend-api/wham/usage"))

        await sut.store.refresh(force: true)

        #expect(sut.store.errorState == .rateLimited)
        #expect(sut.store.retryAfterDate != nil)
        #expect(sut.store.currentSpeed == .slow)

        let callsSoFar = sut.repo.refreshCallCount
        await sut.store.refresh()
        #expect(sut.repo.refreshCallCount == callsSoFar)
    }

    @Test("a server Retry-After hint is honoured verbatim")
    func rateLimitedWithHint() async {
        let sut = makeSUT(error: .rateLimited(retryAfter: 90, retryAfterRaw: "90", endpoint: "/backend-api/wham/usage"))

        await sut.store.refresh(force: true)

        let retry = try? #require(sut.store.retryAfterDate)
        #expect((retry?.timeIntervalSinceNow ?? 0) <= 91)
        #expect((retry?.timeIntervalSinceNow ?? 0) > 80)
    }

    @Test("a network failure is reported without dropping the token")
    func networkError() async {
        let sut = makeSUT(error: .networkError(endpoint: "/backend-api/wham/usage", underlying: "offline"))

        await sut.store.refresh(force: true)

        #expect(sut.store.errorState == .networkError)
        #expect(sut.store.hasConfig)
        #expect(sut.tokenProvider.invalidateCount == 0)
    }

    @Test("a success after an error clears the backoff and the speed")
    func recoveryAfterError() async {
        let sut = makeSUT(error: .rateLimited(retryAfter: nil, retryAfterRaw: nil, endpoint: "/backend-api/wham/usage"))
        await sut.store.refresh(force: true)

        sut.repo.stubbedError = nil
        await sut.store.refresh(force: true)

        #expect(sut.store.errorState == .none)
        #expect(sut.store.retryAfterDate == nil)
        #expect(sut.store.currentSpeed == .normal)
    }

    // MARK: - Cache

    @Test("cached usage renders before the first network answer")
    func loadCached() async {
        let sut = makeSUT()
        sut.sharedFile._cachedUsage = CachedCodexUsage(
            usage: CodexFixtures.decode(CodexFixtures.proliteJSON),
            fetchDate: Date(timeIntervalSince1970: 1_789_000_000)
        )

        sut.store.loadCached()

        #expect(sut.store.weekly?.pct == 18)
        #expect(sut.store.lastUpdate == Date(timeIntervalSince1970: 1_789_000_000))
        // Cached rendering must not look like a live sync happened.
        #expect(sut.notif.codexEvaluations.isEmpty)
    }

    @Test("showing stale data alongside an expired token is the calm awaiting state")
    func awaitingRefresh() async {
        let sut = makeSUT()
        await sut.store.refresh(force: true)

        sut.repo.stubbedError = .tokenExpired(endpoint: "/backend-api/wham/usage", statusCode: 401)
        await sut.store.refresh(force: true)

        #expect(sut.store.isAwaitingRefresh)
    }

    // MARK: - Credential rotation

    @Test("a rotated credential clears the backoff and asks for a forced refresh")
    func reconcileDetectsRotation() async {
        let sut = makeSUT(error: .rateLimited(retryAfter: nil, retryAfterRaw: nil, endpoint: "/backend-api/wham/usage"))
        await sut.store.refresh(force: true)
        sut.tokenProvider.refreshIfChangedResult = true

        #expect(sut.store.reconcileCredentialsIfChanged())
        #expect(sut.store.retryAfterDate == nil)
        #expect(sut.store.currentSpeed == .fast)
    }

    @Test("an unchanged credential asks for nothing")
    func reconcileNoChange() {
        let sut = makeSUT()
        sut.tokenProvider.refreshIfChangedResult = false

        #expect(!sut.store.reconcileCredentialsIfChanged())
    }

    @Test("a file change invalidates the cached credential and speeds the poll up")
    func handleAuthChange() async {
        let sut = makeSUT(error: .rateLimited(retryAfter: nil, retryAfterRaw: nil, endpoint: "/backend-api/wham/usage"))
        await sut.store.refresh(force: true)

        sut.store.handleAuthChange()

        #expect(sut.tokenProvider.invalidateCount == 1)
        #expect(sut.store.retryAfterDate == nil)
        #expect(sut.store.currentSpeed == .fast)
    }

    // MARK: - Recomputation

    @Test("changing the pacing margin recomputes without refetching")
    func recalculatePacing() async {
        let now = Date()
        let usage = CodexFixtures.usage(
            primary: CodexFixtures.window(usedPercent: 70, windowSeconds: 18_000, resetAfterSeconds: 9_000, resetAt: now.addingTimeInterval(9_000))
        )
        let sut = makeSUT(usage: usage)
        await sut.store.refresh(force: true)
        let callsBefore = sut.repo.refreshCallCount

        // 20 points ahead of an even pace: hot at a 5-point margin, on track at 25.
        sut.store.pacingMargin = 5
        sut.store.recalculatePacing()
        #expect(sut.store.session?.pacing?.zone == .hot)

        sut.store.pacingMargin = 25
        sut.store.recalculatePacing()
        #expect(sut.store.session?.pacing?.zone == .onTrack)
        #expect(sut.repo.refreshCallCount == callsBefore)
    }
}
