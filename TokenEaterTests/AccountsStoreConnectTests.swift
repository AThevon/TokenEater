import Testing
import Foundation

@Suite("AccountsStore connect", .serialized)
@MainActor
struct AccountsStoreConnectTests {

    private static let suiteName = "AccountsStoreConnectTests"
    private let home = "/Users/tester"
    private let work = "/Users/tester/.claude-work"
    private let workService = "Claude Code-credentials-0badc0de"

    /// Every provider `connect` built, with the scope it was built for.
    private final class Providers: @unchecked Sendable {
        var made: [(scope: CredentialScope, provider: MockTokenProvider)] = []
        var next: () -> MockTokenProvider = { MockTokenProvider() }
    }

    private struct SUT {
        let store: AccountsStore
        let defaults: UserDefaults
        let mainRepo: MockUsageRepository
        let mainProvider: MockTokenProvider
        let api: MockAPIClient
        let providers: Providers
        let scanner: MockClaudeConfigDirScanner
    }

    private func makeSUT(
        configure: @escaping (MockTokenProvider) -> Void = { $0.token = "work-token" },
        mainProfile: ProfileResponse = .fixture(accountUUID: "main-uuid", orgUUID: "main-org")
    ) -> SUT {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        let mainRepo = MockUsageRepository()
        mainRepo.stubbedProfile = mainProfile
        let mainProvider = MockTokenProvider()
        mainProvider.token = "main-token"
        let main = UsageStore(
            repository: mainRepo,
            tokenProvider: mainProvider,
            sharedFileService: MockSharedFileService(),
            notificationService: MockNotificationService(),
            sessionSamplesKey: "AccountsStoreConnectTests.main",
            reloadWidgets: {}
        )
        let providers = Providers()
        providers.next = {
            let provider = MockTokenProvider()
            configure(provider)
            return provider
        }
        let api = MockAPIClient()
        api.stubbedProfile = .fixture(accountUUID: "work-uuid", orgUUID: "work-org", email: "maya@acme.com", orgName: "Acme")
        let scanner = MockClaudeConfigDirScanner()
        let store = AccountsStore(
            mainStore: main,
            defaults: defaults,
            home: home,
            scanner: scanner,
            makeConnectTokenProvider: { scope in
                let provider = providers.next()
                providers.made.append((scope, provider))
                return provider
            },
            apiClient: api,
            notifications: MockNotificationService()
        ) { record in
            let file = MockSharedFileService()
            let usage = UsageStore(
                repository: MockUsageRepository(),
                tokenProvider: MockTokenProvider(),
                sharedFileService: file,
                notificationService: MockNotificationService(),
                sessionSamplesKey: AccountsStore.sessionSamplesKey(for: record.id),
                reloadWidgets: {}
            )
            return AccountRuntime(store: usage, sharedFile: file)
        }
        return SUT(store: store, defaults: defaults, mainRepo: mainRepo, mainProvider: mainProvider,
                   api: api, providers: providers, scanner: scanner)
    }

    private var workDigest: String {
        ClaudeConfigDirResolver.identityDigest(accountUUID: "work-uuid", organizationUUID: "work-org")
    }

    private var workCommand: String { "CLAUDE_CONFIG_DIR=~/.claude-work claude" }

    // MARK: - Outcomes

    @Test("a folder with a live login is identified once and nothing is fetched beyond its profile")
    func ready() async throws {
        let sut = makeSUT()
        let result = await sut.store.connect(configDir: "~/.claude-work/", knownService: workService)
        guard case .ready(let pending) = result else {
            Issue.record("expected ready, got \(result)")
            return
        }
        #expect(pending.configDir == work)
        #expect(pending.service == workService)
        #expect(pending.digest == workDigest)
        #expect(pending.plan == .pro)
        #expect(pending.organizationName == "Acme")
        #expect(pending.maskedEmail == "m•••@acme.com")
        #expect(pending.proposedName == "Work")
        #expect(pending.proposedColorHex == AccountPalette.presets[1])

        // One provider, bounded to the folder, read exactly once.
        #expect(sut.providers.made.count == 1)
        #expect(sut.providers.made[0].scope == .configDir(path: work, service: workService))
        #expect(sut.providers.made[0].provider.currentTokenCallCount == 1)
        #expect(sut.api.fetchProfileCallCount == 1)
        #expect(sut.api.lastProfileToken == "work-token")
        #expect(sut.api.fetchCallCount == 0)
        // Nothing is added before the user names it.
        #expect(sut.store.records.count == 1)
        #expect(sut.defaults.data(forKey: ClaudeAccountsStorage.defaultsKey) == nil)
    }

    @Test("without a known service the folder is inspected first, attributes only")
    func inspectsWhenServiceUnknown() async {
        let sut = makeSUT()
        sut.scanner.inspected[work] = MockClaudeConfigDirScanner.candidate(work, service: workService)
        let result = await sut.store.connect(configDir: work)
        #expect(sut.scanner.inspectCallCount == 1)
        #expect(sut.providers.made.first?.scope == .configDir(path: work, service: workService))
        if case .ready = result {} else { Issue.record("expected ready, got \(result)") }
    }

    @Test("no login at all gives the command that creates one")
    func noLogin() async {
        let sut = makeSUT(configure: { provider in
            provider.token = nil
            provider.tokenDiagnostic = TokenDiagnostic(source: nil, keychainFailure: .notFound)
        })
        #expect(await sut.store.connect(configDir: work, knownService: workService) == .noLogin(command: workCommand))
        #expect(sut.api.fetchProfileCallCount == 0)
    }

    @Test("a refused Keychain read says so")
    func accessDenied() async {
        let sut = makeSUT(configure: { provider in
            provider.token = nil
            provider.tokenDiagnostic = TokenDiagnostic(source: nil, keychainFailure: .accessDenied)
        })
        #expect(await sut.store.connect(configDir: work, knownService: workService) == .accessDenied)
    }

    @Test("a Keychain read that never answered says so")
    func timedOut() async {
        let sut = makeSUT(configure: { provider in
            provider.token = nil
            provider.tokenDiagnostic = TokenDiagnostic(source: nil, keychainFailure: .timedOut)
        })
        #expect(await sut.store.connect(configDir: work, knownService: workService) == .timedOut)
    }

    @Test("an expired login is refused with the command that renews it")
    func expired() async {
        let sut = makeSUT()
        sut.api.stubbedProfileError = APIError.tokenExpired(endpoint: "/api/oauth/profile", statusCode: 401)
        #expect(await sut.store.connect(configDir: work, knownService: workService) == .expired(command: workCommand))
        #expect(sut.store.records.count == 1)
    }

    @Test("a profile that cannot be fetched is a network failure")
    func network() async {
        let sut = makeSUT()
        let error = APIError.networkError(endpoint: "/api/oauth/profile", underlying: "offline")
        sut.api.stubbedProfileError = error
        #expect(await sut.store.connect(configDir: work, knownService: workService) == .network(error.localizedDescription))
    }

    @Test("a folder already tracked is refused before anything is read")
    func alreadyTracked() async {
        let sut = makeSUT()
        #expect(await sut.store.connect(configDir: "~/.claude/") == .alreadyTracked)
        #expect(sut.providers.made.isEmpty)
        #expect(sut.scanner.inspectCallCount == 0)
    }

    @Test("a second copy of the main account is refused, and the main identity is captured on the way")
    func duplicateOfMain() async {
        let sut = makeSUT(mainProfile: .fixture(accountUUID: "work-uuid", orgUUID: "work-org"))
        #expect(sut.store.records[0].identityDigest == nil)
        let result = await sut.store.connect(configDir: work, knownService: workService)
        #expect(result == .duplicate(of: sut.store.records[0].summary))
        #expect(sut.mainRepo.fetchProfileCallCount == 1)
        #expect(sut.store.records[0].identityDigest == workDigest)
    }

    @Test("a known main identity is not fetched again")
    func mainDigestNotRefetched() async {
        let sut = makeSUT()
        _ = await sut.store.connect(configDir: work, knownService: workService)
        _ = await sut.store.connect(configDir: work, knownService: workService)
        #expect(sut.mainRepo.fetchProfileCallCount == 1)
    }

    @Test("a second copy of an added account is refused with its name")
    func duplicateOfAdded() async {
        let sut = makeSUT()
        let side = ClaudeAccountRecord(
            id: AccountID(rawValue: "acct-side"),
            configDir: "/Users/tester/.claude-side",
            service: "Claude Code-credentials-5eed5eed",
            name: "Side",
            colorHex: "#22D3EE",
            identityDigest: workDigest
        )
        sut.store.add(side)
        let result = await sut.store.connect(configDir: work, knownService: workService)
        #expect(result == .duplicate(of: sut.store.record(for: side.id)!.summary))
    }

    // MARK: - Commit

    @Test("committing adds the account under its chosen name and turns the identity check on")
    func commitAddsAndGates() async throws {
        let sut = makeSUT()
        guard case .ready(let pending) = await sut.store.connect(configDir: work, knownService: workService) else {
            Issue.record("connect did not succeed")
            return
        }
        let record = try #require(sut.store.commit(pending, name: "  Work account long name ", colorHex: "#f472b6"))
        #expect(record.name == "Work account")
        #expect(record.colorHex == "#F472B6")
        #expect(record.configDir == work)
        #expect(record.service == workService)
        #expect(record.identityDigest == workDigest)
        #expect(!record.isPaused)
        #expect(record.notificationsEnabled)
        #expect(sut.store.records.map(\.id) == [.main, record.id])
        #expect(sut.store.mainStore.identityGate != nil)
        #expect(sut.store.usageStore(for: record.id)?.identityGate != nil)
        // The main account's identity, kept in memory so far, is now stored.
        #expect(AccountsStore.loadRecords(from: sut.defaults)[0].identityDigest != nil)
    }

    @Test("no email reaches the stored account list")
    func noEmailPersisted() async throws {
        let sut = makeSUT()
        guard case .ready(let pending) = await sut.store.connect(configDir: work, knownService: workService) else {
            Issue.record("connect did not succeed")
            return
        }
        sut.store.commit(pending, name: pending.proposedName, colorHex: pending.proposedColorHex)
        let data = try #require(sut.defaults.data(forKey: ClaudeAccountsStorage.defaultsKey))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("@"))
        #expect(!text.contains("work-uuid"))
        #expect(!text.contains("Acme"))
    }

    @Test("a pending account whose login got tracked meanwhile is not committed twice")
    func commitRefusesDuplicate() async throws {
        let sut = makeSUT()
        guard case .ready(let pending) = await sut.store.connect(configDir: work, knownService: workService) else {
            Issue.record("connect did not succeed")
            return
        }
        #expect(sut.store.commit(pending, name: "Work", colorHex: "#6366F1") != nil)
        #expect(sut.store.commit(pending, name: "Work", colorHex: "#6366F1") == nil)
        #expect(sut.store.records.count == 2)
    }
    // MARK: - Main account folder (#294)

    private let perso = "/Users/tester/.claude-perso"
    private let persoService = "Claude Code-credentials-5eedf00d"

    @Test("moving the main account checks the folder's login, then follows it everywhere")
    func mainFolderMoves() async {
        let sut = makeSUT()
        var announced: [CredentialScope] = []
        let cancellable = sut.store.mainScopeChanged.sink { announced.append($0) }
        defer { cancellable.cancel() }

        let result = await sut.store.setMainConfigDir("~/.claude-perso", knownService: persoService)
        let expected = CredentialScope.configDir(path: perso, service: persoService)
        #expect(result == .moved(expected))
        #expect(sut.providers.made.count == 1)
        #expect(sut.providers.made[0].provider.currentTokenCallCount == 1)
        #expect(sut.mainProvider.reconfigureCallCount == 1)
        #expect(sut.mainProvider.lastScope == expected)
        #expect(announced == [expected])
        #expect(sut.store.records[0].identityDigest == workDigest)
        // "Claude" was only the default folder's proposal, so it follows.
        #expect(sut.store.records[0].name == "Perso")
        #expect(AccountsStore.loadRecords(from: sut.defaults)[0].configDir == perso)
    }

    @Test("a name the user chose stays when the main folder moves")
    func mainFolderKeepsChosenName() async {
        let sut = makeSUT()
        sut.store.update(.main) { $0.name = "Maya" }
        _ = await sut.store.setMainConfigDir(perso, knownService: persoService)
        #expect(sut.store.records[0].name == "Maya")
    }

    @Test("going back to ~/.claude restores the default chain without reading anything")
    func mainFolderBackToDefault() async {
        let sut = makeSUT()
        _ = await sut.store.setMainConfigDir(perso, knownService: persoService)
        #expect(await sut.store.setMainConfigDir(nil) == .moved(.defaultChain))
        #expect(sut.store.records[0].configDir == nil)
        #expect(sut.store.records[0].service == nil)
        #expect(sut.store.records[0].name == "Claude")
        #expect(sut.mainProvider.lastScope == .defaultChain)
        #expect(sut.providers.made.count == 1)

        // Picking ~/.claude itself, with its login under the base service, is the same.
        _ = await sut.store.setMainConfigDir(perso, knownService: persoService)
        let back = await sut.store.setMainConfigDir("~/.claude", knownService: ClaudeConfigDirResolver.baseService)
        #expect(back == .moved(.defaultChain))
        #expect(sut.store.records[0].configDir == nil)
    }

    @Test("~/.claude with a suffixed login is kept as a folder of its own")
    func mainFolderExplicitDefault() async {
        let sut = makeSUT()
        let suffixed = ClaudeConfigDirResolver.service(forHashInput: "/Users/tester/.claude")
        let result = await sut.store.setMainConfigDir("/Users/tester/.claude", knownService: suffixed)
        #expect(result == .moved(.configDir(path: "/Users/tester/.claude", service: suffixed)))
        #expect(sut.store.records[0].configDir == "/Users/tester/.claude")
    }

    @Test("the main account cannot take an added account's login or folder")
    func mainFolderRefusesAddedAccount() async {
        let sut = makeSUT()
        let side = ClaudeAccountRecord(
            id: AccountID(rawValue: "acct-side"),
            configDir: "/Users/tester/.claude-side",
            service: "Claude Code-credentials-5eed5eed",
            name: "Side",
            colorHex: "#22D3EE",
            identityDigest: workDigest
        )
        sut.store.add(side)
        #expect(await sut.store.setMainConfigDir("~/.claude-side") == .refused(.alreadyTracked))
        let duplicate = await sut.store.setMainConfigDir(perso, knownService: persoService)
        #expect(duplicate == .refused(.duplicate(of: sut.store.record(for: side.id)!.summary)))
        #expect(sut.mainProvider.reconfigureCallCount == 0)
        #expect(sut.store.records[0].configDir == nil)
    }

    @Test("an expired login in the new folder changes nothing")
    func mainFolderRefusesExpired() async {
        let sut = makeSUT()
        sut.api.stubbedProfileError = APIError.tokenExpired(endpoint: "/api/oauth/profile", statusCode: 401)
        let result = await sut.store.setMainConfigDir(perso, knownService: persoService)
        #expect(result == .refused(.expired(command: "CLAUDE_CONFIG_DIR=~/.claude-perso claude")))
        #expect(sut.mainProvider.reconfigureCallCount == 0)
        #expect(sut.defaults.data(forKey: ClaudeAccountsStorage.defaultsKey) == nil)
    }
}
