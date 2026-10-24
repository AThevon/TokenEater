import Testing
import Foundation

@Suite("Accounts index for the widget")
struct AccountIndexEntryTests {

    private let work = AccountIndexEntry(id: "acct-work", name: "Work", colorHex: "#6366F1", isPaused: false)
    private let perso = AccountIndexEntry(id: "acct-perso", name: "Perso", colorHex: "#F472B6", isPaused: true)

    @Test("an entry encodes its id, name, colour and pause, nothing else")
    func encodesOnlyFourKeys() throws {
        let record = ClaudeAccountRecord(
            id: AccountID(rawValue: "acct-work"),
            configDir: "/Users/tester/.claude-work",
            service: "Claude Code-credentials-1a2b3c4d",
            name: "Work",
            colorHex: "#6366F1",
            identityDigest: "deadbeef"
        )
        let data = try JSONEncoder().encode(AccountIndexEntry(record))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["id", "name", "colorHex", "isPaused"])
        #expect(object["id"] as? String == "acct-work")
        #expect(object["name"] as? String == "Work")
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("claude-work"))
        #expect(!text.contains("credentials"))
        #expect(!text.contains("deadbeef"))
    }

    @Test("the main fallback is the untouched main account")
    func mainFallback() {
        #expect(AccountIndexEntry.mainFallback == AccountIndexEntry(ClaudeAccountRecord.defaultMain()))
        #expect(AccountIndexEntry.mainFallback.isMain)
        #expect(AccountIndexEntry.index(of: [.defaultMain()]) == [.mainFallback])
    }

    @Test("resolve: nil is the main account, a known id its entry, an unknown id nothing")
    func resolve() {
        let main = AccountIndexEntry(id: "main", name: "Perso", colorHex: "#5B8DEF", isPaused: false)
        let index = [main, work, perso]
        #expect(AccountIndexEntry.resolve(nil, in: index) == main)
        #expect(AccountIndexEntry.resolve("main", in: index) == main)
        #expect(AccountIndexEntry.resolve("acct-work", in: index) == work)
        #expect(AccountIndexEntry.resolve("acct-gone", in: index) == nil)
    }

    @Test("with no index written the widget knows the main account alone")
    func resolveWithoutIndex() {
        #expect(AccountIndexEntry.resolve(nil, in: []) == .mainFallback)
        #expect(AccountIndexEntry.resolve("acct-work", in: []) == nil)
        #expect(AccountIndexEntry.effectiveIndex(nil) == [.mainFallback])
    }

    @Test("an entry whose id this build would never write is ignored")
    func invalidIDsIgnored() {
        let rogue = AccountIndexEntry(id: "../../etc", name: "X", colorHex: "#000000", isPaused: false)
        #expect(rogue.accountID == nil)
        #expect(AccountIndexEntry.resolve("../../etc", in: [.mainFallback, rogue]) == nil)
        #expect(AccountIndexEntry.effectiveIndex([rogue]) == [.mainFallback])
    }

    @Test("the widget state: active, paused, removed, and the file it reads")
    func entryState() {
        let index = [AccountIndexEntry.mainFallback, work, perso]
        #expect(ClaudeAccountEntryState.resolve(id: nil, index: index) == .active(.mainFallback))
        #expect(ClaudeAccountEntryState.resolve(id: "acct-work", index: index) == .active(work))
        #expect(ClaudeAccountEntryState.resolve(id: "acct-perso", index: index) == .paused(perso))
        #expect(ClaudeAccountEntryState.resolve(id: "acct-gone", index: index) == .removed)
        #expect(ClaudeAccountEntryState.resolve(id: nil, index: nil) == .active(.mainFallback))
        #expect(ClaudeAccountEntryState.resolve(id: "acct-work", index: nil) == .removed)

        #expect(ClaudeAccountEntryState.active(.mainFallback).sharedFileName == "shared.json")
        #expect(ClaudeAccountEntryState.active(work).sharedFileName == "shared-acct-work.json")
        #expect(ClaudeAccountEntryState.removed.sharedFileName == nil)
    }

    @Test("a paused flag on the main entry never reads as paused")
    func mainNeverPaused() {
        let main = AccountIndexEntry(id: "main", name: "Claude", colorHex: "#5B8DEF", isPaused: true)
        #expect(ClaudeAccountEntryState.resolve(id: nil, index: [main]) == .active(main))
    }

    @Test("the per-account file names match the ones the stores write")
    func sharedFileNames() {
        #expect(AccountID.main.sharedFileName == "shared.json")
        #expect(AccountID(rawValue: "acct-1234").sharedFileName == "shared-acct-1234.json")
    }

    // MARK: - Stored shape

    private struct Envelope: Codable {
        var cachedUsage: Int?
        var accountsIndex: StoredAccountsIndex?
    }

    @Test("an unreadable entry is dropped, its siblings kept")
    func lossyEntries() throws {
        let json = ##"{"cachedUsage": 1, "accountsIndex": [{"id": "main"}, {"id": "acct-work", "name": "Work", "colorHex": "#6366F1", "isPaused": false}]}"##
        let decoded = try JSONDecoder().decode(Envelope.self, from: Data(json.utf8))
        #expect(decoded.cachedUsage == 1)
        #expect(decoded.accountsIndex?.entries == [work])
    }

    @Test("an index of another shape never costs the rest of the file")
    func malformedIndexKeepsTheFile() throws {
        for value in ["42", #""text""#, #"{"a": 1}"#] {
            let json = #"{"cachedUsage": 7, "accountsIndex": "# + value + "}"
            let decoded = try JSONDecoder().decode(Envelope.self, from: Data(json.utf8))
            #expect(decoded.cachedUsage == 7)
            #expect(decoded.accountsIndex?.entries == [])
        }
        let absent = try JSONDecoder().decode(Envelope.self, from: Data(#"{"cachedUsage": 3}"#.utf8))
        #expect(absent.accountsIndex == nil)
    }

    @Test("the stored index encodes as a plain array")
    func storedRoundTrip() throws {
        let data = try JSONEncoder().encode(StoredAccountsIndex([work]))
        let array = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(array.count == 1)
        #expect(try JSONDecoder().decode(StoredAccountsIndex.self, from: data).entries == [work])
    }

    @Test("the account widget's kind is frozen")
    @MainActor
    func accountKindFrozen() {
        #expect(WidgetReloader.accountKind == "ClaudeAccountWidget")
        #expect(WidgetReloader.usageKind == "TokenEaterWidget")
        #expect(WidgetReloader.pacingKind == "PacingWidget")
        #expect(WidgetReloader.codexUsageKind == "CodexUsageWidget")
    }
}

@Suite("AccountsStore writes the widget index", .serialized)
@MainActor
struct AccountsStoreWidgetIndexTests {

    private static let suiteName = "AccountsStoreWidgetIndexTests"
    private let home = "/Users/tester"

    private func cleanDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        return defaults
    }

    private final class Counter {
        var reloads = 0
    }

    private func makeStore(
        defaults: UserDefaults,
        indexFile: MockSharedFileService,
        counter: Counter
    ) -> AccountsStore {
        let main = UsageStore(
            repository: MockUsageRepository(),
            tokenProvider: MockTokenProvider(),
            sharedFileService: MockSharedFileService(),
            notificationService: MockNotificationService(),
            sessionSamplesKey: "AccountsStoreWidgetIndexTests.main",
            reloadWidgets: {}
        )
        return AccountsStore(
            mainStore: main,
            defaults: defaults,
            home: home,
            notifications: MockNotificationService(),
            indexFile: indexFile,
            reloadAccountWidgets: { counter.reloads += 1 }
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
    }

    private func extra(_ suffix: String, name: String = "Work", color: String = "#6366F1") -> ClaudeAccountRecord {
        ClaudeAccountRecord(
            id: AccountID(rawValue: "acct-\(suffix)"),
            configDir: "/Users/tester/.claude-\(suffix)",
            service: "Claude Code-credentials-\(suffix)",
            name: name,
            colorHex: color,
            identityDigest: "digest-\(suffix)"
        )
    }

    @Test("one untouched account writes no index and reloads nothing")
    func singleAccountWritesNothing() {
        let file = MockSharedFileService()
        let counter = Counter()
        let store = makeStore(defaults: cleanDefaults(), indexFile: file, counter: counter)
        #expect(store.records.count == 1)
        #expect(file.updateAccountsIndexCallCount == 0)
        #expect(file.accountsIndex == nil)
        #expect(counter.reloads == 0)
    }

    @Test("adding an account writes main then the account, and reloads the widget")
    func addWritesIndex() {
        let file = MockSharedFileService()
        let counter = Counter()
        let store = makeStore(defaults: cleanDefaults(), indexFile: file, counter: counter)
        store.add(extra("w"))
        #expect(file.accountsIndex == [
            .mainFallback,
            AccountIndexEntry(id: "acct-w", name: "Work", colorHex: "#6366F1", isPaused: false),
        ])
        #expect(counter.reloads == 1)
    }

    @Test("a pause, a rename and a colour change reach the index")
    func changesReachIndex() {
        let file = MockSharedFileService()
        let counter = Counter()
        let store = makeStore(defaults: cleanDefaults(), indexFile: file, counter: counter)
        let id = AccountID(rawValue: "acct-w")
        store.add(extra("w"))

        store.setPaused(true, for: id)
        #expect(file.accountsIndex?.last?.isPaused == true)

        store.update(id) { $0.name = "Client"; $0.colorHex = "#22d3ee" }
        #expect(file.accountsIndex?.last == AccountIndexEntry(id: "acct-w", name: "Client", colorHex: "#22D3EE", isPaused: true))

        store.setPaused(false, for: id)
        #expect(file.accountsIndex?.last?.isPaused == false)
        #expect(counter.reloads == 4)
    }

    @Test("a change the widget cannot see writes nothing")
    func invisibleChangeWritesNothing() {
        let file = MockSharedFileService()
        let counter = Counter()
        let store = makeStore(defaults: cleanDefaults(), indexFile: file, counter: counter)
        let id = AccountID(rawValue: "acct-w")
        store.add(extra("w"))
        let writes = file.updateAccountsIndexCallCount

        store.update(id) { $0.notificationsEnabled = false }
        _ = store.acceptIdentity("digest-new", for: id)
        #expect(file.updateAccountsIndexCallCount == writes)
        #expect(counter.reloads == 1)
    }

    @Test("removing the last added account leaves the main account alone in the index")
    func removeShrinksIndex() {
        let file = MockSharedFileService()
        let counter = Counter()
        let store = makeStore(defaults: cleanDefaults(), indexFile: file, counter: counter)
        store.add(extra("w"))
        store.add(extra("p", name: "Perso", color: "#F472B6"))
        store.remove(AccountID(rawValue: "acct-w"))
        #expect(file.accountsIndex?.map(\.id) == ["main", "acct-p"])
        store.remove(AccountID(rawValue: "acct-p"))
        #expect(file.accountsIndex == [.mainFallback])
    }

    @Test("no identity, folder or service ever reaches the index")
    func noIdentityInIndex() throws {
        let file = MockSharedFileService()
        let store = makeStore(defaults: cleanDefaults(), indexFile: file, counter: Counter())
        store.add(extra("w"))
        let data = try JSONEncoder().encode(file.accountsIndex)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("digest-w"))
        #expect(!text.contains(".claude-w"))
        #expect(!text.contains("credentials"))
    }

    @Test("at launch a stale index is rewritten, a current one left alone")
    func launchSync() {
        let defaults = cleanDefaults()
        let first = MockSharedFileService()
        let store = makeStore(defaults: defaults, indexFile: first, counter: Counter())
        store.add(extra("w"))
        let current = first.accountsIndex

        // Same list on disk: nothing to do.
        let same = MockSharedFileService()
        same._accountsIndex = current
        _ = makeStore(defaults: defaults, indexFile: same, counter: Counter())
        #expect(same.updateAccountsIndexCallCount == 0)

        // The shared folder was wiped while the list stayed in the defaults.
        let wiped = MockSharedFileService()
        let counter = Counter()
        _ = makeStore(defaults: defaults, indexFile: wiped, counter: counter)
        #expect(wiped.accountsIndex == current)
        #expect(counter.reloads == 1)

        // An index left by accounts that are gone shrinks back to the main one.
        let stale = MockSharedFileService()
        stale._accountsIndex = current
        let fresh = makeStore(defaults: cleanDefaults(), indexFile: stale, counter: Counter())
        #expect(fresh.records.count == 1)
        #expect(stale.accountsIndex == [.mainFallback])
    }

    @Test("a main account renamed while alone is written, so the widget names it")
    func renamedMainAlone() {
        let file = MockSharedFileService()
        let store = makeStore(defaults: cleanDefaults(), indexFile: file, counter: Counter())
        store.update(.main) { $0.name = "Perso" }
        #expect(file.accountsIndex?.map(\.name) == ["Perso"])
    }
}
