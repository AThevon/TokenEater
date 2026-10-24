import Testing
import Foundation

@Suite("Home section order")
struct HomeSectionOrderTests {

    private static let work = AccountID(rawValue: "acct-work")
    private static let side = AccountID(rawValue: "acct-side")
    private static let accounts = [AccountID.main, work, side]

    @Test("Storage ids are the account's own id, or codex")
    func storageIDs() {
        #expect(HomeSection.claude(.main).storageID == "main")
        #expect(HomeSection.claude(Self.work).storageID == "acct-work")
        #expect(HomeSection.codex.storageID == "codex")
        #expect(HomeSection(storageID: "main") == .claude(.main))
        #expect(HomeSection(storageID: "acct-work") == .claude(Self.work))
        #expect(HomeSection(storageID: "codex") == .codex)
        for bad in ["", "claude", "acct-", "ACCT-x", "acct-../x", "claudeWork", "Codex"] {
            #expect(HomeSection(storageID: bad) == nil)
        }
    }

    @Test("Nothing stored: main and Codex as in 6.0, then the added accounts as tracked")
    func defaultOrder() {
        #expect(HomeSectionOrder.reconciled([], accounts: Self.accounts)
                == [.claude(.main), .codex, .claude(Self.work), .claude(Self.side)])
        #expect(HomeSectionOrder.reconciled([], accounts: [.main]) == [.claude(.main), .codex])
    }

    @Test("A new account lands at the end, whether the order was rearranged or not")
    func newAccountAlwaysLast() {
        let untouched = HomeSectionOrder.reconciled([], accounts: [.main, Self.work])
        let touched = HomeSectionOrder.reconciled(untouched.map(\.storageID), accounts: [.main, Self.work])
        #expect(untouched == touched)
        #expect(HomeSectionOrder.reconciled([], accounts: Self.accounts).last == .claude(Self.side))
        #expect(HomeSectionOrder.reconciled(touched.map(\.storageID), accounts: Self.accounts).last == .claude(Self.side))
    }

    @Test("A stored order is kept, and a new account goes at the end")
    func storedOrderWins() {
        let stored = ["codex", "acct-work", "main"]
        #expect(HomeSectionOrder.reconciled(stored, accounts: Self.accounts)
                == [.codex, .claude(Self.work), .claude(.main), .claude(Self.side)])
    }

    @Test("Unknown, malformed, repeated or removed ids are dropped")
    func badIDsDrop() {
        let stored = ["acct-gone", "codex", "nonsense", "codex", "acct-side", "", "main"]
        #expect(HomeSectionOrder.reconciled(stored, accounts: Self.accounts)
                == [.codex, .claude(Self.side), .claude(.main), .claude(Self.work)])
    }

    @Test("Rearranging the visible sections keeps the place of the hidden ones")
    func applyingKeepsHiddenSlots() {
        let full: [HomeSection] = [.claude(.main), .claude(Self.work), .codex, .claude(Self.side)]
        // Work is paused: the user swaps Codex and Side project.
        let visible: [HomeSection] = [.claude(.main), .claude(Self.side), .codex]
        #expect(HomeSectionOrder.applying(visible, to: full)
                == [.claude(.main), .claude(Self.work), .claude(Self.side), .codex])
        // Nothing moved: nothing changes.
        #expect(HomeSectionOrder.applying([.claude(.main), .codex, .claude(Self.side)], to: full) == full)
    }
}
