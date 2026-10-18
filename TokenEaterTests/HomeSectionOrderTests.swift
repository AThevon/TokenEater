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

    @Test("Nothing stored: the accounts as tracked, main first, then Codex")
    func defaultOrder() {
        #expect(HomeSectionOrder.reconciled([], accounts: Self.accounts)
                == [.claude(.main), .claude(Self.work), .claude(Self.side), .codex])
        #expect(HomeSectionOrder.reconciled([], accounts: [.main]) == [.claude(.main), .codex])
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
