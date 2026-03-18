import Testing
import Foundation

@Suite("UsageStore")
@MainActor
struct UsageStoreTests {

    // MARK: - Helpers

    private func makeSUT(
        token: String? = "valid-token",
        shouldFail: Bool = false,
        failWith: APIError? = nil,
        usage: UsageResponse = .fixture()
    ) -> (store: UsageStore, repo: MockUsageRepository, keychain: MockKeychainService, notif: MockNotificationService) {
        let repo = MockUsageRepository()
        if shouldFail {
            repo.stubbedError = failWith ?? .invalidResponse
        }
        repo.stubbedUsage = usage
        let keychain = MockKeychainService()
        keychain.storedToken = token
        let notif = MockNotificationService()
        let store = UsageStore(repository: repo, keychainService: keychain, notificationService: notif)
        // Sync the token into the store so it's configured
        if token != nil {
            store.syncCredentialsFile()
        }
        return (store, repo, keychain, notif)
    }

    // MARK: - refresh — basic

    @Test("refresh updates percentages from API")
    func refreshUpdatesPercentages() async {
        let (store, _, _, _) = makeSUT(usage: .fixture(fiveHourUtil: 42, sevenDayUtil: 65, sonnetUtil: 30))

        await store.refresh()

        #expect(store.fiveHourPct == 42)
        #expect(store.sevenDayPct == 65)
        #expect(store.sonnetPct == 30)
    }

    @Test("refresh sets lastUpdate on success")
    func refreshSetsLastUpdate() async {
        let (store, _, _, _) = makeSUT()

        #expect(store.lastUpdate == nil)
        await store.refresh()
        #expect(store.lastUpdate != nil)
    }

    @Test("refresh sets isLoading false after completion")
    func refreshSetsIsLoadingFalseAfterCompletion() async {
        let (store, _, _, _) = makeSUT()

        await store.refresh()

        #expect(store.isLoading == false)
    }

    @Test("refresh syncs credentials when not configured")
    func refreshSyncsCredentialsFileWhenNotConfigured() async {
        let repo = MockUsageRepository()
        repo.stubbedUsage = .fixture()
        let keychain = MockKeychainService()
        // No token initially
        keychain.storedToken = nil
        let notif = MockNotificationService()
        let store = UsageStore(repository: repo, keychainService: keychain, notificationService: notif)

        // Store is not configured — refresh should try to sync
        await store.refresh()

        // Not configured, so no API call
        #expect(repo.refreshCallCount == 0)
    }

    @Test("refresh checks notification thresholds on success")
    func refreshChecksNotificationThresholds() async {
        let (store, _, _, notif) = makeSUT(usage: .fixture(fiveHourUtil: 42, sevenDayUtil: 65, sonnetUtil: 30))

        await store.refresh()

        #expect(notif.lastThresholdCheck?.fiveHour.pct == 42)
        #expect(notif.lastThresholdCheck?.sevenDay.pct == 65)
        #expect(notif.lastThresholdCheck?.sonnet.pct == 30)
    }

    // MARK: - refresh — hasConfig

    @Test("refresh sets hasConfig false when not configured and no failed token")
    func refreshSetsHasConfigFalse() async {
        let repo = MockUsageRepository()
        let keychain = MockKeychainService()
        keychain.storedToken = nil
        let notif = MockNotificationService()
        let store = UsageStore(repository: repo, keychainService: keychain, notificationService: notif)

        await store.refresh()

        #expect(store.hasConfig == false)
    }

    @Test("refresh sets hasConfig true on successful API call")
    func refreshSetsHasConfigTrue() async {
        let (store, _, _, _) = makeSUT()

        await store.refresh()

        #expect(store.hasConfig == true)
    }

    // MARK: - refresh — error states

    @Test("refresh sets tokenUnavailable error on 401")
    func refreshSetsTokenUnavailableError() async {
        let (store, _, _, _) = makeSUT(shouldFail: true, failWith: .tokenExpired)

        await store.refresh()

        #expect(store.errorState == .tokenUnavailable)
        #expect(store.hasError == true)
    }

    @Test("refresh sets networkError on generic API error")
    func refreshSetsNetworkError() async {
        let (store, _, _, _) = makeSUT(shouldFail: true, failWith: .invalidResponse)

        await store.refresh()

        #expect(store.errorState == .networkError)
    }

    @Test("refresh clears error state on success after previous failure")
    func refreshClearsErrorOnSuccess() async {
        let (store, repo, _, _) = makeSUT(shouldFail: true, failWith: .invalidResponse)

        await store.refresh()
        #expect(store.hasError == true)

        // Fix the repo and retry
        repo.stubbedError = nil
        repo.stubbedUsage = .fixture()
        await store.refresh()

        #expect(store.hasError == false)
        #expect(store.errorState == .none)
    }

    // MARK: - refresh — lastFailedToken

    @Test("refresh skips API when currentToken matches lastFailedToken and keychain returns same token")
    func refreshSkipsAPIWhenTokenAlreadyFailed() async {
        let (store, repo, _, _) = makeSUT(token: "dead-token", shouldFail: true, failWith: .tokenExpired)

        // First call: token fails → lastFailedToken = "dead-token"
        await store.refresh()
        #expect(store.errorState == .tokenUnavailable)

        // Second call: keychain still returns "dead-token" → guard returns early, no new API call
        repo.stubbedError = nil
        repo.stubbedUsage = .fixture(fiveHourUtil: 99)
        await store.refresh()

        // Store should NOT have updated because the token is still the failed one
        #expect(store.fiveHourPct != 99)
    }

    @Test("refresh retries when keychain provides a new token after failure")
    func refreshRetriesWithNewToken() async {
        let (store, repo, keychain, _) = makeSUT(token: "dead-token", shouldFail: true, failWith: .tokenExpired)

        // First call: token fails
        await store.refresh()
        #expect(store.errorState == .tokenUnavailable)

        // Simulate keychain now has a fresh token
        keychain.storedToken = "fresh-token"
        repo.stubbedError = nil
        repo.stubbedUsage = .fixture(fiveHourUtil: 77)

        await store.refresh()

        #expect(store.fiveHourPct == 77)
        #expect(store.errorState == .none)
    }

    // MARK: - refresh — fiveHourReset formatting

    @Test("refresh formats fiveHourReset as hours and minutes")
    func refreshFormatsFiveHourReset() async {
        let futureDate = Date().addingTimeInterval(2 * 3600 + 30 * 60) // 2h30min
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let resetsAt = formatter.string(from: futureDate)

        let usage = UsageResponse(
            fiveHour: .fixture(utilization: 50, resetsAt: resetsAt)
        )
        let (store, _, _, _) = makeSUT(usage: usage)

        await store.refresh()

        #expect(store.fiveHourReset.contains("h"))
        #expect(store.fiveHourReset.contains("min"))
    }

    @Test("refresh formats fiveHourReset as minutes only when < 1h")
    func refreshFormatsMinutesOnly() async {
        let futureDate = Date().addingTimeInterval(45 * 60) // 45min
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let resetsAt = formatter.string(from: futureDate)

        let usage = UsageResponse(
            fiveHour: .fixture(utilization: 50, resetsAt: resetsAt)
        )
        let (store, _, _, _) = makeSUT(usage: usage)

        await store.refresh()

        #expect(!store.fiveHourReset.contains("h"))
        #expect(store.fiveHourReset.contains("min"))
    }

    // MARK: - refresh — pacing

    @Test("refresh updates pacing from usage data")
    func refreshUpdatesPacing() async {
        let now = Date()
        let totalDuration: TimeInterval = 7 * 24 * 3600
        let resetsAt = now.addingTimeInterval(0.5 * totalDuration) // 50% elapsed
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let usage = UsageResponse.fixture(
            sevenDayUtil: 80,
            sevenDayResetsAt: formatter.string(from: resetsAt)
        )
        let (store, _, _, _) = makeSUT(usage: usage)

        await store.refresh()

        #expect(store.pacingResult != nil)
        #expect(store.pacingZone == .hot)
        #expect(store.pacingDelta > 0)
    }

    // MARK: - loadCached — skipping for now (cachedUsage uses SharedFileService directly, will be refactored in Task 7)

    // MARK: - reloadConfig

    @Test("reloadConfig resets error state and triggers refresh")
    func reloadConfigResetsAndRefreshes() async throws {
        let (store, repo, keychain, notif) = makeSUT(token: "dead", shouldFail: true, failWith: .tokenExpired)

        // First: put store in error state
        await store.refresh()
        #expect(store.hasError == true)

        // Now fix the repo and call reloadConfig
        repo.stubbedError = nil
        repo.stubbedUsage = .fixture(fiveHourUtil: 55)
        keychain.storedToken = "new-token"
        store.reloadConfig()

        // reloadConfig triggers an async refresh — wait a moment for it
        try await Task.sleep(for: .milliseconds(100))

        #expect(store.errorState == .none)
        #expect(notif.permissionRequested == true)
    }

    // MARK: - startAutoRefresh / stopAutoRefresh

    @Test("stopAutoRefresh cancels the refresh loop")
    func stopAutoRefreshCancelsLoop() async throws {
        let (store, _, _, _) = makeSUT()

        store.startAutoRefresh(interval: 0.05)
        try await Task.sleep(for: .milliseconds(30))
        store.stopAutoRefresh()

        let pctAfterStop = store.fiveHourPct
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.fiveHourPct == pctAfterStop)
    }

    // MARK: - connectAutoDetect

    @Test("connectAutoDetect sets hasConfig on success")
    func connectAutoDetectSetsHasConfig() async {
        let (store, _, _, _) = makeSUT()

        let result = await store.connectAutoDetect()

        #expect(result.success == true)
        #expect(store.hasConfig == true)
    }

    @Test("connectAutoDetect does not set hasConfig on failure")
    func connectAutoDetectDoesNotSetHasConfigOnFailure() async {
        let repo = MockUsageRepository()
        let keychain = MockKeychainService()
        keychain.storedToken = nil
        let notif = MockNotificationService()
        let store = UsageStore(repository: repo, keychainService: keychain, notificationService: notif)

        let result = await store.connectAutoDetect()

        #expect(result.success == false)
    }

    // MARK: - refresh — new buckets (opus, cowork)

    @Test("refresh extracts opus and cowork percentages")
    func refreshExtractsNewBuckets() async {
        let usage = UsageResponse(
            fiveHour: .fixture(utilization: 50),
            sevenDay: .fixture(utilization: 40),
            sevenDaySonnet: .fixture(utilization: 30),
            sevenDayOpus: .fixture(utilization: 20),
            sevenDayCowork: .fixture(utilization: 10)
        )
        let (store, _, _, _) = makeSUT(usage: usage)

        await store.refresh()

        #expect(store.opusPct == 20)
        #expect(store.coworkPct == 10)
        #expect(store.hasOpus == true)
        #expect(store.hasCowork == true)
    }

    @Test("refresh sets hasOpus false when bucket nil")
    func refreshNilOpus() async {
        let usage = UsageResponse(fiveHour: .fixture(utilization: 50))
        let (store, _, _, _) = makeSUT(usage: usage)

        await store.refresh()

        #expect(store.hasOpus == false)
        #expect(store.opusPct == 0)
    }

    // MARK: - 429 backoff

    @Test("refresh sets rateLimited and increments backoff on 429")
    func refreshIncrementsBackoffOn429() async {
        let (store, _, _, _) = makeSUT(shouldFail: true, failWith: .rateLimited(retryAfter: nil))

        await store.refresh()

        #expect(store.errorState == .rateLimited)
    }

    @Test("refresh resets backoff on success after 429")
    func refreshResetsBackoffOnSuccess() async {
        let (store, repo, _, _) = makeSUT(shouldFail: true, failWith: .rateLimited(retryAfter: nil))

        // First call: 429
        await store.refresh()
        #expect(store.errorState == .rateLimited)

        // Fix repo and retry (force: auto-refresh always retries after backoff delay)
        repo.stubbedError = nil
        repo.stubbedUsage = .fixture(fiveHourUtil: 50)
        await store.refresh(force: true)

        #expect(store.errorState == .none)
        #expect(store.fiveHourPct == 50)
    }

    // MARK: - refreshProfile

    @Test("refreshProfile updates plan type")
    func refreshProfileSetsPlanType() async {
        let (store, repo, _, _) = makeSUT()
        repo.stubbedProfile = .fixture(hasClaudeMax: false, hasClaudePro: true)

        await store.refresh() // ensure token is synced and lastUpdate set
        await store.refreshProfile()

        #expect(store.planType == .pro)
    }

    @Test("refreshProfile failure does not set error state")
    func refreshProfileFailureSilent() async {
        let (store, repo, _, _) = makeSUT()
        repo.stubbedProfileError = APIError.invalidResponse

        await store.refreshProfile()

        #expect(store.errorState == .none)
        #expect(store.planType == .unknown)
    }
}
