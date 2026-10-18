import Testing
import Foundation

/// A user of the second-account prototype (#284) installs this build: its
/// preferences must decode with no crash, no ghost mode, no `work*` kind
/// left, and no account added behind their back.
@Suite("Prototype account migration (#284)", .serialized)
@MainActor
struct PrototypeAccountMigrationTests {

    private static let suiteName = "PrototypeAccountMigrationTests"

    private func makeDefaults(_ prefs: [String: Any]) -> UserDefaults {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        for (key, value) in prefs { defaults.set(value, forKey: key) }
        return defaults
    }

    private func ownKeys(_ defaults: UserDefaults) -> Set<String> {
        Set(defaults.persistentDomain(forName: Self.suiteName)?.keys.map { $0 } ?? [])
    }

    @Test("The prototype's mode, keys and kinds are read into this build's terms")
    func migratesPrototypePrefs() throws {
        let defaults = makeDefaults(PrototypeAccountPrefsFixture.prefs)
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }

        #expect(PrototypeAccountMigration.run(defaults: defaults))

        // No ghost mode: All, the only mode that means something here.
        #expect(defaults.string(forKey: "activeProviderMode") == "all")
        // The prototype's own keys and its mode's layouts are gone; this
        // build's account list was never written, so no account was added.
        let keys = ownKeys(defaults)
        for gone in ["extraClaudeAccounts", "workAccountLabel", "workAccountMenuBarSeeded",
                     "menuBarComposition.claudeWork", "popoverComposition.claudeWork",
                     "dashboardComposition.claudeWork", "sessionPacingSamples.1a2b3c4d"] {
            #expect(!keys.contains(gone), "\(gone) survived")
        }
        #expect(defaults.object(forKey: ClaudeAccountsStorage.defaultsKey) == nil)

        // The work kinds are dropped, the rest of each layout is kept.
        let menuBar = try JSONDecoder().decode(MenuBarComposition.self, from: #require(defaults.data(forKey: "menuBarComposition")))
        #expect(menuBar.segments.map(\.kind) == [.session, .weekly])
        #expect(menuBar.segments.allSatisfy { $0.account == nil })
        let popover = try JSONDecoder().decode(PopoverComposition.self, from: #require(defaults.data(forKey: "popoverComposition")))
        #expect(popover.elements.map(\.kind) == [.session, .weekly])
        let templates = try JSONDecoder().decode([PopoverUserTemplate].self, from: #require(defaults.data(forKey: "popoverUserTemplates")))
        #expect(templates.map(\.name) == ["Both accounts"])
        #expect(templates.first?.composition.elements.map(\.kind) == [.session])
        for key in ["menuBarComposition", "popoverComposition", "popoverUserTemplates"] {
            #expect(!PrototypeAccountMigration.mentionsWorkKind(defaults.data(forKey: key) ?? Data()))
        }

        // The work card's glance choice goes, the others stay.
        let windows = try JSONDecoder().decode([String: String].self, from: #require(defaults.data(forKey: "heroWindows")))
        #expect(windows == ["claude": "weekly", "codex": "session"])

        // Run again: nothing left to do.
        #expect(!PrototypeAccountMigration.run(defaults: defaults))
    }

    @Test("Without the migration the prototype's prefs still decode, minus the work kinds")
    func decodersAreLossy() throws {
        let menuBar = try JSONDecoder().decode(MenuBarComposition.self, from: Data(PrototypeAccountPrefsFixture.menuBarAll.utf8))
        #expect(menuBar.segments.map(\.kind) == [.session, .weekly])
        let popover = try JSONDecoder().decode(PopoverComposition.self, from: Data(PrototypeAccountPrefsFixture.popoverAll.utf8))
        #expect(popover.elements.map(\.kind) == [.session, .weekly])
        #expect(ProviderMode(rawValue: PrototypeAccountMigration.modeRawValue) == nil)
    }

    @Test("An install that never ran the prototype is left untouched")
    func untouchedOtherwise() {
        let current = MenuBarComposition(segments: [
            MenuBarSegment(kind: .session, style: .labelValue),
            MenuBarSegment(kind: .weekly, style: .labelValue, account: AccountID(rawValue: "acct-work")),
        ])
        let prefs: [String: Any] = [
            "activeProviderMode": "claude",
            "menuBarComposition": try! JSONEncoder().encode(current),
            "sessionPacingSamples": Data("[]".utf8),
            "sessionPacingSamples.acct-work": Data("[]".utf8),
            // Same prefix, not the prototype's eight hex digits.
            "sessionPacingSamples.codex": Data("[]".utf8),
            "sessionPacingSamples.1a2b3c4d5": Data("[]".utf8),
            "popoverComposition.claude.acct-work": Data("{}".utf8),
            "heroWindows": Data(#"{"claude":"weekly"}"#.utf8),
        ]
        let defaults = makeDefaults(prefs)
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        let before = NSDictionary(dictionary: defaults.persistentDomain(forName: Self.suiteName) ?? [:])

        #expect(!PrototypeAccountMigration.run(defaults: defaults))
        #expect(NSDictionary(dictionary: defaults.persistentDomain(forName: Self.suiteName) ?? [:]).isEqual(before))
    }

    @Test("The prototype's prefs open on All with the work segments gone, and read no credential")
    func settingsStoreAfterMigration() {
        let standard = UserDefaults.standard
        let keys = Array(PrototypeAccountPrefsFixture.prefs.keys) + ["claudeAccounts.v1", "focusedClaudeAccount"]
        func clean() { for key in keys { standard.removeObject(forKey: key) } }
        clean()
        defer { clean() }
        for (key, value) in PrototypeAccountPrefsFixture.prefs { standard.set(value, forKey: key) }

        PrototypeAccountMigration.run(defaults: standard)
        let tokens = MockTokenProvider()
        let settings = SettingsStore(notificationService: MockNotificationService(), tokenProvider: tokens)

        #expect(settings.activeProviderMode == .all)
        #expect(settings.claudeAccounts.map(\.id) == [.main])
        #expect(settings.menuBarComposition.segments.map(\.kind) == [.session, .weekly])
        #expect(settings.modeChoices.allSatisfy { $0.account == nil || $0.account == .main })
        #expect(tokens.currentTokenCallCount == 0)
    }
}
