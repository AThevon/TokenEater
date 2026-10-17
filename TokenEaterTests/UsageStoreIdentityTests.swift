import Testing
import Foundation

/// The identity gate only exists from two accounts, so these pin both sides:
/// one account never pays for a profile fetch on the refresh path (cswap,
/// #153), and several never write one login's numbers under another's name.
@Suite("UsageStore identity and scope")
@MainActor
struct UsageStoreIdentityTests {

    private func makeSUT(
        token: String? = "tok-1",
        reloads: ReloadCounter = ReloadCounter()
    ) -> (store: UsageStore, repo: MockUsageRepository, provider: MockTokenProvider, file: MockSharedFileService) {
        let repo = MockUsageRepository()
        repo.stubbedUsage = .fixture()
        let provider = MockTokenProvider()
        provider.token = token
        let file = MockSharedFileService()
        let store = UsageStore(
            repository: repo,
            tokenProvider: provider,
            sharedFileService: file,
            notificationService: MockNotificationService(),
            sessionSamplesKey: "UsageStoreIdentityTests.\(UUID().uuidString)",
            reloadWidgets: { reloads.count += 1 }
        )
        return (store, repo, provider, file)
    }

    final class ReloadCounter { var count = 0 }

    @Test("without a gate a refresh never fetches the profile")
    func noGateNoProfile() async {
        let sut = makeSUT()
        await sut.store.refresh(force: true)
        #expect(sut.repo.fetchProfileCallCount == 0)
        #expect(sut.repo.refreshCallCount == 1)
        #expect(sut.store.identityState == .unchecked)
    }

    @Test("a login that belongs to another account writes nothing")
    func belongsToStops() async {
        let sut = makeSUT()
        let other = AccountID(rawValue: "acct-other")
        sut.store.identityGate = { _ in .belongsTo(other) }
        await sut.store.refresh(force: true)
        #expect(sut.repo.fetchProfileCallCount == 1)
        #expect(sut.repo.refreshCallCount == 0)
        #expect(sut.store.identityState == .conflict(.belongsTo(other)))
        #expect(sut.store.lastUpdate == nil)
    }

    @Test("an accepted login is checked once per token, then refreshes as usual")
    func acceptedOncePerToken() async {
        let sut = makeSUT()
        var digests: [String] = []
        sut.store.identityGate = { digest in digests.append(digest); return .accepted }
        await sut.store.refresh(force: true)
        await sut.store.refresh(force: true)
        #expect(sut.repo.fetchProfileCallCount == 1)
        #expect(sut.repo.refreshCallCount == 2)
        #expect(sut.store.identityState == .verified)
        #expect(digests == [ClaudeConfigDirResolver.identityDigest(accountUUID: "test-uuid", organizationUUID: "org-uuid")])

        // A rotated token is a new login until proved otherwise.
        sut.provider.token = "tok-2"
        await sut.store.refresh(force: true)
        #expect(sut.repo.fetchProfileCallCount == 2)
        #expect(sut.repo.refreshCallCount == 3)
    }

    @Test("a rate-limited profile leaves the check pending and writes nothing")
    func rateLimitedProfilePends() async {
        let sut = makeSUT()
        sut.repo.stubbedProfileError = APIError.rateLimited(retryAfter: nil, retryAfterRaw: nil, endpoint: "/api/oauth/profile")
        sut.store.identityGate = { _ in .accepted }
        await sut.store.refresh(force: true)
        #expect(sut.store.identityState == .pending)
        #expect(sut.repo.refreshCallCount == 0)
        #expect(sut.file.updateAfterSyncCallCount == 0)
    }

    @Test("a refused token is left to the ordinary 401 path")
    func unauthorizedProfileFallsThrough() async {
        let sut = makeSUT()
        sut.repo.stubbedProfileError = APIError.tokenExpired(endpoint: "/api/oauth/profile", statusCode: 401)
        sut.repo.stubbedError = APIError.tokenExpired(endpoint: "/api/oauth/usage", statusCode: 401)
        sut.store.identityGate = { _ in .accepted }
        await sut.store.refresh(force: true)
        #expect(sut.repo.refreshCallCount == 1)
        #expect(sut.store.errorState == .tokenUnavailable)
    }

    @Test("dropping the gate forgets the verified login")
    func clearingGateResets() async {
        let sut = makeSUT()
        sut.store.identityGate = { _ in .accepted }
        await sut.store.refresh(force: true)
        #expect(sut.store.identityState == .verified)
        sut.store.identityGate = nil
        #expect(sut.store.identityState == .unchecked)
    }

    @Test("reconfiguring drops every number, the samples and the error, and re-scopes the token")
    func reconfigureClears() async {
        let sut = makeSUT()
        await sut.store.refresh(force: true)
        #expect(sut.store.lastUpdate != nil)
        #expect(sut.store.fiveHourPct > 0)

        let scope = CredentialScope.configDir(path: "/Users/x/.claude-perso", service: "S")
        sut.store.reconfigure(scope: scope)
        #expect(sut.provider.reconfigureCallCount == 1)
        #expect(sut.provider.lastScope == scope)
        #expect(sut.store.credentialScope == scope)
        #expect(sut.file.invalidateCacheCallCount >= 1)
        #expect(sut.store.lastUpdate == nil)
        #expect(sut.store.lastUsage == nil)
        #expect(sut.store.fiveHourPct == 0)
        #expect(sut.store.sevenDayPct == 0)
        #expect(sut.store.sessionSamples.isEmpty)
        #expect(sut.store.planType == .unknown)
        #expect(sut.store.pacingResult == nil)
        #expect(sut.store.errorState == .none)
    }

    @Test("the widget reload goes through the closure the store was given")
    func reloadClosure() async {
        let counter = ReloadCounter()
        let sut = makeSUT(reloads: counter)
        await sut.store.refresh(force: true)
        #expect(counter.count == 1)
        sut.store.reloadConfig()
        #expect(counter.count >= 2)
    }

    @Test("hasTokenSource asks the store's own provider")
    func hasTokenSourceDelegates() {
        let sut = makeSUT()
        sut.provider._hasTokenSource = false
        #expect(!sut.store.hasTokenSource())
        sut.provider._hasTokenSource = true
        #expect(sut.store.hasTokenSource())
    }
}
