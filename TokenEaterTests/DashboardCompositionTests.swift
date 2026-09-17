import Testing
import Foundation

/// The dashboard's block list is the thing three hand-written layouts used to
/// be. These pin the properties that make replacing them safe.
@Suite("Dashboard composition")
struct DashboardCompositionTests {

    @Test("The default reproduces the layout the page has always had")
    func defaultIsTodaysPage() {
        // Anyone who never opens the editor must see no change at all.
        #expect(DashboardComposition.default.visibleBlocks
                == [.hero, .windows, .pacing, .extraCredits, .footer])
        #expect(DashboardComposition.default.entries.allSatisfy { !$0.isHidden })
    }

    @Test("Hiding keeps the block, it does not delete it")
    func hidingIsReversible() {
        var composition = DashboardComposition.default
        composition.entries[0].isHidden = true
        #expect(composition.visibleBlocks.count == DashboardBlock.allCases.count - 1)
        #expect(composition.entries.count == DashboardBlock.allCases.count)
    }

    @Test("A composition round-trips unchanged")
    func roundTrip() throws {
        var original = DashboardComposition.default
        original.entries.reverse()
        original.entries[1].isHidden = true
        let decoded = try JSONDecoder().decode(
            DashboardComposition.self, from: JSONEncoder().encode(original)
        )
        #expect(decoded == original)
    }

    @Test("A block this build does not know is dropped, the rest survives")
    func unknownBlockIsDropped() throws {
        let json = """
        {"version": 1, "entries": [
          {"block": "hero", "isHidden": false},
          {"block": "gemini", "isHidden": false},
          {"block": "pacing", "isHidden": true}
        ]}
        """
        let decoded = try JSONDecoder().decode(DashboardComposition.self, from: Data(json.utf8))
        #expect(decoded.entries.map(\.block) == [.hero, .pacing])
    }

    @Test("A block added since the layout was saved is appended, never lost")
    func newBlocksAreAppended() throws {
        // Otherwise a user who saved a layout before a block existed would
        // never see that block, with nothing in the UI to explain why.
        let partial = DashboardComposition(entries: [.init(block: .hero)])
        let reconciled = DashboardComposition.reconciled(partial)
        #expect(Set(reconciled.entries.map(\.block)) == Set(DashboardBlock.allCases))
        #expect(reconciled.entries.first?.block == .hero)
        #expect(reconciled.entries.dropFirst().allSatisfy { !$0.isHidden })
    }

    @Test("Reconciling is idempotent")
    func reconcileTwiceChangesNothing() {
        let once = DashboardComposition.reconciled(.default)
        #expect(DashboardComposition.reconciled(once) == once)
    }

    @Test("Every block declares who can draw it, and at least one provider can")
    func providerCoverage() {
        for block in DashboardBlock.allCases {
            #expect(!block.providers.isEmpty, "\(block.rawValue) is drawable by nobody")
            #expect(!block.localizedName.isEmpty)
            #expect(!block.symbolName.isEmpty)
        }
        // Extra Credits is Claude's paid pool; Codex has no equivalent.
        #expect(DashboardBlock.extraCredits.providers == [.claude])
    }

    @Test("An empty stored list falls back rather than rendering nothing")
    func emptyFallsBack() throws {
        let decoded = try JSONDecoder().decode(
            DashboardComposition.self, from: Data(#"{"version":1,"entries":[]}"#.utf8)
        )
        #expect(decoded.entries.isEmpty)
        // The store treats an empty decode as "no layout saved" and uses the
        // default, so the page can never come up blank.
        #expect(!DashboardComposition.reconciled(decoded).entries.isEmpty)
    }
}
