import Testing
import Foundation

@Suite("UsageStore")
@MainActor
struct UsageStoreTests {

    // MARK: - Helpers

    private func makeSUT(
        isConfigured: Bool = true,
        shouldFail: Bool = false,
        usage: UsageResponse = .fixture()
    ) -> (store: UsageStore, repo: MockUsageRepository, notif: MockNotificationService) {
        let repo = MockUsageRepository()
        repo.isConfiguredValue = isConfigured
        repo.shouldFail = shouldFail
        repo.stubbedUsage = usage
        let notif = MockNotificationService()
        let store = UsageStore(repository: repo, notificationService: notif)
        return (store, repo, notif)
    }

    // MARK: - refresh

    @Test("refresh updates percentages from API")
    func refreshUpdatesPercentages() async {
        let (store, _, _) = makeSUT(usage: .fixture(fiveHourUtil: 42, sevenDayUtil: 65, sonnetUtil: 30))

        await store.refresh()

        #expect(store.fiveHourPct == 42)
        #expect(store.sevenDayPct == 65)
        #expect(store.sonnetPct == 30)
    }

    @Test("refresh sets hasConfig false when not configured")
    func refreshSetsHasConfigFalse() async {
        let (store, _, _) = makeSUT(isConfigured: false)

        await store.refresh()

        #expect(store.hasConfig == false)
    }

    @Test("refresh sets hasError on failure")
    func refreshSetsHasErrorOnFailure() async {
        let (store, _, _) = makeSUT(shouldFail: true)

        await store.refresh()

        #expect(store.hasError == true)
    }

    @Test("refresh calls syncKeychainToken")
    func refreshCallsSyncKeychainToken() async {
        let (store, repo, _) = makeSUT()

        await store.refresh()

        #expect(repo.syncCallCount == 1)
    }

    @Test("refresh checks notification thresholds")
    func refreshChecksNotificationThresholds() async {
        let (store, _, notif) = makeSUT(usage: .fixture(fiveHourUtil: 42, sevenDayUtil: 65, sonnetUtil: 30))

        await store.refresh()

        #expect(notif.lastThresholdCheck?.fiveHour == 42)
        #expect(notif.lastThresholdCheck?.sevenDay == 65)
        #expect(notif.lastThresholdCheck?.sonnet == 30)
    }

    @Test("refresh sets isLoading false after completion")
    func refreshSetsIsLoadingFalseAfterCompletion() async {
        let (store, _, _) = makeSUT()

        await store.refresh()

        #expect(store.isLoading == false)
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
        #expect(store.sevenDayPct == 0)
        #expect(store.sonnetPct == 0)
        #expect(store.lastUpdate == nil)
    }
}
