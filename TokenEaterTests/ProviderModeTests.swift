import Testing
import Foundation

/// The mode model's persistence is the irreversible part of the design: every
/// saved layout on every install encodes these keys. These tests pin the three
/// properties that make it safe to ship.
@Suite("Provider display modes", .serialized)
@MainActor
struct ProviderModeTests {

    private static let keys = [
        "popoverComposition", "popoverComposition.claude", "popoverComposition.codex",
        "menuBarComposition", "menuBarComposition.claude", "menuBarComposition.codex",
        "dashboardComposition", "dashboardComposition.claude", "dashboardComposition.codex",
        "activeProviderMode", "codexEnabled", "claudeEnabled",
        "claudeAccounts.v1", "focusedClaudeAccount", "heroWindows",
    ]

    private func clean() {
        let defaults = UserDefaults.standard
        for key in Self.keys { defaults.removeObject(forKey: key) }
        // Every per-account layout a test left behind, and the keys of the
        // second-account prototype (#284) earlier runs may have left.
        for key in defaults.dictionaryRepresentation().keys
        where key.contains(".acct-") || key.hasSuffix(".claudeWork") {
            defaults.removeObject(forKey: key)
        }
    }

    private static let work = AccountID(rawValue: "acct-work")
    private static let side = AccountID(rawValue: "acct-side")

    private func summary(_ id: AccountID, _ name: String, paused: Bool = false) -> ClaudeAccountSummary {
        ClaudeAccountSummary(id: id, name: name, colorHex: "#6366F1", isPaused: paused)
    }

    private var mainSummary: ClaudeAccountSummary {
        ClaudeAccountRecord.defaultMain().summary
    }

    /// Every composition and account key currently written.
    private func layoutKeys() -> Set<String> {
        Set(UserDefaults.standard.dictionaryRepresentation().keys.filter {
            $0.hasPrefix("popoverComposition") || $0.hasPrefix("menuBarComposition")
                || $0.hasPrefix("dashboardComposition") || $0 == "focusedClaudeAccount"
                || $0 == "claudeAccounts.v1"
        })
    }

    private func makeStore() -> SettingsStore {
        clean()
        return SettingsStore(notificationService: MockNotificationService(), tokenProvider: MockTokenProvider())
    }

    // MARK: - Storage keys

    @Test("All keeps the pre-modes key, so an existing layout needs no migration")
    func allUsesTheLegacyKey() {
        #expect(ProviderMode.all.storageSuffix.isEmpty)
        #expect(ProviderMode.claude.storageSuffix == ".claude")
        #expect(ProviderMode.codex.storageSuffix == ".codex")
    }

    @Test("A provider mode writes no key until it is actually visited")
    func modeKeysAreLazy() {
        let store = makeStore()
        defer { clean() }

        store.popoverComposition = PopoverBuiltinTemplate.classic.composition
        #expect(UserDefaults.standard.data(forKey: "popoverComposition") != nil)
        #expect(UserDefaults.standard.data(forKey: "popoverComposition.codex") == nil)

        store.activeProviderMode = .codex
        #expect(UserDefaults.standard.data(forKey: "popoverComposition.codex") != nil)
    }

    @Test("Switching away persists the outgoing layout under its own key")
    func switchingPersistsTheOutgoingMode() throws {
        let store = makeStore()
        defer { clean() }

        store.popoverComposition = PopoverBuiltinTemplate.minimalist.composition
        let allKinds = store.popoverComposition.elements.map(\.kind)

        store.activeProviderMode = .codex
        store.activeProviderMode = .all

        #expect(store.popoverComposition.elements.map(\.kind) == allKinds)
    }

    // MARK: - Seeding

    @Test("A mode is seeded by filtering the All layout, never by copying it")
    func seedingFiltersRatherThanCopies() {
        let store = makeStore()
        defer { clean() }

        store.popoverComposition = PopoverBuiltinTemplate.sideBySide.composition
        #expect(store.popoverComposition.elements.contains { $0.kind.provider == .codex })

        store.activeProviderMode = .claude

        // A plain copy would leave the Codex cells in the Claude mode, which is
        // exactly the unreadable popover the modes exist to fix.
        #expect(!store.popoverComposition.elements.contains { $0.kind.provider == .codex })
        #expect(store.popoverComposition.elements.contains { $0.kind.provider == .claude })
    }

    @Test("Chrome, utilities and actions survive every filter")
    func providerlessElementsSurvive() {
        let store = makeStore()
        defer { clean() }

        store.popoverComposition = PopoverBuiltinTemplate.sideBySide.composition
        let chrome = store.popoverComposition.elements.filter { $0.kind.provider == nil }.map(\.kind)
        #expect(!chrome.isEmpty)

        store.activeProviderMode = .codex
        for kind in chrome {
            #expect(store.popoverComposition.elements.contains { $0.kind == kind }, "\(kind.rawValue) vanished")
        }
    }

    @Test("A mode with nothing of its own still gets a usable layout")
    func emptyModeIsSeededFromTheBuiltin() {
        let store = makeStore()
        defer { clean() }

        // Classic holds no Codex cell at all, so filtering it for Codex leaves
        // only chrome. The user must not land on a popover with no metric.
        store.popoverComposition = PopoverBuiltinTemplate.classic.composition
        store.activeProviderMode = .codex

        #expect(store.popoverComposition.elements.contains { $0.kind.provider == .codex })
    }

    // MARK: - Restore

    @Test("Relaunching in a provider mode loads that mode's layout, not All's")
    func restoreLoadsTheModeLayout() {
        let store = makeStore()
        defer { clean() }

        store.popoverComposition = PopoverBuiltinTemplate.minimalist.composition
        store.activeProviderMode = .codex
        let codexKinds = store.popoverComposition.elements.map(\.kind)
        #expect(codexKinds != PopoverBuiltinTemplate.minimalist.composition.elements.map(\.kind))

        // A fresh store reads the same defaults, the way a relaunch would.
        let relaunched = SettingsStore(
            notificationService: MockNotificationService(), tokenProvider: MockTokenProvider()
        )
        #expect(relaunched.activeProviderMode == .codex)
        #expect(relaunched.popoverComposition.elements.map(\.kind) == codexKinds)
    }

    @Test("A layout with no percentage in it is still the user's layout")
    func pacingOnlyLayoutSurvivesAModeSwitch() {
        let store = makeStore()
        defer { clean() }
        store.claudeEnabled = true
        store.codexEnabled = true

        // Pace is a built-in, and the only one carrying no usage element at
        // all. A load gate that asked for a percentage overwrote it with a
        // seeded layout on every switch back into the mode.
        store.activeProviderMode = .codex
        store.popoverComposition = PopoverBuiltinTemplate.pace.composition
        let saved = store.popoverComposition.elements.map(\.kind)

        store.activeProviderMode = .all
        store.activeProviderMode = .codex

        #expect(store.popoverComposition.elements.map(\.kind) == saved)
    }

    // MARK: - Provider symmetry

    @Test("Both providers can be switched off independently")
    func bothProvidersAreToggleable() {
        let store = makeStore()
        defer { clean() }

        store.claudeEnabled = true
        store.codexEnabled = true
        #expect(store.activeProviders == [.claude, .codex])

        store.claudeEnabled = false
        #expect(store.activeProviders == [.codex])

        store.claudeEnabled = true
        store.codexEnabled = false
        #expect(store.activeProviders == [.claude])
    }

    @Test("The mode selector only appears with two providers to choose between")
    func modesNeedTwoProviders() {
        let store = makeStore()
        defer { clean() }

        store.claudeEnabled = true
        store.codexEnabled = false
        #expect(store.modeChoices.isEmpty)

        store.codexEnabled = true
        #expect(store.modeChoices.map(\.mode) == [.all, .claude, .codex])

        // Codex alone offers nothing to switch between either.
        store.claudeEnabled = false
        #expect(store.modeChoices.isEmpty)
    }

    // MARK: - Visibility rule

    @Test("A provider mode hides the other provider and keeps neutral cells")
    func modeVisibilityRule() {
        #expect(ProviderMode.all.shows(.claude))
        #expect(ProviderMode.all.shows(.codex))
        #expect(ProviderMode.all.shows(nil))

        #expect(ProviderMode.claude.shows(.claude))
        #expect(!ProviderMode.claude.shows(.codex))
        #expect(ProviderMode.claude.shows(nil))

        #expect(!ProviderMode.codex.shows(.claude))
        #expect(ProviderMode.codex.shows(.codex))
        #expect(ProviderMode.codex.shows(nil))
    }

    // MARK: - Accounts

    @Test("Without an added account, the keys written are exactly the 6.0 ones")
    func keysMatchSixPointZero() {
        let store = makeStore()
        defer { clean() }
        store.claudeEnabled = true
        store.codexEnabled = true

        store.popoverComposition = PopoverBuiltinTemplate.sideBySide.composition
        store.activeProviderMode = .claude
        store.activeProviderMode = .codex
        store.activeProviderMode = .all

        #expect(layoutKeys() == [
            "popoverComposition", "popoverComposition.claude", "popoverComposition.codex",
            "menuBarComposition", "menuBarComposition.claude", "menuBarComposition.codex",
            "dashboardComposition", "dashboardComposition.claude", "dashboardComposition.codex",
        ])
        #expect(store.compositionSuffix.isEmpty)
        #expect(store.focusedClaudeAccount == .main)
    }

    @Test("An account's Claude mode writes under its own key and leaves Claude's alone")
    func accountModeHasItsOwnKey() throws {
        let store = makeStore()
        defer { clean() }
        store.claudeAccounts = [mainSummary, summary(Self.work, "Work")]

        store.activeProviderMode = .claude
        store.popoverComposition = PopoverBuiltinTemplate.minimalist.composition
        let claudeLayout = try #require(UserDefaults.standard.data(forKey: "popoverComposition.claude")
            .flatMap { try? JSONDecoder().decode(PopoverComposition.self, from: $0) })
        store.activeProviderMode = .all

        store.selectScope(.claude, account: Self.work)
        #expect(store.activeProviderMode == .claude)
        #expect(store.focusedClaudeAccount == Self.work)
        #expect(store.compositionSuffix == ".claude.acct-work")
        // Seeded from Claude's own layout.
        #expect(store.popoverComposition.elements.map(\.kind) == PopoverBuiltinTemplate.minimalist.composition.elements.map(\.kind))
        store.popoverComposition = PopoverBuiltinTemplate.compact.composition
        #expect(UserDefaults.standard.data(forKey: "popoverComposition.claude.acct-work") != nil)
        #expect(UserDefaults.standard.string(forKey: "focusedClaudeAccount") == "acct-work")
        #expect(UserDefaults.standard.data(forKey: "popoverComposition.claude")
            .flatMap { try? JSONDecoder().decode(PopoverComposition.self, from: $0) } == claudeLayout)

        store.selectScope(.claude, account: .main)
        #expect(store.popoverComposition.elements.map(\.kind) == PopoverBuiltinTemplate.minimalist.composition.elements.map(\.kind))
        #expect(UserDefaults.standard.string(forKey: "focusedClaudeAccount") == nil)

        store.selectScope(.claude, account: Self.work)
        #expect(store.popoverComposition.elements.map(\.kind) == PopoverBuiltinTemplate.compact.composition.elements.map(\.kind))
    }

    @Test("Seeding Claude mode keeps only what belongs to the account on screen")
    func claudeSeedDropsOtherAccounts() {
        let store = makeStore()
        defer { clean() }
        store.claudeAccounts = [mainSummary, summary(Self.work, "Work")]
        var all = PopoverBuiltinTemplate.classic.composition
        all.elements.append(PopoverElement(kind: .weekly, style: .chip, width: .half, account: Self.work))
        store.popoverComposition = all

        store.activeProviderMode = .claude
        #expect(!store.popoverComposition.elements.contains { $0.account != nil })
        #expect(store.popoverComposition.elements.count == PopoverBuiltinTemplate.classic.composition.elements.count)
    }

    @Test("Claude mode on an account that gets paused goes back to the main account")
    func pausedFocusFallsBack() {
        let store = makeStore()
        defer { clean() }
        store.claudeAccounts = [mainSummary, summary(Self.work, "Work")]
        store.selectScope(.claude, account: Self.work)
        store.popoverComposition = PopoverBuiltinTemplate.compact.composition

        store.claudeAccounts = [mainSummary, summary(Self.work, "Work", paused: true)]
        #expect(store.focusedClaudeAccount == .main)
        #expect(store.activeProviderMode == .claude)
        #expect(store.compositionSuffix == ".claude")
        // Saved before leaving.
        #expect(UserDefaults.standard.data(forKey: "popoverComposition.claude.acct-work") != nil)
    }

    @Test("A relaunch restores the focused account, unless it stopped running")
    func restoreFocusedAccount() {
        let store = makeStore()
        defer { clean() }
        store.claudeAccounts = [mainSummary, summary(Self.work, "Work")]
        UserDefaults.standard.set(ClaudeAccountsStorage.encode([
            .defaultMain(),
            ClaudeAccountRecord(id: Self.work, configDir: "/tmp/w", name: "Work", colorHex: "#6366F1"),
        ]), forKey: "claudeAccounts.v1")
        store.selectScope(.claude, account: Self.work)
        store.popoverComposition = PopoverBuiltinTemplate.compact.composition

        let relaunched = SettingsStore(notificationService: MockNotificationService(), tokenProvider: MockTokenProvider())
        #expect(relaunched.focusedClaudeAccount == Self.work)
        #expect(relaunched.compositionSuffix == ".claude.acct-work")
        #expect(relaunched.popoverComposition.elements.map(\.kind) == PopoverBuiltinTemplate.compact.composition.elements.map(\.kind))

        UserDefaults.standard.set(ClaudeAccountsStorage.encode([.defaultMain()]), forKey: "claudeAccounts.v1")
        let afterRemoval = SettingsStore(notificationService: MockNotificationService(), tokenProvider: MockTokenProvider())
        #expect(afterRemoval.focusedClaudeAccount == .main)
        #expect(afterRemoval.compositionSuffix == ".claude")
    }

    @Test("One pill per running Claude account, Codex last, nothing below two")
    func modeChoices() {
        let store = makeStore()
        defer { clean() }
        store.claudeEnabled = true
        store.codexEnabled = false
        store.claudeAccounts = [mainSummary]
        #expect(store.modeChoices.isEmpty)

        store.codexEnabled = true
        #expect(store.modeChoices.map(\.id) == ["all", "claude", "codex"])

        store.codexEnabled = false
        store.claudeAccounts = [mainSummary, summary(Self.work, "Work")]
        #expect(store.modeChoices.map(\.id) == ["all", "claude", "claude.acct-work"])

        store.codexEnabled = true
        store.claudeAccounts = [mainSummary, summary(Self.work, "Work"), summary(Self.side, "Side")]
        #expect(store.modeChoices.map(\.id) == ["all", "claude", "claude.acct-work", "claude.acct-side", "codex"])

        store.claudeAccounts = [mainSummary, summary(Self.work, "Work", paused: true), summary(Self.side, "Side")]
        #expect(store.modeChoices.map(\.id) == ["all", "claude", "claude.acct-side", "codex"])

        // Claude off stops every account.
        store.claudeEnabled = false
        #expect(store.activeClaudeAccounts.isEmpty)
        #expect(store.modeChoices.isEmpty)
    }

    @Test("The Claude accounts fold into one menu pill from three running accounts")
    func claudeMenuFromThree() {
        let main = ModeChoice(mode: .claude, account: .main)
        let work = ModeChoice(mode: .claude, account: Self.work)
        let side = ModeChoice(mode: .claude, account: Self.side)
        let all = ModeChoice(mode: .all)
        let codex = ModeChoice(mode: .codex)
        #expect(!ModeChoice.collapsesClaude([]))
        #expect(!ModeChoice.collapsesClaude([all, main, codex]))
        #expect(!ModeChoice.collapsesClaude([all, main, work, codex]))
        #expect(ModeChoice.collapsesClaude([all, main, work, side]))
        #expect(ModeChoice.collapsesClaude([all, main, work, side, codex]))
    }

    @Test("Markers start at two running accounts, paused ones and Claude off excluded")
    func markersNeedTwoRunningAccounts() {
        let store = makeStore()
        defer { clean() }
        store.claudeEnabled = true
        store.claudeAccounts = [mainSummary]
        #expect(!store.showsAccountMarkers)
        store.claudeAccounts = [mainSummary, summary(Self.work, "Work", paused: true)]
        #expect(!store.showsAccountMarkers)
        store.claudeAccounts = [mainSummary, summary(Self.work, "Work")]
        #expect(store.showsAccountMarkers)
        #expect(store.runningClaudeAccountIDs == [.main, Self.work])
        store.claudeEnabled = false
        #expect(!store.showsAccountMarkers)
        #expect(store.runningClaudeAccountIDs.isEmpty)
    }

    @Test("A pill is selected when its mode and, for Claude, its account are on screen")
    func pillSelection() {
        let store = makeStore()
        defer { clean() }
        store.claudeEnabled = true
        store.codexEnabled = true
        store.claudeAccounts = [mainSummary, summary(Self.work, "Work")]
        store.selectScope(.all)
        #expect(store.isSelected(ModeChoice(mode: .all)))
        #expect(!store.isSelected(ModeChoice(mode: .claude, account: .main)))

        store.selectScope(.claude, account: Self.work)
        #expect(store.isSelected(ModeChoice(mode: .claude, account: Self.work)))
        #expect(!store.isSelected(ModeChoice(mode: .claude, account: .main)))
        #expect(!store.isSelected(ModeChoice(mode: .all)))

        // Codex keeps the focused account for the way back to Claude, and
        // no Claude pill reads as selected meanwhile.
        store.selectScope(.codex)
        #expect(store.isSelected(ModeChoice(mode: .codex)))
        #expect(!store.isSelected(ModeChoice(mode: .claude, account: Self.work)))
        store.selectScope(.all)
    }

    @Test("An element reads its own running account, else the mode's account")
    func effectiveAccountRule() {
        let running: Set<AccountID> = [.main, Self.work]
        func effective(_ declared: AccountID?, _ mode: ProviderMode, _ focused: AccountID = .main) -> AccountID? {
            AccountID.effective(declared: declared, mode: mode, focused: focused, running: running)
        }
        #expect(effective(nil, .all) == .main)
        #expect(effective(nil, .claude, Self.work) == Self.work)
        #expect(effective(nil, .codex, Self.work) == .main)
        #expect(effective(Self.work, .all) == Self.work)
        #expect(effective(Self.work, .claude, .main) == Self.work)
        #expect(effective(.main, .claude, Self.work) == .main)
        // Paused or removed: drawn nowhere.
        #expect(effective(Self.side, .all) == nil)
        // A focus left on an account that stopped falls back to the main one.
        #expect(effective(nil, .claude, Self.side) == .main)
    }

    @Test("Removing an account purges its layouts, its pinned cells and templates, its glance card")
    func purgeAccount() throws {
        let store = makeStore()
        defer {
            clean()
            store.popoverUserTemplates = []
            store.menuBarUserTemplates = []
        }
        store.claudeAccounts = [mainSummary, summary(Self.work, "Work")]

        var popover = PopoverBuiltinTemplate.classic.composition
        popover.elements.append(PopoverElement(kind: .session, style: .chip, width: .half, account: Self.work))
        store.popoverComposition = popover
        var bar = MenuBarBuiltinTemplate.classic.composition
        bar.segments.append(MenuBarSegment(kind: .session, style: .labelValue, account: Self.work))
        store.menuBarComposition = bar
        store.popoverUserTemplates = [PopoverUserTemplate(name: "T", composition: popover)]
        store.menuBarUserTemplates = [MenuBarUserTemplate(name: "T", composition: bar)]
        store.setHeroWindow("weekly", for: .claude, account: Self.work)
        store.setHeroWindow("session", for: .claude)

        store.selectScope(.claude, account: Self.work)
        store.selectScope(.codex)
        #expect(UserDefaults.standard.data(forKey: "popoverComposition.claude.acct-work") != nil)
        // A saved All layout that still targets the account.
        store.selectScope(.all)
        store.selectScope(.codex)

        store.claudeAccounts = [mainSummary]
        store.purgeAccount(Self.work)

        for base in ["popoverComposition", "menuBarComposition", "dashboardComposition"] {
            #expect(UserDefaults.standard.data(forKey: base + ".claude.acct-work") == nil)
        }
        let savedAll = try #require(UserDefaults.standard.data(forKey: "popoverComposition"))
        #expect(!(try JSONDecoder().decode(PopoverComposition.self, from: savedAll)).elements.contains { $0.account != nil })
        let savedBar = try #require(UserDefaults.standard.data(forKey: "menuBarComposition"))
        #expect(!(try JSONDecoder().decode(MenuBarComposition.self, from: savedBar)).segments.contains { $0.account != nil })
        #expect(!store.popoverUserTemplates[0].composition.elements.contains { $0.account != nil })
        #expect(!store.menuBarUserTemplates[0].composition.segments.contains { $0.account != nil })
        #expect(store.heroWindow(for: .claude, account: Self.work) == nil)
        #expect(store.heroWindow(for: .claude) == "session")
    }

    @Test("The glance card key is the provider's for the main account, suffixed for another")
    func heroWindowKeys() {
        let store = makeStore()
        defer { clean() }
        #expect(store.heroWindowKey(.claude) == "claude")
        #expect(store.heroWindowKey(.claude, account: Self.work) == "claude.acct-work")
        #expect(store.heroWindowKey(.codex, account: Self.work) == "codex")
    }

    // MARK: - Seeding an added account

    @Test("In All, a new account gets a popover section and, when asked, its menu bar segments")
    func seedAccountInAll() {
        let store = makeStore()
        defer { clean() }
        store.claudeEnabled = true
        store.codexEnabled = true
        store.claudeAccounts = [mainSummary, summary(Self.work, "Work")]
        store.seedAccount(Self.work, addToMenuBar: true)

        let pinned = store.popoverComposition.elements.filter { $0.account == Self.work }
        #expect(pinned.map(\.kind) == [.session, .weekly])
        #expect(pinned.allSatisfy { $0.style == .chip && $0.width == .half })
        #expect(store.menuBarComposition.segments.filter { $0.account == Self.work }.map(\.kind) == [.session, .weekly])

        // Persisted under the All keys, which are the published ones here.
        let saved = UserDefaults.standard.data(forKey: "menuBarComposition")
            .flatMap { try? JSONDecoder().decode(MenuBarComposition.self, from: $0) }
        #expect(saved?.segments.contains { $0.account == Self.work } == true)
    }

    @Test("Leaving the menu bar unchecked leaves it exactly as it was")
    func seedAccountWithoutMenuBar() {
        let store = makeStore()
        defer { clean() }
        let before = store.menuBarComposition
        store.seedAccount(Self.work, addToMenuBar: false)
        #expect(store.menuBarComposition == before)
        #expect(store.popoverComposition.elements.contains { $0.account == Self.work })
    }

    @Test("In Codex mode, the All layouts are updated in storage and Codex's own stay put")
    func seedAccountFromCodexMode() throws {
        let store = makeStore()
        defer { clean() }
        store.claudeEnabled = true
        store.codexEnabled = true
        store.activeProviderMode = .codex
        let codexPopover = store.popoverComposition
        let codexMenuBar = store.menuBarComposition

        store.seedAccount(Self.work, addToMenuBar: true)

        #expect(store.popoverComposition == codexPopover)
        #expect(store.menuBarComposition == codexMenuBar)
        let allPopover = try #require(UserDefaults.standard.data(forKey: "popoverComposition")
            .flatMap { try? JSONDecoder().decode(PopoverComposition.self, from: $0) })
        #expect(allPopover.elements.filter { $0.account == Self.work }.count == 2)
        let allMenuBar = try #require(UserDefaults.standard.data(forKey: "menuBarComposition")
            .flatMap { try? JSONDecoder().decode(MenuBarComposition.self, from: $0) })
        #expect(allMenuBar.segments.filter { $0.account == Self.work }.count == 2)

        // Back in All, the account is there.
        store.activeProviderMode = .all
        #expect(store.menuBarComposition.segments.contains { $0.account == Self.work })
        #expect(store.popoverComposition.elements.contains { $0.account == Self.work })
    }

    @Test("The demo's running accounts land in the All layouts, paused and real ones do not")
    func demoSeedsItsAccounts() {
        let store = makeStore()
        defer { clean() }
        let home = ClaudeConfigDirResolver.realHome()
        let records = [ClaudeAccountRecord.defaultMain()]
            + DemoFixtures.seeded.map { DemoFixtures.record(for: $0, home: home, now: Date()) }
            + [ClaudeAccountRecord(id: Self.side, configDir: home + "/.claude-side", name: "Side", colorHex: "#22D3EE")]
        store.claudeEnabled = true
        store.codexEnabled = true
        store.claudeAccounts = records.map(\.summary)
        store.activeProviderMode = .claude

        DemoLaunch.seedLayouts(for: records, into: store, home: home)

        #expect(store.activeProviderMode == .all)
        let running = DemoFixtures.seeded.filter { !(DemoFixtures.record(for: $0, home: home, now: Date()).isPaused) }
        #expect(running.contains(DemoFixtures.work) && running.contains(DemoFixtures.side))
        for fixture in DemoFixtures.seeded {
            let inPopover = store.popoverComposition.elements.contains { $0.account == fixture.accountID }
            let inMenuBar = store.menuBarComposition.segments.contains { $0.account == fixture.accountID }
            #expect(inPopover == running.contains(fixture))
            #expect(inMenuBar == running.contains(fixture))
        }
        #expect(!store.popoverComposition.elements.contains { $0.account == Self.side })
        #expect(!store.menuBarComposition.segments.contains { $0.account == Self.side })
        // In list order, Work's run before Side project's.
        let order = store.menuBarComposition.segments.compactMap(\.account)
        let work = order.firstIndex(of: DemoFixtures.work.accountID)
        let side = order.firstIndex(of: DemoFixtures.side.accountID)
        #expect(work != nil && side != nil && work! < side!)
    }

    @Test("The main account is never seeded")
    func seedAccountIgnoresMain() {
        let store = makeStore()
        defer { clean() }
        let popover = store.popoverComposition
        let menuBar = store.menuBarComposition
        store.seedAccount(.main, addToMenuBar: true)
        #expect(store.popoverComposition == popover)
        #expect(store.menuBarComposition == menuBar)
    }
}

/// A mode is a view of what is on, so it cannot outlive what it was a view of.
@Suite("Provider mode reconciliation", .serialized)
@MainActor
struct ProviderModeReconciliationTests {

    private func makeStore() -> SettingsStore {
        for key in ["claudeEnabled", "codexEnabled", "activeProviderMode",
                    "popoverComposition", "popoverComposition.claude", "popoverComposition.codex",
                    "menuBarComposition", "menuBarComposition.claude", "menuBarComposition.codex"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return SettingsStore(notificationService: MockNotificationService(), tokenProvider: MockTokenProvider())
    }

    @Test("Turning off the provider the app is filtered to falls back to All")
    func turningOffTheActiveProviderResetsTheMode() {
        let store = makeStore()
        store.claudeEnabled = true
        store.codexEnabled = true
        store.activeProviderMode = .claude

        // Without this the mode filtered for a provider `activeProviders` no
        // longer contained, every surface resolved to an empty set, and the
        // dashboard rendered nothing at all.
        store.claudeEnabled = false
        #expect(store.activeProviderMode == .all)
        #expect(store.activeProviders == [.codex])
    }

    @Test("The mirror case behaves the same")
    func turningOffCodexFromCodexMode() {
        let store = makeStore()
        store.claudeEnabled = true
        store.codexEnabled = true
        store.activeProviderMode = .codex

        store.codexEnabled = false
        #expect(store.activeProviderMode == .all)
        #expect(store.activeProviders == [.claude])
    }

    @Test("Turning off the other provider leaves the mode alone")
    func unrelatedToggleDoesNotResetTheMode() {
        let store = makeStore()
        store.claudeEnabled = true
        store.codexEnabled = true
        store.activeProviderMode = .claude

        store.codexEnabled = false
        // Claude mode still describes something that exists, so it stands.
        #expect(store.activeProviderMode == .claude)
    }

    @Test("Whatever is on, something is always visible")
    func noCombinationRendersNothing() {
        let store = makeStore()
        for (claude, codex) in [(true, true), (true, false), (false, true)] {
            store.claudeEnabled = true
            store.codexEnabled = true
            for mode in ProviderMode.allCases {
                store.activeProviderMode = mode
                store.claudeEnabled = claude
                store.codexEnabled = codex
                let visible = store.activeProviders.filter { store.activeProviderMode.shows($0) }
                #expect(!visible.isEmpty,
                        "claude=\(claude) codex=\(codex) mode=\(mode.rawValue) renders an empty page")
            }
        }
    }
}
