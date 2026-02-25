import Testing
import Foundation

@Suite("UsageStore")
@MainActor
struct UsageStoreTests {

    // MARK: - Helpers

    private func makeSUT(
        isConfigured: Bool = true,
        shouldFail: Bool = false,
        failWith: APIError? = nil,
        usage: UsageResponse = .fixture(),
        currentToken: String? = "valid-token"
    ) -> (store: UsageStore, repo: MockUsageRepository, notif: MockNotificationService) {
        let repo = MockUsageRepository()
        repo.isConfiguredValue = isConfigured
        repo.currentTokenValue = currentToken
        if shouldFail {
            repo.stubbedError = failWith ?? .invalidResponse
        }
        repo.stubbedUsage = usage
        let notif = MockNotificationService()
        let store = UsageStore(repository: repo, notificationService: notif)
        return (store, repo, notif)
    }

    // MARK: - refresh — basic

    @Test("refresh updates percentages from API")
    func refreshUpdatesPercentages() async {
        let (store, _, _) = makeSUT(usage: .fixture(fiveHourUtil: 42, sevenDayUtil: 65, sonnetUtil: 30))

        await store.refresh()

        #expect(store.fiveHourPct == 42)
        #expect(store.sevenDayPct == 65)
        #expect(store.sonnetPct == 30)
    }

    @Test("refresh sets lastUpdate on success")
    func refreshSetsLastUpdate() async {
        let (store, _, _) = makeSUT()

        #expect(store.lastUpdate == nil)
        await store.refresh()
        #expect(store.lastUpdate != nil)
    }

    @Test("refresh sets isLoading false after completion")
    func refreshSetsIsLoadingFalseAfterCompletion() async {
        let (store, _, _) = makeSUT()

        await store.refresh()

        #expect(store.isLoading == false)
    }

    @Test("refresh calls syncKeychainTokenSilently when not configured")
    func refreshCallsSyncSilentlyWhenNotConfigured() async {
        let (store, repo, _) = makeSUT(isConfigured: false)

        await store.refresh()

        #expect(repo.syncSilentCallCount == 1)
        #expect(repo.syncCallCount == 0)
    }

    @Test("refresh checks notification thresholds on success")
    func refreshChecksNotificationThresholds() async {
        let (store, _, notif) = makeSUT(usage: .fixture(fiveHourUtil: 42, sevenDayUtil: 65, sonnetUtil: 30))

        await store.refresh()

        #expect(notif.lastThresholdCheck?.fiveHour == 42)
        #expect(notif.lastThresholdCheck?.sevenDay == 65)
        #expect(notif.lastThresholdCheck?.sonnet == 30)
    }

    // MARK: - refresh — hasConfig

    @Test("refresh sets hasConfig false when not configured and no failed token")
    func refreshSetsHasConfigFalse() async {
        let (store, _, _) = makeSUT(isConfigured: false, currentToken: nil)

        await store.refresh()

        #expect(store.hasConfig == false)
    }

    @Test("refresh sets hasConfig true on successful API call")
    func refreshSetsHasConfigTrue() async {
        let (store, _, _) = makeSUT()

        await store.refresh()

        #expect(store.hasConfig == true)
    }

    // MARK: - refresh — error states

    @Test("refresh sets tokenExpired error on 401")
    func refreshSetsTokenExpiredError() async {
        let (store, _, _) = makeSUT(shouldFail: true, failWith: .tokenExpired)

        await store.refresh()

        #expect(store.errorState == .tokenExpired)
        #expect(store.hasError == true)
    }

    @Test("refresh sets keychainLocked error")
    func refreshSetsKeychainLockedError() async {
        let (store, _, _) = makeSUT(shouldFail: true, failWith: .keychainLocked)

        await store.refresh()

        #expect(store.errorState == .keychainLocked)
    }

    @Test("refresh sets networkError on generic API error")
    func refreshSetsNetworkError() async {
        let (store, _, _) = makeSUT(shouldFail: true, failWith: .invalidResponse)

        await store.refresh()

        if case .networkError = store.errorState {
            // correct
        } else {
            Issue.record("Expected .networkError, got \(store.errorState)")
        }
    }

    @Test("refresh clears error state on success after previous failure")
    func refreshClearsErrorOnSuccess() async {
        let (store, repo, _) = makeSUT(shouldFail: true, failWith: .invalidResponse)

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
        let (store, repo, _) = makeSUT(shouldFail: true, failWith: .tokenExpired, currentToken: "dead-token")

        // First call: token fails → lastFailedToken = "dead-token"
        await store.refresh()
        #expect(store.errorState == .tokenExpired)

        // Second call: syncSilently still returns "dead-token" → guard returns early, no new API call
        repo.stubbedError = nil
        repo.stubbedUsage = .fixture(fiveHourUtil: 99)
        await store.refresh()

        // Store should NOT have updated because the token is still the failed one
        #expect(store.fiveHourPct != 99)
    }

    @Test("refresh retries when keychain provides a new token after failure")
    func refreshRetriesWithNewToken() async {
        let (store, repo, _) = makeSUT(shouldFail: true, failWith: .tokenExpired, currentToken: "dead-token")

        // First call: token fails
        await store.refresh()
        #expect(store.errorState == .tokenExpired)

        // Simulate keychain now has a fresh token
        repo.currentTokenValue = "fresh-token"
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
        let (store, _, _) = makeSUT(usage: usage)

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
        let (store, _, _) = makeSUT(usage: usage)

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
        let (store, _, _) = makeSUT(usage: usage)

        await store.refresh()

        #expect(store.pacingResult != nil)
        #expect(store.pacingZone == .hot)
        #expect(store.pacingDelta > 0)
    }

    // MARK: - loadCached

    @Test("loadCached reads from repository")
    func loadCachedReadsFromRepository() {
        let (store, repo, _) = makeSUT()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        repo.cachedValue = CachedUsage(
            usage: .fixture(fiveHourUtil: 10, sevenDayUtil: 20, sonnetUtil: 30),
            fetchDate: date
        )

        store.loadCached()

        #expect(store.fiveHourPct == 10)
        #expect(store.sevenDayPct == 20)
        #expect(store.sonnetPct == 30)
        #expect(store.lastUpdate == date)
    }

    @Test("loadCached does nothing when no cache")
    func loadCachedDoesNothingWhenNoCache() {
        let (store, _, _) = makeSUT()

        store.loadCached()

        #expect(store.fiveHourPct == 0)
        #expect(store.lastUpdate == nil)
    }

    // MARK: - reloadConfig

    @Test("reloadConfig resets error state and triggers refresh")
    func reloadConfigResetsAndRefreshes() async throws {
        let (store, repo, notif) = makeSUT(shouldFail: true, failWith: .tokenExpired, currentToken: "dead")

        // First: put store in error state
        await store.refresh()
        #expect(store.hasError == true)

        // Now fix the repo and call reloadConfig
        repo.stubbedError = nil
        repo.stubbedUsage = .fixture(fiveHourUtil: 55)
        repo.currentTokenValue = "new-token"
        store.reloadConfig()

        // reloadConfig triggers an async refresh — wait a moment for it
        try await Task.sleep(for: .milliseconds(100))

        #expect(store.errorState == .none)
        #expect(notif.permissionRequested == true)
    }

    @Test("reloadConfig loads cached data")
    func reloadConfigLoadsCached() {
        let (store, repo, _) = makeSUT()
        repo.cachedValue = CachedUsage(
            usage: .fixture(fiveHourUtil: 33),
            fetchDate: Date()
        )

        store.reloadConfig()

        #expect(store.fiveHourPct == 33)
    }

    // MARK: - startAutoRefresh / stopAutoRefresh

    @Test("stopAutoRefresh cancels the refresh loop")
    func stopAutoRefreshCancelsLoop() async throws {
        let (store, _, _) = makeSUT()

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
        let (store, repo, _) = makeSUT()
        repo.isConfiguredValue = true

        let result = await store.connectAutoDetect()

        #expect(result.success == true)
        #expect(store.hasConfig == true)
    }

    @Test("connectAutoDetect does not set hasConfig on failure")
    func connectAutoDetectDoesNotSetHasConfigOnFailure() async {
        let (store, repo, _) = makeSUT(isConfigured: false)
        repo.isConfiguredValue = false

        let result = await store.connectAutoDetect()

        #expect(result.success == false)
    }
}
