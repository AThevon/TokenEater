import Testing
import Foundation

/// The multi-account demo must be invisible to everyone who never turns it
/// on, and must leave nothing behind once turned off.
@Suite("Demo mode", .serialized)
@MainActor
struct DemoModeTests {

    private static let suiteName = "DemoModeTests"
    private let home = "/Users/tester"

    /// A `codex.json` stand-in at a path of the test's own.
    private final class CodexFile: CodexSharedFileServiceProtocol, @unchecked Sendable {
        let fileURL: URL
        var clearCount = 0
        var enabledCalls: [Bool] = []
        init(url: URL) { fileURL = url }
        var isConfigured: Bool { false }
        var isEnabled: Bool { enabledCalls.last ?? false }
        var cachedUsage: CachedCodexUsage? { nil }
        var pacingMargin: Double { 10 }
        var lastSyncDate: Date? { nil }
        func invalidateCache() {}
        func updateAfterSync(usage: CachedCodexUsage, syncDate: Date) {}
        func updatePacingMargin(_ margin: Double) {}
        func updateEnabled(_ enabled: Bool) { enabledCalls.append(enabled) }
        func clear() { clearCount += 1 }
    }

    private struct Fixture {
        let env: DemoLaunchEnvironment
        let defaults: UserDefaults
        let directory: URL
        let index: MockSharedFileService
        let accountFiles: AccountFiles
        let codex: CodexFile
        let notifications: MockNotificationService
    }

    private final class AccountFiles: @unchecked Sendable {
        var files: [AccountID: MockSharedFileService] = [:]
        func file(_ id: AccountID) -> MockSharedFileService {
            if let file = files[id] { return file }
            let file = MockSharedFileService()
            files[id] = file
            return file
        }
    }

    private func makeFixture(prefs: [String: Any] = [:], index: [AccountIndexEntry]? = nil) throws -> Fixture {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        for (key, value) in prefs { defaults.set(value, forKey: key) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DemoModeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let indexFile = MockSharedFileService()
        indexFile._accountsIndex = index
        let files = AccountFiles()
        let codex = CodexFile(url: directory.appendingPathComponent("codex.json"))
        let notifications = MockNotificationService()
        let env = DemoLaunchEnvironment(
            defaults: defaults,
            domainName: Self.suiteName,
            home: home,
            sharedDirectory: directory,
            indexFile: indexFile,
            accountFile: { files.file($0) },
            codexFile: codex,
            notifications: notifications,
            now: Date(timeIntervalSince1970: 1_790_000_000)
        )
        return Fixture(env: env, defaults: defaults, directory: directory, index: indexFile,
                       accountFiles: files, codex: codex, notifications: notifications)
    }

    private func domain(_ fixture: Fixture) -> NSDictionary {
        NSDictionary(dictionary: fixture.defaults.persistentDomain(forName: Self.suiteName) ?? [:])
    }

    private func files(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    private let realPrefs: [String: Any] = [
        "refreshInterval": 120,
        "codexEnabled": false,
        "hasCompletedOnboarding": true,
    ]

    // MARK: - Inert by default

    @Test("without the switch, launch reads two keys and writes nothing")
    func inertWithoutSwitch() throws {
        let fixture = try makeFixture(prefs: realPrefs)
        let before = domain(fixture)

        #expect(DemoLaunch.prepare(fixture.env) == .inactive)

        #expect(domain(fixture).isEqual(before))
        #expect(fixture.index.updateAccountsIndexCallCount == 0)
        #expect(fixture.index.clearAccountsIndexCallCount == 0)
        #expect(fixture.accountFiles.files.isEmpty)
        #expect(fixture.codex.clearCount == 0 && fixture.codex.enabledCalls.isEmpty)
        #expect(fixture.notifications.purges.isEmpty)
        #expect(files(in: fixture.directory).isEmpty)
    }

    @Test("without the switch, the app's launch step builds nothing")
    func launchStepWithoutSwitch() {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        #expect(DemoLaunch.step(defaults: defaults) == .none)
        #expect(defaults.persistentDomain(forName: Self.suiteName)?.isEmpty ?? true)
        // The launch step reads the app's own defaults, never a suite, and
        // this process has no switch there.
        #expect(DemoLaunch.step(defaults: .standard) == .none)
        #expect(DemoLaunch.prepareAtLaunch() == .inactive)
    }

    @Test("the switch set to NO is the same as no switch")
    func inertWithSwitchOff() throws {
        let fixture = try makeFixture(prefs: realPrefs.merging([DemoMode.flagKey: false]) { $1 })
        let before = domain(fixture)
        #expect(DemoLaunch.prepare(fixture.env) == .inactive)
        #expect(domain(fixture).isEqual(before))
    }

    @Test("this process does not run the demo")
    func processIsNotInDemo() {
        #expect(DemoMode.isActive == false)
    }

    @Test("the shared seams answer as before while the demo is off")
    func seamsInertWhenOff() {
        let realHome = ClaudeConfigDirResolver.realHome()
        let folder = DemoFixtures.work.folderPath(home: realHome)
        let root = ClaudeHistoryRoot(
            account: DemoFixtures.work.accountID,
            projectsURL: URL(fileURLWithPath: folder).appendingPathComponent("projects"),
            cacheURL: URL(fileURLWithPath: "/tmp/unused.json")
        )
        #expect(DemoMode.historyService(for: root, active: false, home: realHome) == nil)
        #expect(DemoMode.codexHistoryService(active: false) == nil)
        #expect(DemoMode.configFolderExists(atPath: folder, active: false)
                == FileManager.default.fileExists(atPath: folder))
        // What the app builds by default, since this process is not in demo.
        #expect(CombinedSessionHistoryService.claudeLeg(for: root) is SessionHistoryService)
        #expect(CombinedSessionHistoryService.codexLeg() is SessionHistoryService)

        // And what the demo would answer instead.
        #expect(DemoMode.historyService(for: root, active: true, home: realHome) is DemoSessionHistoryService)
        #expect(DemoMode.configFolderExists(atPath: folder, active: true))
    }

    @Test("a real token goes to the real client, untouched")
    func apiClientRoutesRealTokens() async throws {
        let real = MockAPIClient()
        let client = DemoAPIClient(real: real, latency: .zero)

        _ = try await client.fetchUsage(token: "sk-ant-real", proxyConfig: nil)
        _ = try await client.fetchProfile(token: "sk-ant-real", proxyConfig: nil)
        #expect(real.fetchCallCount == 1)
        #expect(real.fetchProfileCallCount == 1)

        _ = try await client.fetchUsage(token: DemoFixtures.work.token, proxyConfig: nil)
        _ = try await client.fetchProfile(token: DemoFixtures.work.token, proxyConfig: nil)
        #expect(real.fetchCallCount == 1)
        #expect(real.fetchProfileCallCount == 1)
    }

    @Test("a folder that is not the demo's keeps its real provider and scan")
    func realFoldersStayReal() {
        let scope = CredentialScope.configDir(path: home + "/.claude-work", service: "Claude Code-credentials-0badc0de")
        #expect(DemoTokenProvider.make(scope: scope, home: home) == nil)
        #expect(DemoTokenProvider.make(scope: .defaultChain, home: home) == nil)

        let real = MockClaudeConfigDirScanner()
        let scanner = DemoConfigDirScanner(real: real, home: home)
        _ = scanner.inspect(path: home + "/.claude-work")
        #expect(real.inspectCallCount == 1)
    }

    // MARK: - Turning it on

    @Test("turning it on snapshots the app and tracks the seeded accounts")
    func activationSeeds() throws {
        let fixture = try makeFixture(prefs: realPrefs.merging([DemoMode.flagKey: true]) { $1 })

        #expect(DemoLaunch.prepare(fixture.env) == .activated)

        let records = ClaudeAccountsStorage.load(from: fixture.defaults, home: home)
        #expect(records.map(\.id) == [.main] + DemoFixtures.seeded.map(\.accountID))
        // Exactly three fake Claude accounts, none paused: pausing one is
        // the user's to try.
        #expect(DemoFixtures.seeded.map(\.name) == ["Work", "Side project", "Old login"])
        #expect(records.allSatisfy { !$0.isPaused })
        #expect(records.allSatisfy { $0.id.isMain || $0.identityDigest != nil })
        #expect(fixture.defaults.bool(forKey: "codexEnabled"))
        #expect(fixture.defaults.data(forKey: DemoMode.snapshotKey) != nil)
        #expect(fixture.defaults.integer(forKey: DemoMode.versionKey) == DemoFixtures.version)
        // The account that never refreshes starts with its last numbers.
        #expect(fixture.accountFiles.files[DemoFixtures.expired.accountID]?.cachedUsage != nil)
        #expect(fixture.accountFiles.files[DemoFixtures.work.accountID]?.cachedUsage == nil)
        // Nothing reached the disk of the shared folder.
        #expect(files(in: fixture.directory).isEmpty)

        // A second launch with the switch still on changes nothing.
        let during = domain(fixture)
        #expect(DemoLaunch.prepare(fixture.env) == .resumed)
        #expect(domain(fixture).isEqual(during))
    }

    // MARK: - A demo started by an older build

    /// What a demo started by the previous build left: its seeded Paused
    /// account (`acct-demo-paused`) and Client connected from the add sheet
    /// under a random id, with their keys, files and layouts.
    private func olderDemo(_ fixture: Fixture) throws -> (paused: AccountID, client: AccountID, real: AccountID) {
        fixture.defaults.set(true, forKey: DemoMode.flagKey)
        #expect(DemoLaunch.prepare(fixture.env) == .activated)
        fixture.defaults.removeObject(forKey: DemoMode.versionKey)

        var records = ClaudeAccountsStorage.load(from: fixture.defaults, home: home)
        let pausedPath = home + "/.claude-demo-paused"
        let paused = ClaudeAccountRecord(
            id: AccountID(rawValue: "acct-demo-paused"), configDir: pausedPath,
            service: ClaudeConfigDirResolver.service(forHashInput: pausedPath),
            name: "Paused", colorHex: "#6366F1", isPaused: true, identityDigest: "paused"
        )
        let clientRecord = DemoFixtures.record(for: DemoFixtures.client, home: home, now: Date())
        let client = ClaudeAccountRecord(
            id: .makeExtra(), configDir: clientRecord.configDir, service: clientRecord.service,
            name: "Client", colorHex: clientRecord.colorHex, identityDigest: clientRecord.identityDigest
        )
        // A real account added during the demo must stay.
        let realPath = home + "/.claude-work"
        let real = ClaudeAccountRecord(
            id: .makeExtra(), configDir: realPath,
            service: ClaudeConfigDirResolver.service(forHashInput: realPath),
            name: "Real", colorHex: "#22C55E", identityDigest: "real"
        )
        records += [paused, client, real]
        fixture.defaults.set(ClaudeAccountsStorage.encode(records), forKey: ClaudeAccountsStorage.defaultsKey)
        for id in [paused.id, client.id, real.id] {
            fixture.defaults.set(Data([1]), forKey: "sessionPacingSamples" + id.storageSuffix)
            fixture.defaults.set(Data([2]), forKey: "popoverComposition.claude" + id.storageSuffix)
            try Data("{}".utf8).write(to: fixture.directory.appendingPathComponent(id.sharedFileName))
        }
        return (paused.id, client.id, real.id)
    }

    @Test("a demo started by an older build drops Paused and Client at the next launch")
    func olderDemoIsPruned() throws {
        let fixture = try makeFixture(prefs: realPrefs)
        let ids = try olderDemo(fixture)
        #expect(DemoLaunch.step(defaults: fixture.defaults) == .prune)

        let outcome = DemoLaunch.prepare(fixture.env)
        #expect(outcome == .pruned([ids.paused, ids.client]))

        let records = ClaudeAccountsStorage.load(from: fixture.defaults, home: home)
        #expect(records.map(\.id) == [.main] + DemoFixtures.seeded.map(\.accountID) + [ids.real])
        for id in [ids.paused, ids.client] {
            #expect(fixture.defaults.object(forKey: "sessionPacingSamples" + id.storageSuffix) == nil)
            #expect(fixture.defaults.object(forKey: "popoverComposition.claude" + id.storageSuffix) == nil)
            #expect(!files(in: fixture.directory).contains(id.sharedFileName))
        }
        #expect(Set(fixture.notifications.purges.map(\.account)) == [ids.paused, ids.client])
        #expect(fixture.defaults.object(forKey: "sessionPacingSamples" + ids.real.storageSuffix) != nil)
        #expect(files(in: fixture.directory).contains(ids.real.sharedFileName))

        // Once only: the next launch just resumes.
        #expect(DemoLaunch.step(defaults: fixture.defaults) == .resume)
        #expect(DemoLaunch.prepare(fixture.env) == .resumed)
    }

    @Test("the add sheet's demo folders still answer after the trim")
    func addSheetFoldersStillWork() {
        #expect(DemoFixtures.claude.filter { !$0.seeded }.map(\.key) == ["client", "empty", "copy"])
        for fixture in DemoFixtures.claude {
            #expect(DemoFixtures.fixture(forFolder: fixture.folderPath(home: home), home: home) == fixture)
            #expect(DemoFixtures.isDemoFolder(fixture.folderPath(home: home), home: home))
        }
        #expect(DemoFixtures.isDemoFolder(home + "/.claude-demo-paused", home: home))
        #expect(DemoFixtures.fixture(forFolder: home + "/.claude-demo-paused", home: home) == nil)
        #expect(!DemoFixtures.isDemoFolder(home + "/.claude-work", home: home))
        #expect(!DemoFixtures.isDemoFolder(nil, home: home))
    }

    // MARK: - Turning it off

    @Test("turning it off restores the defaults exactly and removes every demo file")
    func cleanupRestoresEverything() throws {
        let fixture = try makeFixture(prefs: realPrefs)
        let original = domain(fixture)

        fixture.defaults.set(true, forKey: DemoMode.flagKey)
        #expect(DemoLaunch.prepare(fixture.env) == .activated)

        // What a demo session leaves: an account connected from the add
        // sheet under a random id, layouts and samples per account, a
        // changed setting, the per-account files, a Codex file, an index.
        var records = ClaudeAccountsStorage.load(from: fixture.defaults, home: home)
        let client = DemoFixtures.record(for: DemoFixtures.client, home: home, now: Date())
        let connected = ClaudeAccountRecord(
            id: .makeExtra(), configDir: client.configDir, service: client.service,
            name: "Client", colorHex: client.colorHex, identityDigest: client.identityDigest
        )
        records.append(connected)
        fixture.defaults.set(ClaudeAccountsStorage.encode(records), forKey: ClaudeAccountsStorage.defaultsKey)
        fixture.defaults.set(Data([1, 2, 3]), forKey: "popoverComposition.claude" + DemoFixtures.work.accountID.storageSuffix)
        fixture.defaults.set(Data([4]), forKey: "sessionPacingSamples" + connected.id.storageSuffix)
        fixture.defaults.set(60, forKey: "refreshInterval")
        fixture.defaults.set("work", forKey: "focusedClaudeAccount")
        let leftovers = [
            DemoFixtures.work.accountID.sharedFileName,
            "history-cache" + DemoFixtures.work.accountID.storageSuffix + ".json",
            connected.id.sharedFileName,
            "codex.json",
        ]
        for name in leftovers {
            try Data("{}".utf8).write(to: fixture.directory.appendingPathComponent(name))
        }
        try Data("{}".utf8).write(to: fixture.directory.appendingPathComponent("shared.json"))
        fixture.index._accountsIndex = AccountIndexEntry.index(of: records)

        fixture.defaults.removeObject(forKey: DemoMode.flagKey)
        #expect(DemoLaunch.prepare(fixture.env) == .cleanedUp)

        #expect(domain(fixture).isEqual(original))
        #expect(files(in: fixture.directory) == ["shared.json"])
        #expect(fixture.index._accountsIndex == nil)
        let purged = Set(fixture.notifications.purges.map(\.account))
        #expect(purged == Set(DemoFixtures.seeded.map(\.accountID) + [connected.id]))
        #expect(fixture.notifications.purges.allSatisfy { $0.includingDelivered })
        #expect(!purged.contains(.main))

        // And the launch after that is an ordinary one.
        #expect(DemoLaunch.prepare(fixture.env) == .inactive)
    }

    @Test("turning it off puts back the widget index and the Codex file that existed")
    func cleanupRestoresPriorIndexAndCodex() throws {
        let renamedMain = AccountIndexEntry(id: "main", name: "Perso", colorHex: "#5B8DEF", isPaused: false)
        let fixture = try makeFixture(prefs: ["codexEnabled": true], index: [renamedMain])
        try Data("{}".utf8).write(to: fixture.codex.fileURL)

        fixture.defaults.set(true, forKey: DemoMode.flagKey)
        DemoLaunch.prepare(fixture.env)
        fixture.index._accountsIndex = AccountIndexEntry.index(of: ClaudeAccountsStorage.load(from: fixture.defaults, home: home))
        fixture.defaults.removeObject(forKey: DemoMode.flagKey)
        DemoLaunch.prepare(fixture.env)

        #expect(fixture.index._accountsIndex == [renamedMain])
        #expect(fixture.codex.clearCount == 1)
        #expect(fixture.codex.enabledCalls == [true])
        #expect(FileManager.default.fileExists(atPath: fixture.codex.fileURL.path))
        #expect(fixture.defaults.object(forKey: DemoMode.snapshotKey) == nil)
    }

    @Test("the main account moved into a demo folder gets its real folder and no demo numbers back")
    func cleanupAfterMainMovedIntoDemo() throws {
        let fixture = try makeFixture(prefs: realPrefs)
        let original = domain(fixture)
        fixture.defaults.set(true, forKey: DemoMode.flagKey)
        DemoLaunch.prepare(fixture.env)
        var records = ClaudeAccountsStorage.load(from: fixture.defaults, home: home)
        records[0].configDir = DemoFixtures.client.folderPath(home: home)
        fixture.defaults.set(ClaudeAccountsStorage.encode(records), forKey: ClaudeAccountsStorage.defaultsKey)
        fixture.defaults.removeObject(forKey: DemoMode.flagKey)

        DemoLaunch.prepare(fixture.env)

        #expect(fixture.index.clearUsageCallCount == 1)
        #expect(domain(fixture).isEqual(original))
        #expect(ClaudeAccountsStorage.load(from: fixture.defaults, home: home).first?.configDir == nil)
    }

    @Test("a real account tracked before the demo keeps its files and alerts")
    func cleanupSparesRealAccounts() throws {
        let real = ClaudeAccountRecord(id: .makeExtra(), configDir: home + "/.claude-work", name: "Work", colorHex: "#22D3EE")
        let before = [ClaudeAccountRecord.defaultMain(), real]
        let fixture = try makeFixture(prefs: [ClaudeAccountsStorage.defaultsKey: ClaudeAccountsStorage.encode(before)!])
        try Data("{}".utf8).write(to: fixture.directory.appendingPathComponent(real.id.sharedFileName))
        fixture.defaults.set(true, forKey: DemoMode.flagKey)
        DemoLaunch.prepare(fixture.env)
        fixture.defaults.removeObject(forKey: DemoMode.flagKey)

        DemoLaunch.prepare(fixture.env)

        #expect(!fixture.notifications.purges.map(\.account).contains(real.id))
        #expect(files(in: fixture.directory) == [real.id.sharedFileName])
        #expect(ClaudeAccountsStorage.load(from: fixture.defaults, home: home).map(\.id) == [.main, real.id])
    }

    @Test("a real account added during the demo goes like a removed one, leaving no file behind")
    func cleanupRemovesRealAccountAddedDuringDemo() throws {
        let fixture = try makeFixture(prefs: realPrefs)
        fixture.defaults.set(true, forKey: DemoMode.flagKey)
        DemoLaunch.prepare(fixture.env)
        var records = ClaudeAccountsStorage.load(from: fixture.defaults, home: home)
        let real = ClaudeAccountRecord(id: .makeExtra(), configDir: home + "/.claude-work", name: "Work", colorHex: "#22D3EE")
        records.append(real)
        fixture.defaults.set(ClaudeAccountsStorage.encode(records), forKey: ClaudeAccountsStorage.defaultsKey)
        fixture.defaults.set(Data([4]), forKey: "sessionPacingSamples" + real.id.storageSuffix)
        fixture.defaults.set(2, forKey: "lastLevel_fiveHour" + real.id.storageSuffix)
        for name in [real.id.sharedFileName, "history-cache" + real.id.storageSuffix + ".json"] {
            try Data("{}".utf8).write(to: fixture.directory.appendingPathComponent(name))
        }
        fixture.defaults.removeObject(forKey: DemoMode.flagKey)

        DemoLaunch.prepare(fixture.env)

        #expect(files(in: fixture.directory).isEmpty)
        #expect(fixture.notifications.purges.contains { $0.account == real.id && $0.includingDelivered })
        #expect(ClaudeAccountsStorage.load(from: fixture.defaults, home: home).map(\.id) == [.main])
        #expect(fixture.defaults.object(forKey: "sessionPacingSamples" + real.id.storageSuffix) == nil)
        #expect(fixture.defaults.object(forKey: "lastLevel_fiveHour" + real.id.storageSuffix) == nil)
    }

    @Test("what the app lived through during the demo survives it, settings do not")
    func cleanupKeepsRuntimeState() throws {
        let prefs = realPrefs.merging([
            "lastSeenVersion": "6.0.2",
            "lastLevel_fiveHour": 0,
            "claudeTokenAlertSent": true,
        ]) { $1 }
        let fixture = try makeFixture(prefs: prefs)
        fixture.defaults.set(true, forKey: DemoMode.flagKey)
        DemoLaunch.prepare(fixture.env)

        // The real main account crossed a threshold, a login expiry was
        // alerted, a refresh succeeded, the what's-new screen was closed,
        // Codex alerted; and a setting changed.
        let expiry = Date(timeIntervalSince1970: 1_790_100_000)
        fixture.defaults.set(2, forKey: "lastLevel_fiveHour")
        fixture.defaults.set(expiry, forKey: "lastLoginExpiredEpisode")
        fixture.defaults.removeObject(forKey: "claudeTokenAlertSent")
        fixture.defaults.set(Data([7]), forKey: "sessionPacingSamples")
        fixture.defaults.set("6.1.0", forKey: "lastSeenVersion")
        fixture.defaults.set(1, forKey: "lastLevel_codexSession")
        // A demo account's own state goes with it.
        fixture.defaults.set(2, forKey: "lastLevel_fiveHour" + DemoFixtures.work.accountID.storageSuffix)
        fixture.defaults.set(60, forKey: "refreshInterval")
        fixture.defaults.removeObject(forKey: DemoMode.flagKey)

        DemoLaunch.prepare(fixture.env)

        #expect(fixture.defaults.integer(forKey: "lastLevel_fiveHour") == 2)
        #expect(fixture.defaults.object(forKey: "lastLoginExpiredEpisode") as? Date == expiry)
        #expect(fixture.defaults.object(forKey: "claudeTokenAlertSent") == nil)
        #expect(fixture.defaults.data(forKey: "sessionPacingSamples") == Data([7]))
        #expect(fixture.defaults.string(forKey: "lastSeenVersion") == "6.1.0")
        #expect(fixture.defaults.integer(forKey: "lastLevel_codexSession") == 1)
        #expect(fixture.defaults.object(forKey: "lastLevel_fiveHour" + DemoFixtures.work.accountID.storageSuffix) == nil)
        #expect(fixture.defaults.integer(forKey: "refreshInterval") == 120)
        #expect(fixture.defaults.bool(forKey: "codexEnabled") == false)
        // The fake Codex login's alerts went too, delivered ones included.
        #expect(fixture.notifications.codexAlertPurges == 1)
    }

    @Test("the main account's Claude state from a demo folder does not outlive the demo")
    func cleanupDropsMainStateFromDemoFolder() throws {
        let fixture = try makeFixture(prefs: realPrefs.merging(["lastLevel_fiveHour": 0]) { $1 })
        fixture.defaults.set(true, forKey: DemoMode.flagKey)
        DemoLaunch.prepare(fixture.env)
        var records = ClaudeAccountsStorage.load(from: fixture.defaults, home: home)
        records[0].configDir = DemoFixtures.client.folderPath(home: home)
        fixture.defaults.set(ClaudeAccountsStorage.encode(records), forKey: ClaudeAccountsStorage.defaultsKey)
        fixture.defaults.set(2, forKey: "lastLevel_fiveHour")
        fixture.defaults.set("6.1.0", forKey: "lastSeenVersion")
        fixture.defaults.removeObject(forKey: DemoMode.flagKey)

        DemoLaunch.prepare(fixture.env)

        #expect(fixture.defaults.integer(forKey: "lastLevel_fiveHour") == 0)
        #expect(fixture.defaults.string(forKey: "lastSeenVersion") == "6.1.0")
    }

    // MARK: - The fixtures through the real code

    @Test("the add flow: a login connects, no login and a duplicate are refused")
    func connectThroughDemoSeams() async throws {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        let seeded = [ClaudeAccountRecord.defaultMain()]
            + DemoFixtures.seeded.map { DemoFixtures.record(for: $0, home: home, now: Date()) }
        defaults.set(ClaudeAccountsStorage.encode(seeded), forKey: ClaudeAccountsStorage.defaultsKey)

        let mainRepo = MockUsageRepository()
        mainRepo.stubbedProfile = .fixture(accountUUID: "main-uuid", orgUUID: "main-org")
        let mainProvider = MockTokenProvider()
        mainProvider.token = "main-token"
        let main = UsageStore(
            repository: mainRepo,
            tokenProvider: mainProvider,
            sharedFileService: MockSharedFileService(),
            notificationService: MockNotificationService(),
            sessionSamplesKey: "DemoModeTests.main",
            reloadWidgets: {}
        )
        let home = self.home
        let store = AccountsStore(
            mainStore: main,
            defaults: defaults,
            home: home,
            scanner: DemoConfigDirScanner(real: MockClaudeConfigDirScanner(), home: home),
            makeConnectTokenProvider: { scope in
                if let demo = DemoTokenProvider.make(scope: scope, home: home) { return demo }
                return MockTokenProvider()
            },
            apiClient: DemoAPIClient(real: MockAPIClient(), latency: .zero),
            notifications: MockNotificationService(),
            makeRuntime: { record in
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
        })

        let candidates = store.scanner.candidates(excluding: store.trackedPaths)
        #expect(candidates.map(\.displayPath) == ["~/.claude-demo-client", "~/.claude-demo-empty", "~/.claude-demo-copy"])
        #expect(candidates.map(\.hasLogin) == [true, false, true])

        let clientPath = DemoFixtures.client.folderPath(home: home)
        guard case .ready(let pending) = await store.connect(configDir: clientPath, knownService: candidates[0].matchedService) else {
            Issue.record("the client folder should connect")
            return
        }
        #expect(pending.plan == .pro)
        #expect(pending.maskedEmail == "m•••@globex-demo.dev")

        let empty = await store.connect(configDir: DemoFixtures.empty.folderPath(home: home))
        #expect(empty == .noLogin(command: "CLAUDE_CONFIG_DIR=~/.claude-demo-empty claude"))

        let copy = await store.connect(configDir: DemoFixtures.copy.folderPath(home: home), knownService: candidates[2].matchedService)
        let workSummary = try #require(store.record(for: DemoFixtures.work.accountID)?.summary)
        #expect(copy == .duplicate(of: workSummary))

        let added = try #require(store.commit(pending, name: "Client", colorHex: pending.proposedColorHex))
        #expect(store.records.last?.id == added.id)
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    @Test("an expired demo login shows the escalated expired state, with its folder's command")
    func expiredLoginState() async {
        let fixture = DemoFixtures.expired
        let scope = CredentialScope.configDir(path: fixture.folderPath(home: home), service: fixture.service(home: home))
        let startedAt = Date()
        let store = UsageStore(
            repository: UsageRepository(
                apiClient: DemoAPIClient(real: MockAPIClient(), startedAt: startedAt, latency: .zero),
                sharedFileService: MockSharedFileService()
            ),
            tokenProvider: DemoTokenProvider(fixture: fixture, scope: scope, startedAt: startedAt),
            sharedFileService: MockSharedFileService(),
            notificationService: MockNotificationService(),
            sessionSamplesKey: "DemoModeTests.expired",
            reloadWidgets: {}
        )

        await store.refresh(force: true)

        #expect(store.errorState == .tokenUnavailable)
        #expect(store.loginExpiredSince == DemoFixtures.expiredAt(startedAt: startedAt))
        #expect(UsageStore.renewCommand(scope: scope, home: home) == "CLAUDE_CONFIG_DIR=~/.claude-demo-old claude")
        UserDefaults.standard.removeObject(forKey: "DemoModeTests.expired")
    }

    @Test("a running demo account fills every tile its fixture has, and drifts")
    func workUsage() async {
        let fixture = DemoFixtures.work
        let startedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let early = DemoFixtures.usage(for: fixture, at: startedAt.addingTimeInterval(600), startedAt: startedAt)
        let later = DemoFixtures.usage(for: fixture, at: startedAt.addingTimeInterval(1_500), startedAt: startedAt)

        #expect(early.fiveHour?.utilization != later.fiveHour?.utilization)
        #expect((82...94).contains(early.fiveHour?.utilization ?? 0))
        #expect(early.sevenDayFable != nil)
        // No account invents a Sonnet or Opus weekly limit: live accounts no
        // longer get one, so the demo must not show one either.
        for account in DemoFixtures.claude {
            let usage = DemoFixtures.usage(for: account, at: startedAt, startedAt: startedAt)
            #expect(usage.sevenDaySonnet == nil, "\(account.name) invents a Sonnet limit")
            #expect(usage.sevenDayOpus == nil, "\(account.name) invents an Opus limit")
        }
        #expect(early.extraUsage?.isEnabled == true)
        // Resets sit on a grid: the next refresh in the same window agrees.
        #expect(early.fiveHour?.resetsAt == later.fiveHour?.resetsAt)
        #expect(DemoFixtures.identityDigest(of: DemoFixtures.copy) == DemoFixtures.identityDigest(of: fixture))
        #expect(DemoFixtures.identityDigest(of: DemoFixtures.side) != DemoFixtures.identityDigest(of: fixture))
    }

    @Test("demo history has data for an active account and none after a quiet one went quiet")
    func historyFixtures() async throws {
        let startedAt = Date()
        let busy = DemoSessionHistoryService(shape: DemoFixtures.work.history, seed: "work", provider: .claude, startedAt: startedAt)
        let week = try await busy.loadHistory(range: .sevenDays)
        #expect(week.reduce(0) { $0 + $1.totalActive } > 0)

        let quiet = DemoSessionHistoryService(shape: DemoFixtures.expired.history, seed: "old", provider: .claude, startedAt: startedAt)
        let day = try await quiet.loadHistory(range: .twentyFourHours)
        #expect(day.isEmpty)
    }
}
