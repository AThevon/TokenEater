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
        "activeProviderMode", "codexEnabled",
    ]

    private func clean() {
        for key in Self.keys { UserDefaults.standard.removeObject(forKey: key) }
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
        #expect(store.availableProviderModes.isEmpty)

        store.codexEnabled = true
        #expect(store.availableProviderModes == [.all, .claude, .codex])

        // Codex alone offers nothing to switch between either.
        store.claudeEnabled = false
        #expect(store.availableProviderModes.isEmpty)
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
