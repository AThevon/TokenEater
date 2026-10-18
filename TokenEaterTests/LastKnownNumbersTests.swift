import Testing
import Foundation

private let samplesKey = "LastKnownNumbersTests.samples"

/// The suites that write the shared `UserDefaults` clean before each test,
/// never in a teardown (see `SettingsStoreTests`).
private func cleanDefaults() {
    UserDefaults.standard.removeObject(forKey: samplesKey)
}

/// A login that stops answering keeps its last numbers on screen, dated, and
/// never falls back to a blank 0% that reads as a fresh reading. A routine
/// token blip over fresh numbers changes nothing.
@Suite("Last known numbers", .serialized)
@MainActor
struct LastKnownNumbersTests {

    private func makeStore(
        repo: MockUsageRepository,
        token: MockTokenProvider,
        shared: MockSharedFileService = MockSharedFileService()
    ) -> UsageStore {
        cleanDefaults()
        return UsageStore(
            repository: repo,
            tokenProvider: token,
            sharedFileService: shared,
            notificationService: MockNotificationService(),
            sessionSamplesKey: samplesKey,
            reloadWidgets: {}
        )
    }

    private func refusingRepo() -> MockUsageRepository {
        let repo = MockUsageRepository()
        repo.stubbedError = APIError.tokenExpired(endpoint: "/api/oauth/usage", statusCode: 401)
        repo.stubbedProfileError = APIError.tokenExpired(endpoint: "/api/oauth/profile", statusCode: 401)
        return repo
    }

    private func cache(fetchedAt date: Date) -> MockSharedFileService {
        let shared = MockSharedFileService()
        shared._cachedUsage = CachedUsage(
            usage: UsageResponse(
                fiveHour: UsageBucket(utilization: 47, resetsAt: nil),
                sevenDay: UsageBucket(utilization: 71, resetsAt: nil)
            ),
            fetchDate: date
        )
        return shared
    }

    @Test("an expired added account shows its cached numbers, dated, even when a refresh runs first")
    func expiredAccountKeepsDatedNumbers() async {
        let token = MockTokenProvider()
        token.token = "expired"
        token.lastScope = .configDir(path: "/Users/demo/.claude-old", service: "Claude Code-credentials-old")
        let twoDaysAgo = Date().addingTimeInterval(-2 * 86_400)
        let store = makeStore(repo: refusingRepo(), token: token, shared: cache(fetchedAt: twoDaysAgo))

        // No `reloadConfig` first: a token change or a wake can start here.
        await store.refresh(force: true)

        #expect(store.errorState == .tokenUnavailable)
        #expect(store.fiveHourPct == 47)
        #expect(store.sevenDayPct == 71)
        #expect(store.isAwaitingRefresh)
        #expect(store.lastNumbersDate == twoDaysAgo)
        #expect(store.hasNoNumbers == false)
    }

    @Test("a token blip over fresh numbers stays calm: they are not dated")
    func blipOverFreshNumbersIsNotDated() async {
        let token = MockTokenProvider()
        token.token = "expired"
        let minutesAgo = Date().addingTimeInterval(-4 * 60)
        let store = makeStore(repo: refusingRepo(), token: token, shared: cache(fetchedAt: minutesAgo))

        await store.refresh(force: true)

        #expect(store.isAwaitingRefresh)
        #expect(store.lastNumbersDate == nil)
    }

    @Test("numbers turn old past the hour of calm, or at once when the login is known to be expired")
    func lastNumbersRule() {
        let now = Date()
        let fresh = now.addingTimeInterval(-10 * 60)
        let stale = now.addingTimeInterval(-TokenExpiryPolicy.escalationDelay - 60)
        func rule(_ awaiting: Bool, _ last: Date?, _ expiredSince: Date?) -> Date? {
            UsageStore.lastNumbersDate(isAwaitingRefresh: awaiting, lastUpdate: last,
                                       loginExpiredSince: expiredSince, now: now)
        }
        #expect(rule(false, stale, nil) == nil)
        #expect(rule(true, nil, nil) == nil)
        #expect(rule(true, fresh, nil) == nil)
        #expect(rule(true, stale, nil) == stale)
        #expect(rule(true, fresh, now.addingTimeInterval(-2 * 3600)) == fresh)
    }

    @Test("a refused login with no cache has no numbers, rather than a 0%")
    func refusedLoginWithoutCacheHasNoNumbers() async {
        let token = MockTokenProvider()
        token.token = "expired"
        let store = makeStore(repo: refusingRepo(), token: token)

        await store.refresh(force: true)

        #expect(store.errorState == .tokenUnavailable)
        #expect(store.lastUsage == nil)
        #expect(store.hasNoNumbers)
        #expect(store.lastNumbersDate == nil)
    }

    @Test("live numbers are not dated")
    func liveNumbersAreNotDated() async {
        let repo = MockUsageRepository()
        repo.stubbedUsage = UsageResponse(fiveHour: UsageBucket(utilization: 10, resetsAt: nil))
        let token = MockTokenProvider()
        token.token = "t"
        let store = makeStore(repo: repo, token: token)
        await store.refresh(force: true)
        #expect(store.lastNumbersDate == nil)
        #expect(store.hasNoNumbers == false)
    }
}
