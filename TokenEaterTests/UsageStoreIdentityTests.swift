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

    @Test("the identity digest is read fresh every time, the sources first")
    func freshIdentityDigest() async {
        let sut = makeSUT()
        sut.repo.stubbedProfile = .fixture(accountUUID: "a-uuid", orgUUID: "o-uuid", email: "lea@studio.fr")
        let expected = ClaudeConfigDirResolver.identityDigest(accountUUID: "a-uuid", organizationUUID: "o-uuid")
        #expect(await sut.store.freshIdentityDigest() == expected)
        #expect(await sut.store.freshIdentityDigest() == expected)
        #expect(sut.repo.fetchProfileCallCount == 2)
        #expect(sut.provider.refreshTokenIfChangedCallCount == 2)
        #expect(sut.store.maskedEmail == "l•••@studio.fr")
    }

    @Test("no token, no profile, no digest")
    func freshIdentityDigestWithoutToken() async {
        let sut = makeSUT(token: nil)
        #expect(await sut.store.freshIdentityDigest() == nil)
        #expect(sut.repo.fetchProfileCallCount == 0)
    }

    @Test("with the gate on, a fresh digest is answered without taking the profile in")
    func freshIdentityDigestUnderGate() async {
        let sut = makeSUT()
        sut.store.identityGate = { _ in .accepted }
        sut.repo.stubbedProfile = .fixture(accountUUID: "a-uuid", orgUUID: "o-uuid", email: "lea@studio.fr")
        #expect(await sut.store.freshIdentityDigest() != nil)
        #expect(sut.store.maskedEmail == nil)
    }

    @Test("moving to another folder forgets the previous login's identity and email")
    func reconfigureForgetsIdentity() async {
        let sut = makeSUT()
        _ = await sut.store.freshIdentityDigest()
        #expect(sut.store.maskedEmail != nil)
        sut.store.reconfigure(scope: .configDir(path: "/Users/x/.claude-y", service: "Claude Code-credentials-00000000"))
        #expect(sut.store.maskedEmail == nil)
        #expect(sut.store.lastIdentityDigest == nil)
    }

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

    @Test("a refused profile takes the 401 path without fetching or writing any usage")
    func unauthorizedProfileFallsThrough() async {
        let sut = makeSUT()
        sut.repo.stubbedProfileError = APIError.tokenExpired(endpoint: "/api/oauth/profile", statusCode: 403)
        sut.store.identityGate = { _ in .accepted }
        await sut.store.refresh(force: true)
        #expect(sut.repo.refreshCallCount == 0)
        #expect(sut.repo.saveCallCount == 0)
        #expect(sut.store.lastUpdate == nil)
        #expect(sut.store.errorState == .tokenUnavailable)
        #expect(sut.provider.invalidateCallCount == 1)
    }

    @Test("a login in conflict never shows the other login's profile")
    func conflictKeepsProfileOut() async {
        let sut = makeSUT()
        sut.repo.stubbedProfile = .fixture(accountUUID: "a-uuid", orgUUID: "o-uuid", email: "lea@studio.fr")
        sut.store.identityGate = { _ in .changed(newDigest: "x") }
        await sut.store.refresh(force: true)
        #expect(sut.store.identityState == .conflict(.changed(newDigest: "x")))
        #expect(sut.store.maskedEmail == nil)
        #expect(sut.store.planType == .unknown)
        #expect(sut.store.organizationName == nil)
    }

    @Test("with the gate on, the profile refresh waits for a verified token")
    func refreshProfileWaitsForVerification() async {
        let sut = makeSUT()
        sut.store.identityGate = { _ in .changed(newDigest: "x") }
        await sut.store.refreshProfile()
        #expect(sut.repo.fetchProfileCallCount == 0)
        #expect(sut.store.maskedEmail == nil)
    }

    // MARK: - Stopping, moving and retiring while a refresh is out

    @Test("a refresh that comes back after the store moved writes nothing")
    func reconfigureDropsInFlightRefresh() async {
        let sut = makeSUT()
        let store = sut.store
        sut.repo.onFetchUsage = {
            await MainActor.run {
                store.reconfigure(scope: .configDir(path: "/Users/x/.claude-perso", service: "S"))
            }
        }
        await store.refresh(force: true)
        #expect(sut.repo.saveCallCount == 0)
        #expect(store.lastUpdate == nil)
        #expect(store.fiveHourPct == 0)
        #expect(store.sessionSamples.isEmpty)
        #expect(store.isLoading == false)

        // The next refresh is not swallowed by the abandoned one.
        sut.repo.onFetchUsage = nil
        await store.refresh(force: true)
        #expect(sut.repo.saveCallCount == 1)
        #expect(store.lastUpdate != nil)
    }

    @Test("a refresh that comes back after the account was removed writes nothing and alerts nobody")
    func retireDropsInFlightRefresh() async {
        let notifications = MockNotificationService()
        let repo = MockUsageRepository()
        repo.stubbedUsage = .fixture(fiveHourUtil: 97)
        let provider = MockTokenProvider()
        provider.token = "tok"
        let store = UsageStore(
            repository: repo,
            tokenProvider: provider,
            sharedFileService: MockSharedFileService(),
            notificationService: notifications,
            sessionSamplesKey: "UsageStoreIdentityTests.\(UUID().uuidString)",
            reloadWidgets: {}
        )
        var asked = 0
        store.notifTogglesProvider = { asked += 1; return nil }
        repo.onFetchUsage = { await MainActor.run { store.retire() } }
        await store.refresh(force: true)
        #expect(repo.saveCallCount == 0)
        #expect(store.sessionSamples.isEmpty)
        #expect(asked == 0)
        #expect(store.isRetired)

        // Nothing starts it again.
        repo.onFetchUsage = nil
        await store.refresh(force: true)
        store.reloadConfig()
        #expect(repo.refreshCallCount == 1)
    }

    @Test("stopping the store drops the refresh that was out")
    func stopDropsInFlightRefresh() async {
        let sut = makeSUT()
        let store = sut.store
        sut.repo.onFetchUsage = { await MainActor.run { store.stopAutoRefresh() } }
        await store.refresh(force: true)
        #expect(sut.repo.saveCallCount == 0)
        #expect(store.lastUpdate == nil)
    }

    @Test("moving to another folder clears the previous login's numbers from the shared file")
    func reconfigureClearsSharedFile() async {
        let sut = makeSUT()
        sut.file._cachedUsage = CachedUsage(usage: .fixture(fiveHourUtil: 61), fetchDate: Date())
        sut.store.loadCached()
        #expect(sut.store.fiveHourPct == 61)
        sut.store.reconfigure(scope: .configDir(path: "/Users/x/.claude-perso", service: "S"))
        #expect(sut.file.clearUsageCallCount == 1)
        sut.store.loadCached()
        #expect(sut.store.fiveHourPct == 0)
        #expect(sut.store.lastUpdate == nil)
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
