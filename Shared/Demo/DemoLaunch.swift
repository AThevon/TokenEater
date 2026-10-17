import Foundation

/// Where the demo's launch step reads and writes. `live()` is the app's own
/// defaults domain and shared folder; tests hand in a scratch domain and
/// folder.
struct DemoLaunchEnvironment {
    let defaults: UserDefaults
    /// The persistent domain `defaults` writes, snapshotted and restored
    /// whole.
    let domainName: String
    let home: String
    /// The folder holding `shared.json` and the per-account files.
    let sharedDirectory: URL
    /// `shared.json`, for the widget's accounts index.
    let indexFile: SharedFileServiceProtocol
    /// An account's own shared file, for the last numbers a paused or
    /// expired fake account starts with.
    let accountFile: (AccountID) -> SharedFileServiceProtocol
    let codexFile: CodexSharedFileServiceProtocol
    /// Drops a fake account's alerts, pending and delivered.
    let notifications: NotificationServiceProtocol
    let now: Date

    static func live(now: Date = Date()) -> DemoLaunchEnvironment {
        let index = SharedFileService()
        return DemoLaunchEnvironment(
            defaults: .standard,
            domainName: Bundle.main.bundleIdentifier ?? "com.tokeneater.app",
            home: ClaudeConfigDirResolver.realHome(),
            sharedDirectory: index.fileURL.deletingLastPathComponent(),
            indexFile: index,
            accountFile: { SharedFileService(fileName: $0.sharedFileName) },
            codexFile: CodexSharedFileService(),
            notifications: NotificationService(),
            now: now
        )
    }
}

/// What the launch step did.
enum DemoLaunchOutcome: Equatable {
    /// The switch is off and no demo ever ran: nothing was read beyond two
    /// keys, nothing was written. Every install that never heard of the
    /// demo lands here.
    case inactive
    /// The switch was just turned on: the app's state was snapshotted and
    /// the fake accounts added.
    case activated
    /// The demo was already on: nothing to do.
    case resumed
    /// The switch was turned off: everything the demo added is gone and the
    /// app's defaults are back to the snapshot.
    case cleanedUp
}

/// Starts and ends the demo, once per launch, before any store reads its
/// defaults (`TokenEaterApp.init`).
enum DemoLaunch {
    /// What this launch has to do, from the switch and the snapshot alone.
    enum Step: Equatable {
        case none
        case resume
        case activate
        case cleanUp
    }

    static func step(defaults: UserDefaults) -> Step {
        let enabled = defaults.bool(forKey: DemoMode.flagKey)
        let ran = defaults.object(forKey: DemoMode.snapshotKey) != nil
        switch (enabled, ran) {
        case (false, false): return .none
        case (true, true): return .resume
        case (true, false): return .activate
        case (false, true): return .cleanUp
        }
    }

    /// The app's launch step. The live files and services are only built
    /// when there is something to do, so an install that never turned the
    /// demo on reads two keys here and nothing else.
    @discardableResult
    static func prepareAtLaunch(defaults: UserDefaults = .standard) -> DemoLaunchOutcome {
        switch step(defaults: defaults) {
        case .none: return .inactive
        case .resume: return .resumed
        case .activate, .cleanUp: return prepare(.live())
        }
    }

    @discardableResult
    static func prepare(_ env: DemoLaunchEnvironment) -> DemoLaunchOutcome {
        switch step(defaults: env.defaults) {
        case .none: return .inactive
        case .resume: return .resumed
        case .activate:
            activate(env)
            return .activated
        case .cleanUp:
            cleanUp(env)
            return .cleanedUp
        }
    }

    // MARK: - Turning it on

    /// Snapshots the app's defaults, the widget's accounts index and whether
    /// `codex.json` existed, then tracks the seeded fake accounts next to
    /// whatever was tracked already, gives the paused and expired ones their
    /// last numbers, and turns Codex on for the fake login.
    static func activate(_ env: DemoLaunchEnvironment) {
        var domain = env.defaults.persistentDomain(forName: env.domainName) ?? [:]
        for key in DemoMode.keys { domain.removeValue(forKey: key) }
        guard let snapshot = try? PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0) else {
            return
        }
        env.defaults.set(snapshot, forKey: DemoMode.snapshotKey)
        if let index = env.indexFile.accountsIndex, let data = try? JSONEncoder().encode(index) {
            env.defaults.set(data, forKey: DemoMode.snapshotIndexKey)
        }
        env.defaults.set(
            FileManager.default.fileExists(atPath: env.codexFile.fileURL.path),
            forKey: DemoMode.codexFileExistedKey
        )
        env.defaults.set(env.now, forKey: DemoMode.startedAtKey)

        var records = ClaudeAccountsStorage.load(from: env.defaults, home: env.home)
        for fixture in DemoFixtures.seeded {
            let record = DemoFixtures.record(for: fixture, home: env.home, now: env.now)
            guard !records.contains(where: { $0.id == record.id }) else { continue }
            let tracked = records.contains { existing in
                let dir = existing.configDir ?? ClaudeConfigDirResolver.defaultDirectory(home: env.home)
                return ClaudeConfigDirResolver.normalize(dir, home: env.home) == record.configDir
            }
            guard !tracked else { continue }
            records.append(record)
            seedLastNumbers(for: fixture, file: env.accountFile(record.id), startedAt: env.now)
            seedSessionSamples(for: fixture, defaults: env.defaults, startedAt: env.now)
        }
        env.defaults.set(ClaudeAccountsStorage.encode(records), forKey: ClaudeAccountsStorage.defaultsKey)
        env.defaults.set(true, forKey: "codexEnabled")
    }

    /// The numbers a fake account that does not refresh (paused, expired)
    /// shows, dated `lastNumbersAgo` before `startedAt`.
    static func seedLastNumbers(for fixture: DemoClaudeFixture, file: SharedFileServiceProtocol, startedAt: Date) {
        guard let ago = fixture.lastNumbersAgo else { return }
        let fetched = startedAt.addingTimeInterval(-ago)
        let usage = DemoFixtures.usage(for: fixture, at: fetched, startedAt: fetched)
        file.updateAfterSync(usage: CachedUsage(usage: usage, fetchDate: fetched), syncDate: fetched)
    }

    /// A trajectory for the hero pacing graph of the busiest running fake
    /// account, so it does not start empty.
    static func seedSessionSamples(for fixture: DemoClaudeFixture, defaults: UserDefaults, startedAt: Date) {
        guard fixture == DemoFixtures.work else { return }
        let samples = DemoFixtures.sessionSamples(for: fixture, now: startedAt, startedAt: startedAt)
        guard let data = try? JSONEncoder().encode(samples) else { return }
        defaults.set(data, forKey: AccountsStore.sessionSamplesKey(for: fixture.accountID))
    }

    // MARK: - Turning it off

    /// Every fake account goes the way Remove takes an account: its shared
    /// file, its history cache and its alerts. The widget's accounts index
    /// and `codex.json` go back to what they were, and last the app's
    /// defaults are replaced by the snapshot, which also drops the account
    /// list, the layouts, the samples and every key the demo wrote.
    static func cleanUp(_ env: DemoLaunchEnvironment) {
        let records = ClaudeAccountsStorage.load(from: env.defaults, home: env.home)
        var ids = Set(DemoFixtures.seeded.map(\.accountID))
        for record in records where DemoFixtures.fixture(forFolder: record.configDir, home: env.home) != nil {
            ids.insert(record.id)
        }
        let fm = FileManager.default
        for id in ids.sorted(by: { $0.rawValue < $1.rawValue }) where !id.isMain {
            try? fm.removeItem(at: env.sharedDirectory.appendingPathComponent(id.sharedFileName))
            try? fm.removeItem(at: env.sharedDirectory.appendingPathComponent("history-cache\(id.storageSuffix).json"))
            env.notifications.purge(account: id, includingDelivered: true)
        }
        // The fake Codex login may have scheduled reset reminders.
        env.notifications.cancelCodexReminders()
        // The main account moved into a demo folder wrote demo numbers to
        // `shared.json`; its real folder comes back with the snapshot.
        if DemoFixtures.fixture(forFolder: records.first?.configDir, home: env.home) != nil {
            env.indexFile.clearUsage()
        }

        if let data = env.defaults.data(forKey: DemoMode.snapshotIndexKey),
           let index = try? JSONDecoder().decode([AccountIndexEntry].self, from: data) {
            env.indexFile.updateAccountsIndex(index)
        } else {
            env.indexFile.clearAccountsIndex()
        }

        let snapshotData = env.defaults.data(forKey: DemoMode.snapshotKey)
        let snapshot = snapshotData.flatMap {
            try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) as? [String: Any]
        }

        if env.defaults.bool(forKey: DemoMode.codexFileExistedKey) {
            env.codexFile.clear()
            env.codexFile.updateEnabled(snapshot?["codexEnabled"] as? Bool ?? false)
        } else {
            try? fm.removeItem(at: env.codexFile.fileURL)
        }

        if let snapshot {
            env.defaults.setPersistentDomain(snapshot, forName: env.domainName)
        } else {
            // No readable snapshot: at least nothing fake stays tracked and
            // the demo's own keys go.
            let kept = records.filter { !ids.contains($0.id) }
            env.defaults.set(ClaudeAccountsStorage.encode(kept), forKey: ClaudeAccountsStorage.defaultsKey)
            for key in env.defaults.dictionaryRepresentation().keys where ids.contains(where: { key.hasSuffix($0.storageSuffix) }) {
                env.defaults.removeObject(forKey: key)
            }
            for key in DemoMode.keys { env.defaults.removeObject(forKey: key) }
        }
    }
}
