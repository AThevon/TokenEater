import Testing
import Foundation

@Suite("MonitoringColumns")
struct MonitoringColumnsTests {

    private static let work = AccountID(rawValue: "acct-work")
    private static let side = AccountID(rawValue: "acct-side")
    private static let old = AccountID(rawValue: "acct-old")

    private func columns(
        _ mode: ProviderMode,
        focused: AccountID = .main,
        sections: [HomeSection] = [.claude(.main), .codex]
    ) -> [HomeSection] {
        MonitoringColumns.columns(mode: mode, focused: focused, sections: sections)
    }

    // MARK: - Which sections

    @Test("All shows every running section, in the order it is given")
    func allFollowsTheOrder() {
        #expect(columns(.all) == [.claude(.main), .codex])
        let custom: [HomeSection] = [.codex, .claude(Self.work), .claude(.main)]
        #expect(columns(.all, sections: custom) == custom)
    }

    @Test("Claude mode shows the focused account, or the main one when it stopped")
    func claudeModeShowsTheFocus() {
        let sections: [HomeSection] = [.claude(Self.work), .codex, .claude(.main)]
        #expect(columns(.claude, focused: Self.work, sections: sections) == [.claude(Self.work)])
        #expect(columns(.claude, focused: Self.side, sections: sections) == [.claude(.main)])
    }

    @Test("Claude off leaves Codex alone, Codex off leaves Claude alone")
    func providersOff() {
        #expect(columns(.all, sections: [.codex]) == [.codex])
        #expect(columns(.claude, sections: [.codex]).isEmpty)
        #expect(columns(.codex, sections: [.claude(.main)]).isEmpty)
        #expect(columns(.codex) == [.codex])
    }

    // MARK: - Layout

    @Test("One section has the page in every layout")
    func oneSection() {
        for layout in HomeLayout.allCases {
            #expect(MonitoringColumns.perRow(layout: layout, sections: 1) == 1)
            #expect(MonitoringColumns.perRow(layout: layout, sections: 0) == 1)
        }
    }

    @Test("Auto: two sections side by side, three or more stacked")
    func autoLayout() {
        #expect(MonitoringColumns.perRow(layout: .auto, sections: 2) == 2)
        for count in 3...6 {
            #expect(MonitoringColumns.perRow(layout: .auto, sections: count) == 1)
        }
    }

    @Test("One column always stacks, two columns always pairs")
    func explicitLayouts() {
        for count in 2...6 {
            #expect(MonitoringColumns.perRow(layout: .oneColumn, sections: count) == 1)
            #expect(MonitoringColumns.perRow(layout: .twoColumns, sections: count) == 2)
        }
    }

    @Test("Two abreast needs two sections at their minimum width plus the gap")
    func twoAbreastThreshold() {
        let minimum = MonitoringColumns.twoAbreastMinimumWidth(spacing: 16)
        #expect(minimum == MonitoringColumns.minimumSideBySideWidth * 2 + 16)
        // The page's content at the 600 pt minimum window (minus the window
        // and page padding) is below it, so the sections stack there; at
        // 760 pt two sections fit.
        #expect(600 - 16 - 32 < minimum)
        #expect(760 - 16 - 32 >= minimum)
    }

    @Test("Rows keep the order, two per row or one")
    func rows() {
        let five: [HomeSection] = [.claude(.main), .claude(Self.work), .claude(Self.side), .claude(Self.old), .codex]
        #expect(MonitoringColumns.rows([], perRow: 2).isEmpty)
        #expect(MonitoringColumns.rows(five, perRow: 2).map(\.count) == [2, 2, 1])
        #expect(MonitoringColumns.rows(five, perRow: 2).last == [.codex])
        #expect(MonitoringColumns.rows(five, perRow: 1).map(\.count) == [1, 1, 1, 1, 1])
        #expect(MonitoringColumns.rows(five, perRow: 1).flatMap { $0 } == five)
        #expect(MonitoringColumns.rows([.claude(.main), .codex], perRow: 2) == [[.claude(.main), .codex]])
    }
}
