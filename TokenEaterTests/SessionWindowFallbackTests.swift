import Testing
import Foundation

@Suite("SessionWindowFallback")
struct SessionWindowFallbackTests {
    typealias Item = SessionWindowFallback.Item<String>

    private let ultra = AccountID.main
    private let max = AccountID(rawValue: "acct-1")

    private func item(
        _ id: String, _ role: SessionWindowFallback.Role, account: AccountID? = .main,
        lacks: Bool = true, shows: String = "percent", width: Int = 1
    ) -> Item {
        Item(id: id, role: role, account: account, lacksSessionWindow: lacks, shows: shows, width: width)
    }

    @Test("an account with the window draws everything as stored")
    func withWindowNothingChanges() {
        let items = [
            item("s", .session, lacks: false), item("w", .weekly, lacks: false),
            item("sp", .sessionPacing, lacks: false, shows: "pace"), item("r", .sessionOnly, lacks: false),
        ]
        let out = SessionWindowFallback.outcomes(for: items)
        #expect(out.values.allSatisfy { $0 == SessionWindowFallback.Outcome.unchanged })
    }

    @Test("Classic: the session ring steps aside for the weekly ring of equal width")
    func classicTwins() {
        let out = SessionWindowFallback.outcomes(for: [
            item("s", .session), item("w", .weekly),
            item("sp", .sessionPacing, shows: "pace"), item("wp", .weeklyPacing, shows: "pace"),
        ])
        #expect(out["s"] == SessionWindowFallback.Outcome.dropped)
        #expect(out["w"] == SessionWindowFallback.Outcome.unchanged)
        #expect(out["sp"] == SessionWindowFallback.Outcome.dropped)
        #expect(out["wp"] == SessionWindowFallback.Outcome.unchanged)
    }

    @Test("Complete: a wider session hero takes the week and the small weekly ring steps aside")
    func widerSessionSlotWins() {
        let out = SessionWindowFallback.outcomes(for: [
            item("hero", .session, width: 3), item("w", .weekly, width: 1),
        ])
        #expect(out["hero"] == SessionWindowFallback.Outcome.renderedAsWeekly)
        #expect(out["w"] == SessionWindowFallback.Outcome.shownBySessionSlot)
    }

    @Test("a session slot with no weekly twin shows the week in its place")
    func loneSessionSlot() {
        let out = SessionWindowFallback.outcomes(for: [
            item("s", .session), item("sp", .sessionPacing, shows: "pace"), item("r", .sessionOnly),
        ])
        #expect(out["s"] == SessionWindowFallback.Outcome.renderedAsWeekly)
        #expect(out["sp"] == SessionWindowFallback.Outcome.renderedAsWeekly)
        #expect(out["r"] == SessionWindowFallback.Outcome.dropped)
    }

    @Test("Focus: a countdown arc is not the twin of a weekly percentage")
    func differentFactsAreNotTwins() {
        let out = SessionWindowFallback.outcomes(for: [
            item("arc", .session, shows: "countdown", width: 3),
            item("w", .weekly, shows: "percent", width: 1),
        ])
        #expect(out["arc"] == SessionWindowFallback.Outcome.renderedAsWeekly)
        #expect(out["w"] == SessionWindowFallback.Outcome.unchanged)
    }

    @Test("two session slots never draw the week twice")
    func twoSessionSlots() {
        let out = SessionWindowFallback.outcomes(for: [
            item("a", .session, width: 1), item("b", .session, width: 2),
        ])
        #expect(out["b"] == SessionWindowFallback.Outcome.renderedAsWeekly)
        #expect(out["a"] == SessionWindowFallback.Outcome.dropped)
    }

    @Test("twins are looked for within one account only")
    func perAccount() {
        let out = SessionWindowFallback.outcomes(for: [
            item("ultraSession", .session, account: ultra),
            item("maxSession", .session, account: max, lacks: false),
            item("maxWeekly", .weekly, account: max, lacks: false),
        ])
        // Ultra's session slot has no weekly twin of its own account.
        #expect(out["ultraSession"] == SessionWindowFallback.Outcome.renderedAsWeekly)
        #expect(out["maxSession"] == SessionWindowFallback.Outcome.unchanged)
        #expect(out["maxWeekly"] == SessionWindowFallback.Outcome.unchanged)
    }

    @Test("a layout that shows the week twice on its own is left alone")
    func ownDuplicatesKept() {
        let out = SessionWindowFallback.outcomes(for: [
            item("w1", .weekly), item("w2", .weekly), item("other", .other),
        ])
        #expect(out.values.allSatisfy { $0 == SessionWindowFallback.Outcome.unchanged })
    }

    @Test("on a tie the layout's own weekly element is kept, whatever the order")
    func tieKeepsRealWeekly() {
        let out = SessionWindowFallback.outcomes(for: [item("w", .weekly), item("s", .session)])
        #expect(out["w"] == SessionWindowFallback.Outcome.unchanged)
        #expect(out["s"] == SessionWindowFallback.Outcome.dropped)
    }
}
