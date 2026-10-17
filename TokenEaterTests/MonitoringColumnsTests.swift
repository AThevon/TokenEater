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
}
