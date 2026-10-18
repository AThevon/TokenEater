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
    /// The demo was already on, started by a build that seeded other fake
    /// accounts: the ones this build no longer seeds were removed, and the
    /// settings still have to forget them (`SettingsStore.purgeAccount`).
    case pruned([AccountID])
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
        /// Running, but started by a build with other fixtures.
        case prune
        case activate
        case cleanUp
    }

    static func step(defaults: UserDefaults) -> Step {
        let enabled = defaults.bool(forKey: DemoMode.flagKey)
        let ran = defaults.object(forKey: DemoMode.snapshotKey) != nil
        switch (enabled, ran) {
        case (false, false): return .none
        case (true, true): return isCurrent(defaults: defaults) ? .resume : .prune
        case (true, false): return .activate
        case (false, true): return .cleanUp
        }
    }

    /// Whether the running demo was started, or last pruned, by a build
    /// seeding the same accounts as this one.
    static func isCurrent(defaults: UserDefaults) -> Bool {
        let stored = defaults.object(forKey: DemoMode.versionKey) as? Int ?? 1
        return stored >= DemoFixtures.version
    }

    /// The app's launch step, on the app's own defaults and files only:
    /// tests go through `prepare(_:)` with an environment of their own. The
    /// live files and services are only built when there is something to do,
    /// so an install that never turned the demo on reads two keys here and
    /// nothing else.
    @discardableResult
    static func prepareAtLaunch() -> DemoLaunchOutcome {
        switch step(defaults: .standard) {
        case .none: return .inactive
        case .resume: return .resumed
        case .prune, .activate, .cleanUp: return prepare(.live())
        }
    }

    @discardableResult
    static func prepare(_ env: DemoLaunchEnvironment) -> DemoLaunchOutcome {
        switch step(defaults: env.defaults) {
        case .none: return .inactive
        case .resume: return .resumed
        case .prune:
            return .pruned(pruneRetired(env))
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
    /// whatever was tracked already, gives the expired one its last numbers,
    /// and turns Codex on for the fake login.
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
        env.defaults.set(DemoFixtures.version, forKey: DemoMode.versionKey)

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

    // MARK: - A demo started by an older build

    /// Removes the fake accounts this build does not seed, the way Remove
    /// takes an account: a seeded fixture that retired (Paused) and any fake
    /// folder connected through the add sheet (Client), so the demo comes
    /// back to exactly the seeded accounts. Their record, every defaults key
    /// under their suffix, their shared file, their history cache and their
    /// alerts go here, before any store reads them; the layouts that name
    /// them go once the settings exist, through the ids this returns. The
    /// snapshot is not touched: none of them was in it. A real account added
    /// during the demo stays.
    @discardableResult
    static func pruneRetired(_ env: DemoLaunchEnvironment) -> [AccountID] {
        defer { env.defaults.set(DemoFixtures.version, forKey: DemoMode.versionKey) }
        var records = ClaudeAccountsStorage.load(from: env.defaults, home: env.home)
        let seeded = Set(DemoFixtures.seeded.map(\.accountID))
        let retired = records
            .filter { !$0.id.isMain && !seeded.contains($0.id) && DemoFixtures.isDemoFolder($0.configDir, home: env.home) }
            .map(\.id)
        guard !retired.isEmpty else { return [] }

        records.removeAll { retired.contains($0.id) }
        env.defaults.set(ClaudeAccountsStorage.encode(records), forKey: ClaudeAccountsStorage.defaultsKey)
        let fm = FileManager.default
        for id in retired {
            for key in env.defaults.dictionaryRepresentation().keys where key.hasSuffix(id.storageSuffix) {
                env.defaults.removeObject(forKey: key)
            }
            try? fm.removeItem(at: env.sharedDirectory.appendingPathComponent(id.sharedFileName))
            try? fm.removeItem(at: env.sharedDirectory.appendingPathComponent("history-cache\(id.storageSuffix).json"))
            env.notifications.purge(account: id, includingDelivered: true)
        }
        let index = AccountIndexEntry.index(of: records)
        if env.indexFile.accountsIndex != nil {
            env.indexFile.updateAccountsIndex(index)
        }
        return retired
    }

    /// The numbers a fake account that does not refresh (an expired one)
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

    /// Gives the running demo accounts their place in the All layouts, the
    /// way the add sheet does for an account it connects: a popover section
    /// and menu bar segments each, in list order, then All on screen. Run
    /// once the settings exist, right after `activate` and after the demo
    /// card brings removed demo accounts back. A paused one gets nothing, as
    /// it leaves the menu bar and popover anyway.
    @MainActor
    static func seedLayouts(for records: [ClaudeAccountRecord], into settings: SettingsStore, home: String) {
        let running = records.filter { record in
            !record.id.isMain && !record.isPaused
                && DemoFixtures.fixture(forFolder: record.configDir, home: home) != nil
        }
        guard !running.isEmpty else { return }
        for record in running {
            settings.seedAccount(record.id, addToMenuBar: true)
        }
        if settings.activeProviderMode != .all {
            settings.selectScope(.all)
        }
    }

    // MARK: - Turning it off

    /// Every account the snapshot does not hold goes the way Remove takes
    /// an account: its shared file, its history cache and its alerts. That
    /// is every fake account, and a real one added during the demo too,
    /// since its record goes with the snapshot. The fake Codex login's
    /// alerts go as well. The widget's accounts index and `codex.json` go
    /// back to what they were, and last the app's defaults are replaced by
    /// the snapshot, which drops the account list, the layouts and every key
    /// the demo wrote, but keeps what the app lived through meanwhile
    /// (`isRuntimeState`): alerts already sent stay sent.
    static func cleanUp(_ env: DemoLaunchEnvironment) {
        let records = ClaudeAccountsStorage.load(from: env.defaults, home: env.home)
        let snapshotData = env.defaults.data(forKey: DemoMode.snapshotKey)
        let snapshot = snapshotData.flatMap {
            try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) as? [String: Any]
        }

        var ids = Set(DemoFixtures.seeded.map(\.accountID))
        for record in records where !record.id.isMain && DemoFixtures.isDemoFolder(record.configDir, home: env.home) {
            ids.insert(record.id)
        }
        if let snapshot {
            let before = Set(
                ClaudeAccountsStorage.decode(snapshot[ClaudeAccountsStorage.defaultsKey] as? Data, home: env.home).map(\.id)
            )
            for record in records where !before.contains(record.id) {
                ids.insert(record.id)
            }
        }
        ids.remove(.main)

        let fm = FileManager.default
        for id in ids.sorted(by: { $0.rawValue < $1.rawValue }) {
            try? fm.removeItem(at: env.sharedDirectory.appendingPathComponent(id.sharedFileName))
            try? fm.removeItem(at: env.sharedDirectory.appendingPathComponent("history-cache\(id.storageSuffix).json"))
            env.notifications.purge(account: id, includingDelivered: true)
        }
        // The fake Codex login's alerts, delivered ones included: they carry
        // Codex's usual identifiers, so nothing else would ever take them
        // out of Notification Center.
        env.notifications.purgeCodexAlerts()
        // The main account moved into a demo folder wrote demo numbers to
        // `shared.json`; its real folder comes back with the snapshot.
        let mainWasInDemo = DemoFixtures.fixture(forFolder: records.first?.configDir, home: env.home) != nil
        if mainWasInDemo {
            env.indexFile.clearUsage()
        }

        if let data = env.defaults.data(forKey: DemoMode.snapshotIndexKey),
           let index = try? JSONDecoder().decode([AccountIndexEntry].self, from: data) {
            env.indexFile.updateAccountsIndex(index)
        } else {
            env.indexFile.clearAccountsIndex()
        }

        if env.defaults.bool(forKey: DemoMode.codexFileExistedKey) {
            env.codexFile.clear()
            env.codexFile.updateEnabled(snapshot?["codexEnabled"] as? Bool ?? false)
        } else {
            try? fm.removeItem(at: env.codexFile.fileURL)
        }

        if var snapshot {
            let current = env.defaults.persistentDomain(forName: env.domainName) ?? [:]
            let keeps = { (key: String) in
                isRuntimeState(key) && keepsRuntimeState(key, dropping: ids, mainWasInDemo: mainWasInDemo)
            }
            for key in snapshot.keys where keeps(key) && current[key] == nil {
                snapshot.removeValue(forKey: key)
            }
            for (key, value) in current where keeps(key) {
                snapshot[key] = value
            }
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

    // MARK: - What the snapshot does not take back

    /// State the app keeps about what already happened, as opposed to what
    /// the user chose: alert memory, pacing samples, the what's-new and brew
    /// prompts. Restoring it from the snapshot would replay alerts already
    /// sent and the what's-new screen already seen, so the cleanup keeps its
    /// current value. Claude's keys may carry an account's `.acct-<id>`
    /// suffix; the others are the app's own.
    static let claudeAccountStateKeys: Set<String> = [
        "claudeTokenAlertSent", "lastLoginExpiredEpisode", "sessionPacingSamples",
    ]
    static let claudeAccountStatePrefixes = ["lastLevel_", "lastResetsAt_", "lastPacing_"]
    static let appStateKeys: Set<String> = [
        "lastSeenVersion", "brewMigrationDismissed", "lastCodexTokenExpiredFiredAt",
    ]
    /// Checked before Claude's prefixes: Codex's levels share `lastLevel_`.
    static let appStatePrefixes = [
        "lastLevel_codex", "lastPacing_codex", "lastResetsAt_codex", "codexResetAt_", "codexUtilization_", "lastVendorHealth_",
    ]

    /// The key without its account suffix, and that account.
    private static func split(_ key: String) -> (base: String, account: AccountID) {
        guard let range = key.range(of: ".acct-") else { return (key, .main) }
        let raw = String(key[key.index(after: range.lowerBound)...])
        return (String(key[..<range.lowerBound]), AccountID(rawValue: raw))
    }

    static func isRuntimeState(_ key: String) -> Bool {
        let base = split(key).base
        return appStateKeys.contains(base)
            || appStatePrefixes.contains(where: base.hasPrefix)
            || claudeAccountStateKeys.contains(base)
            || claudeAccountStatePrefixes.contains(where: base.hasPrefix)
    }

    /// Whether a runtime key's current value outlives the demo: not for an
    /// account that goes with it, nor for the main account's Claude state
    /// when it spent the demo on a fake folder, whose numbers it holds.
    static func keepsRuntimeState(_ key: String, dropping removed: Set<AccountID>, mainWasInDemo: Bool) -> Bool {
        let (base, account) = split(key)
        if appStateKeys.contains(base) || appStatePrefixes.contains(where: base.hasPrefix) {
            return account.isMain
        }
        if removed.contains(account) { return false }
        if account.isMain && mainWasInDemo { return false }
        return true
    }
}
