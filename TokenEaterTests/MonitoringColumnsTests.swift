import Testing
import Foundation

@Suite("MonitoringColumns")
struct MonitoringColumnsTests {

    private static let work = AccountID(rawValue: "acct-work")
    private static let side = AccountID(rawValue: "acct-side")

    private func columns(
        _ mode: ProviderMode,
        focused: AccountID = .main,
        accounts: [AccountID] = [.main],
        codex: Bool = true
    ) -> [MonitoringColumns.Column] {
        MonitoringColumns.columns(mode: mode, focused: focused, activeAccounts: accounts, codexEnabled: codex)
    }

    @Test("A single account keeps the two columns the dashboard always had")
    func singleAccount() {
        #expect(columns(.all) == [.claude(.main), .codex])
        #expect(columns(.all, codex: false) == [.claude(.main)])
        #expect(columns(.claude) == [.claude(.main)])
        #expect(columns(.codex) == [.codex])
    }

    @Test("All puts every running Claude account first, main first, then Codex")
    func everyAccountInAll() {
        let accounts = [AccountID.main, Self.work, Self.side]
        #expect(columns(.all, accounts: accounts) == [.claude(.main), .claude(Self.work), .claude(Self.side), .codex])
        #expect(columns(.all, accounts: accounts, codex: false) == [.claude(.main), .claude(Self.work), .claude(Self.side)])
    }

    @Test("Claude mode shows the focused account, or the main one when it stopped")
    func claudeModeShowsTheFocus() {
        let accounts = [AccountID.main, Self.work]
        #expect(columns(.claude, focused: Self.work, accounts: accounts) == [.claude(Self.work)])
        #expect(columns(.claude, focused: Self.side, accounts: accounts) == [.claude(.main)])
    }

    @Test("Claude off leaves Codex alone, Codex off leaves Claude alone")
    func providersOff() {
        #expect(columns(.all, accounts: []) == [.codex])
        #expect(columns(.claude, accounts: []).isEmpty)
        #expect(columns(.codex, codex: false).isEmpty)
    }

    @Test("Column ids keep the main account on the plain Claude key")
    func columnIDs() {
        #expect(MonitoringColumns.Column.claude(.main).id == "claude")
        #expect(MonitoringColumns.Column.claude(Self.work).id == "claude.acct-work")
        #expect(MonitoringColumns.Column.codex.id == "codex")
        #expect(MonitoringColumns.Column.claude(Self.work).provider == .claude)
    }

    // MARK: - Rows

    private static let third = AccountID(rawValue: "acct-third")

    private func rowShape(_ columns: [MonitoringColumns.Column], twoAbreast: Bool = true) -> [[MonitoringColumns.Column]] {
        MonitoringColumns.rows(columns, twoAbreast: twoAbreast)
    }

    @Test("One or two columns stay on one row, narrow or not, as in 6.0")
    func twoColumnsNeverWrap() {
        #expect(rowShape([]).isEmpty)
        for twoAbreast in [true, false] {
            #expect(rowShape([.claude(.main)], twoAbreast: twoAbreast) == [[.claude(.main)]])
            #expect(rowShape([.claude(.main), .codex], twoAbreast: twoAbreast) == [[.claude(.main), .codex]])
            #expect(rowShape([.claude(.main), .claude(Self.work)], twoAbreast: twoAbreast)
                    == [[.claude(.main), .claude(Self.work)]])
        }
    }

    @Test("From three columns, never more than two per row, Codex last")
    func neverThreeAbreast() {
        let columns: [MonitoringColumns.Column] = [.claude(.main), .claude(Self.work), .claude(Self.side), .codex]
        let rows = rowShape(columns)
        #expect(rows.allSatisfy { $0.count <= 2 })
        #expect(rows == [[.claude(.main), .claude(Self.work)], [.claude(Self.side), .codex]])
        let three: [MonitoringColumns.Column] = [.claude(.main), .claude(Self.work), .codex]
        #expect(rowShape(three) == [[.claude(.main), .claude(Self.work)], [.codex]])
        let five: [MonitoringColumns.Column] = [.claude(.main), .claude(Self.work), .claude(Self.side), .claude(Self.third), .codex]
        #expect(rowShape(five).map(\.count) == [2, 2, 1])
        #expect(rowShape(five).last == [.codex])
    }

    @Test("Several columns stack one per row when two would be too narrow")
    func narrowStacks() {
        let columns: [MonitoringColumns.Column] = [.claude(.main), .claude(Self.work), .codex]
        #expect(rowShape(columns, twoAbreast: false) == [[.claude(.main)], [.claude(Self.work)], [.codex]])
    }

    @Test("Two abreast needs two columns at their minimum width plus the gap")
    func twoAbreastThreshold() {
        #expect(MonitoringColumns.twoAbreastMinimumWidth(spacing: 16) == MonitoringColumns.minimumSideBySideWidth * 2 + 16)
        // The page's content at a 760 pt window (minus the window and page
        // padding) is narrower; at 800 pt it is wide enough.
        #expect(760 - 24 - 32 < MonitoringColumns.twoAbreastMinimumWidth(spacing: 16))
        #expect(800 - 24 - 32 >= MonitoringColumns.twoAbreastMinimumWidth(spacing: 16))
    }
}
