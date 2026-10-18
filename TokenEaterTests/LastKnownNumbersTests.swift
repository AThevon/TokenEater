import Testing
import Foundation

/// A login that stops answering keeps its last numbers on screen, dated, and
/// never falls back to a blank 0% that reads as a fresh reading.
@Suite("Last known numbers")
@MainActor
struct LastKnownNumbersTests {

    @Test("an expired added account shows its cached numbers, dated, even when a refresh runs first")
    func expiredAccountKeepsDatedNumbers() async {
        let repo = MockUsageRepository()
        repo.stubbedError = APIError.tokenExpired(endpoint: "/api/oauth/usage", statusCode: 401)
        repo.stubbedProfileError = APIError.tokenExpired(endpoint: "/api/oauth/profile", statusCode: 401)
        let token = MockTokenProvider()
        token.token = "expired"
        token.lastScope = .configDir(path: "/Users/demo/.claude-old", service: "Claude Code-credentials-old")
        let shared = MockSharedFileService()
        let twoDaysAgo = Date().addingTimeInterval(-2 * 86_400)
        shared._cachedUsage = CachedUsage(
            usage: UsageResponse(
                fiveHour: UsageBucket(utilization: 47, resetsAt: nil),
                sevenDay: UsageBucket(utilization: 71, resetsAt: nil)
            ),
            fetchDate: twoDaysAgo
        )
        let store = UsageStore(
            repository: repo,
            tokenProvider: token,
            sharedFileService: shared,
            notificationService: MockNotificationService(),
            sessionSamplesKey: "LastKnownNumbersTests.samples",
            reloadWidgets: {}
        )

        // No `reloadConfig` first: a token change or a wake can start here.
        await store.refresh(force: true)

        #expect(store.errorState == .tokenUnavailable)
        #expect(store.fiveHourPct == 47)
        #expect(store.sevenDayPct == 71)
        #expect(store.isAwaitingRefresh)
        #expect(store.lastNumbersDate == twoDaysAgo)
    }

    @Test("live numbers are not dated")
    func liveNumbersAreNotDated() async {
        let repo = MockUsageRepository()
        repo.stubbedUsage = UsageResponse(fiveHour: UsageBucket(utilization: 10, resetsAt: nil))
        let token = MockTokenProvider()
        token.token = "t"
        let store = UsageStore(
            repository: repo,
            tokenProvider: token,
            sharedFileService: MockSharedFileService(),
            notificationService: MockNotificationService(),
            sessionSamplesKey: "LastKnownNumbersTests.samples",
            reloadWidgets: {}
        )
        await store.refresh(force: true)
        #expect(store.lastNumbersDate == nil)
    }
}
