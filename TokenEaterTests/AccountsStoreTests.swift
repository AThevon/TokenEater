import Testing
import Foundation
import Combine

@Suite("AccountsStore", .serialized)
@MainActor
struct AccountsStoreTests {

    private static let suiteName = "AccountsStoreTests"
    private let home = "/Users/tester"

    /// A fresh, empty defaults domain, cleaned before each test.
    private func cleanDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        return defaults
    }

    private final class Runtimes {
        var made: [AccountID: (store: UsageStore, provider: MockTokenProvider, file: MockSharedFileService)] = [:]
    }

    private func makeStore(
        defaults: UserDefaults,
        mainProvider: MockTokenProvider = MockTokenProvider(),
        mainRepo: MockUsageRepository = MockUsageRepository(),
        notifications: MockNotificationService = MockNotificationService()
    ) -> (store: AccountsStore, main: UsageStore, mainProvider: MockTokenProvider, runtimes: Runtimes) {
        let main = UsageStore(
            repository: mainRepo,
            tokenProvider: mainProvider,
            sharedFileService: MockSharedFileService(),
            notificationService: MockNotificationService(),
            sessionSamplesKey: "AccountsStoreTests.main",
            reloadWidgets: {}
        )
        let runtimes = Runtimes()
        let store = AccountsStore(mainStore: main, defaults: defaults, home: home, notifications: notifications) { record in
            let provider = MockTokenProvider()
            let file = MockSharedFileService()
            let usage = UsageStore(
                repository: MockUsageRepository(),
                tokenProvider: provider,
                sharedFileService: file,
                notificationService: MockNotificationService(),
                sessionSamplesKey: AccountsStore.sessionSamplesKey(for: record.id),
                reloadWidgets: {}
            )
            runtimes.made[record.id] = (usage, provider, file)
            return AccountRuntime(store: usage, sharedFile: file)
        }
        return (store, main, mainProvider, runtimes)
    }

    private func extra(_ suffix: String, dir: String? = nil, name: String = "Work", digest: String? = nil) -> ClaudeAccountRecord {
        ClaudeAccountRecord(
            id: AccountID(rawValue: "acct-\(suffix)"),
            configDir: dir ?? "/Users/tester/.claude-\(suffix)",
            service: "Claude Code-credentials-\(suffix)",
            name: name,
            colorHex: "#6366F1",
            identityDigest: digest
        )
    }

    // MARK: - Loading

    @Test("with no stored list there is one main account and nothing is written")
    func defaultsToMainOnly() {
        let defaults = cleanDefaults()
        let sut = makeStore(defaults: defaults)
        #expect(sut.store.records.map(\.id) == [.main])
        #expect(sut.store.runtimes.isEmpty)
        #expect(!sut.store.tracksMultipleAccounts)
        #expect(!sut.store.showsAccountMarkers)
        #expect(sut.store.usageStore(for: .main) === sut.main)
        #expect(defaults.data(forKey: ClaudeAccountsStorage.defaultsKey) == nil)
    }

    @Test("an added account persists and reloads in order, main first")
    func addPersists() {
        let defaults = cleanDefaults()
        let sut = makeStore(defaults: defaults)
        #expect(sut.store.add(extra("a")))
        #expect(sut.store.add(extra("b", name: "Side")))

        let reloaded = AccountsStore.loadRecords(from: defaults)
        #expect(reloaded.map(\.id.rawValue) == ["main", "acct-a", "acct-b"])
        #expect(reloaded[2].name == "Side")
        #expect(sut.store.runtimes.count == 2)
        #expect(sut.store.usageStore(for: AccountID(rawValue: "acct-a")) === sut.runtimes.made[AccountID(rawValue: "acct-a")]?.store)
        #expect(sut.store.allStores.count == 3)
    }

    @Test("a duplicate id, a folder already tracked, or the main id is refused")
    func addRefusesDuplicates() {
        let defaults = cleanDefaults()
        let sut = makeStore(defaults: defaults)
        #expect(sut.store.add(extra("a")))
        #expect(!sut.store.add(extra("a", dir: "/Users/tester/.claude-other")))
        #expect(!sut.store.add(extra("b", dir: "/Users/tester/.claude-a/")))
        #expect(!sut.store.add(extra("c", dir: "~/.claude")))
        var main = extra("d")
        main = ClaudeAccountRecord(id: .main, configDir: main.configDir, name: "X", colorHex: "#5B8DEF")
        #expect(!sut.store.add(main))
        #expect(sut.store.records.count == 2)
    }

    @Test("an added account is handed to configureStore with its position")
    func addConfiguresStore() {
        let defaults = cleanDefaults()
        let sut = makeStore(defaults: defaults)
        var configured: [(AccountID, Int, Int)] = []
        sut.store.configureStore = { _, record, index, count in configured.append((record.id, index, count)) }
        sut.store.add(extra("a"))
        sut.store.add(extra("b"))
        #expect(configured.map(\.0.rawValue) == ["acct-a", "acct-b"])
        #expect(configured.map(\.1) == [1, 2])
        #expect(configured.map(\.2) == [2, 3])

        configured.removeAll()
        sut.store.configureAll()
        #expect(configured.map(\.1) == [1, 2])
        #expect(configured.allSatisfy { $0.2 == 3 })
    }

    @Test("pausing is ignored for the main account and persisted for an added one")
    func pausing() {
        let defaults = cleanDefaults()
        let sut = makeStore(defaults: defaults)
        sut.store.setPaused(true, for: .main)
        #expect(!sut.store.records[0].isPaused)
        #expect(defaults.data(forKey: ClaudeAccountsStorage.defaultsKey) == nil)

        sut.store.add(extra("a"))
        sut.store.setPaused(true, for: AccountID(rawValue: "acct-a"))
        #expect(sut.store.activeAccountIDs == [.main])
        #expect(!sut.store.showsAccountMarkers)
        #expect(sut.store.tracksMultipleAccounts)
        #expect(AccountsStore.loadRecords(from: defaults)[1].isPaused)
        // Paused keeps its store, for its last numbers.
        #expect(sut.store.runtimes[AccountID(rawValue: "acct-a")] != nil)
    }

    @Test("update edits name and colour but never the folder or the identity")
    func updateKeepsFolder() {
        let defaults = cleanDefaults()
        let sut = makeStore(defaults: defaults)
        sut.store.add(extra("a", digest: "d1"))
        let id = AccountID(rawValue: "acct-a")
        sut.store.update(id) { record in
            record.name = "  A much too long name  "
            record.colorHex = "f472b6"
            record.configDir = "/elsewhere"
            record.identityDigest = "forged"
            record.notificationsEnabled = false
        }
        let record = sut.store.record(for: id)
        #expect(record?.name == "A much too l")
        #expect(record?.colorHex == "#F472B6")
        #expect(record?.configDir == "/Users/tester/.claude-a")
        #expect(record?.identityDigest == "d1")
        #expect(record?.notificationsEnabled == false)
    }

    // MARK: - Removal

    @Test("removing an account drops its record, store, samples and file, then says so")
    func removePurges() throws {
        let defaults = cleanDefaults()
        let sut = makeStore(defaults: defaults)
        sut.store.add(extra("rm"))
        let id = AccountID(rawValue: "acct-rm")
        let file = try #require(sut.runtimes.made[id]?.file)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shared-acct-rm-\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: url)
        file.fileURL = url
        UserDefaults.standard.set(Data("[]".utf8), forKey: AccountsStore.sessionSamplesKey(for: id))
        UserDefaults.standard.set(true, forKey: "claudeTokenAlertSent.acct-rm")
        UserDefaults.standard.set(true, forKey: "claudeTokenAlertSent.acct-rmx")
        defer { UserDefaults.standard.removeObject(forKey: "claudeTokenAlertSent.acct-rmx") }

        var removed: [AccountID] = []
        let cancellable = sut.store.accountRemoved.sink { removed.append($0) }
        defer { cancellable.cancel() }
        sut.store.remove(id)

        #expect(sut.store.records.map(\.id) == [.main])
        #expect(sut.store.runtimes[id] == nil)
        #expect(UserDefaults.standard.data(forKey: AccountsStore.sessionSamplesKey(for: id)) == nil)
        #expect(UserDefaults.standard.object(forKey: "claudeTokenAlertSent.acct-rm") == nil)
        // Another account whose id merely starts the same is left alone.
        #expect(UserDefaults.standard.bool(forKey: "claudeTokenAlertSent.acct-rmx"))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(removed == [id])
        #expect(AccountsStore.loadRecords(from: defaults).map(\.id) == [.main])
    }

    @Test("a pause drops the account's pending reminders; a removal sweeps its banners too")
    func notificationsFollowPauseAndRemoval() {
        let defaults = cleanDefaults()
        let notifications = MockNotificationService()
        let sut = makeStore(defaults: defaults, notifications: notifications)
        sut.store.add(extra("n"))
        let id = AccountID(rawValue: "acct-n")

        sut.store.setPaused(true, for: id)
        #expect(notifications.purges.map(\.account) == [id])
        #expect(notifications.purges.map(\.includingDelivered) == [false])

        // Resuming leaves its alerts alone.
        sut.store.setPaused(false, for: id)
        #expect(notifications.purges.count == 1)

        sut.store.remove(id)
        #expect(notifications.purges.map(\.account) == [id, id])
        #expect(notifications.purges.last?.includingDelivered == true)
    }

    @Test("switching an account's alerts off drops its pending reminders, on leaves them")
    func notificationSwitchPurgesPending() {
        let defaults = cleanDefaults()
        let notifications = MockNotificationService()
        let sut = makeStore(defaults: defaults, notifications: notifications)
        sut.store.add(extra("s"))
        let id = AccountID(rawValue: "acct-s")

        sut.store.update(id) { $0.notificationsEnabled = false }
        #expect(notifications.purges.map(\.account) == [id])
        #expect(notifications.purges.first?.includingDelivered == false)
        #expect(AccountsStore.loadRecords(from: defaults)[1].notificationsEnabled == false)

        sut.store.update(id) { $0.notificationsEnabled = true }
        #expect(notifications.purges.count == 1)
    }

    @Test("an account's alerts are named once two accounts run, never before")
    func notificationScopeNames() {
        let defaults = cleanDefaults()
        let sut = makeStore(defaults: defaults)
        let main = sut.store.notificationScope(for: .main)
        #expect(main.displayName() == nil)
        #expect(main.loginCommand() == nil)

        sut.store.add(extra("a", name: "Work"))
        let a = AccountID(rawValue: "acct-a")
        #expect(main.displayName() == "Claude")
        #expect(sut.store.notificationScope(for: a).displayName() == "Work")
        #expect(sut.store.notificationScope(for: a).loginCommand() == "CLAUDE_CONFIG_DIR=~/.claude-a claude")

        // A rename reaches the next alert through the same scope.
        sut.store.update(a) { $0.name = "Job" }
        #expect(sut.store.notificationScope(for: a).displayName() == "Job")

        sut.store.setPaused(true, for: a)
        #expect(main.displayName() == nil)
    }

    @Test("an added account has insights of its own, and removing it deletes its history cache")
    func historyFollowsTheAccount() throws {
        let defaults = cleanDefaults()
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("history-cache.acct-h-\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: cache)
        let main = UsageStore(
            repository: MockUsageRepository(),
            tokenProvider: MockTokenProvider(),
            sharedFileService: MockSharedFileService(),
            notificationService: MockNotificationService(),
            sessionSamplesKey: "AccountsStoreTests.main",
            reloadWidgets: {}
        )
        let store = AccountsStore(mainStore: main, defaults: defaults, home: home, notifications: MockNotificationService()) { record in
            let file = MockSharedFileService()
            let usage = UsageStore(
                repository: MockUsageRepository(),
                tokenProvider: MockTokenProvider(),
                sharedFileService: file,
                notificationService: MockNotificationService(),
                sessionSamplesKey: AccountsStore.sessionSamplesKey(for: record.id),
                reloadWidgets: {}
            )
            let history = ClaudeHistoryRoot(
                account: record.id,
                projectsURL: URL(fileURLWithPath: record.configDir ?? "/").appendingPathComponent("projects"),
                cacheURL: cache
            )
            return AccountRuntime(store: usage, sharedFile: file, history: history)
        }
        store.add(extra("h"))
        let id = AccountID(rawValue: "acct-h")

        #expect(store.insightsStore(for: .main) == nil)
        let insights = try #require(store.insightsStore(for: id))
        #expect(store.insightsStore(for: id) === insights)

        store.remove(id)
        #expect(!FileManager.default.fileExists(atPath: cache.path))
        #expect(store.insightsStore(for: id) == nil)
    }

    @Test("the main account cannot be removed")
    func mainNotRemovable() {
        let defaults = cleanDefaults()
        let sut = makeStore(defaults: defaults)
        sut.store.remove(.main)
        #expect(sut.store.records.map(\.id) == [.main])
        #expect(defaults.data(forKey: ClaudeAccountsStorage.defaultsKey) == nil)
    }

    // MARK: - Identity

    @Test("one account has no gate; two put a gate on every store; removal takes it away")
    func gatesFollowAccountCount() {
        let defaults = cleanDefaults()
        let sut = makeStore(defaults: defaults)
        #expect(sut.main.identityGate == nil)

        sut.store.add(extra("a"))
        let id = AccountID(rawValue: "acct-a")
        #expect(sut.main.identityGate != nil)
        #expect(sut.runtimes.made[id]?.store.identityGate != nil)

        sut.store.remove(id)
        #expect(sut.main.identityGate == nil)
    }

    @Test("the verdict: another account's login, a first capture, its own, a new one")
    func identityVerdicts() {
        let defaults = cleanDefaults()
        let sut = makeStore(defaults: defaults)
        sut.store.add(extra("a", digest: "work"))
        let a = AccountID(rawValue: "acct-a")

        #expect(sut.store.identityVerdict(for: "work", account: .main) == .belongsTo(a))
        #expect(sut.store.identityVerdict(for: "perso", account: .main) == .accepted)
        #expect(sut.store.records[0].identityDigest == "perso")
        #expect(AccountsStore.loadRecords(from: defaults)[0].identityDigest == "perso")
        #expect(sut.store.identityVerdict(for: "perso", account: .main) == .accepted)
        #expect(sut.store.identityVerdict(for: "someone", account: a) == .changed(newDigest: "someone"))

        #expect(!sut.store.acceptIdentity("perso", for: a))
        #expect(sut.store.acceptIdentity("someone", for: a))
        #expect(sut.store.identityVerdict(for: "someone", account: a) == .accepted)
    }

    @Test("with one account the main digest is kept in memory, no gate and no write")
    func singleAccountCapture() async {
        let defaults = cleanDefaults()
        let repo = MockUsageRepository()
        repo.stubbedProfile = .fixture(accountUUID: "acc-1", orgUUID: "org-1")
        let provider = MockTokenProvider()
        provider.token = "tok"
        let sut = makeStore(defaults: defaults, mainProvider: provider, mainRepo: repo)

        await sut.main.refreshProfile()

        let expected = ClaudeConfigDirResolver.identityDigest(accountUUID: "acc-1", organizationUUID: "org-1")
        #expect(sut.store.records[0].identityDigest == expected)
        #expect(sut.main.identityGate == nil)
        #expect(defaults.data(forKey: ClaudeAccountsStorage.defaultsKey) == nil)

        // The captured digest is what a second account is compared against.
        sut.store.add(extra("a", digest: "other"))
        #expect(AccountsStore.loadRecords(from: defaults)[0].identityDigest == expected)
    }

    // MARK: - Main folder (#294)

    @Test("moving the main account reconfigures its store and announces the scope")
    func setMainScopeReconfigures() {
        let defaults = cleanDefaults()
        let provider = MockTokenProvider()
        let sut = makeStore(defaults: defaults, mainProvider: provider)
        var scopes: [CredentialScope] = []
        let cancellable = sut.store.mainScopeChanged.sink { scopes.append($0) }
        defer { cancellable.cancel() }

        #expect(sut.store.setMainScope(configDir: "~/.claude-perso/", service: "Claude Code-credentials-abcd1234"))
        let expected = CredentialScope.configDir(path: "/Users/tester/.claude-perso", service: "Claude Code-credentials-abcd1234")
        #expect(provider.reconfigureCallCount == 1)
        #expect(provider.lastScope == expected)
        #expect(scopes == [expected])
        #expect(AccountsStore.loadRecords(from: defaults)[0].configDir == "/Users/tester/.claude-perso")
        #expect(sut.main.credentialScope == expected)
    }

    @Test("a main folder equal to the default stores nothing, the default chain again")
    func setMainScopeDefault() {
        let defaults = cleanDefaults()
        let provider = MockTokenProvider()
        let sut = makeStore(defaults: defaults, mainProvider: provider)
        sut.store.setMainScope(configDir: "/Users/tester/.claude-perso", service: nil)
        #expect(sut.store.records[0].service == ClaudeConfigDirResolver.serviceCandidates(for: "/Users/tester/.claude-perso", home: home).first)

        sut.store.setMainScope(configDir: "/Users/tester/.claude/", service: nil)
        #expect(sut.store.records[0].configDir == nil)
        #expect(sut.store.records[0].service == nil)
        #expect(provider.lastScope == .defaultChain)
    }

    @Test("the main account cannot move into a folder an added account reads")
    func setMainScopeRefusesTrackedFolder() {
        let defaults = cleanDefaults()
        let provider = MockTokenProvider()
        let sut = makeStore(defaults: defaults, mainProvider: provider)
        sut.store.add(extra("a"))
        #expect(!sut.store.setMainScope(configDir: "/Users/tester/.claude-a", service: nil))
        #expect(provider.reconfigureCallCount == 0)
        #expect(sut.store.records[0].configDir == nil)
    }

    @Test("the mock answers like the store for the same records")
    func mockMatchesStore() {
        let mock = MockAccountsStore(records: [.defaultMain(), extra("a")])
        #expect(mock.tracksMultipleAccounts)
        #expect(mock.showsAccountMarkers)
        mock.records[1].isPaused = true
        #expect(!mock.showsAccountMarkers)
        #expect(mock.activeAccountIDs == [.main])
    }
}
