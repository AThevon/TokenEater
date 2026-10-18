import Testing
import Foundation

@Suite("PopoverSectionGrouping")
struct PopoverSectionGroupingTests {

    private static let work = AccountID(rawValue: "acct-work")
    private static let side = AccountID(rawValue: "acct-side")
    private static let running: Set<AccountID> = [.main, work, side]

    private func groups(
        _ elements: [PopoverElement],
        mode: ProviderMode = .all,
        focused: AccountID = .main,
        running: Set<AccountID> = running
    ) -> [PopoverSectionGrouping.Section] {
        PopoverSectionGrouping.groups(elements, mode: mode, focused: focused, running: running)
    }

    @Test("The seeded All layout splits into chrome, one section per account, then the footer")
    func seededLayout() {
        let composition = PopoverComposition.default
            .addingAccountSection(Self.work)
            .addingAccountSection(Self.side)
        let sections = groups(composition.visibleElements)
        #expect(sections.map(\.key) == [
            .neutral, .claude(.main), .claude(Self.work), .claude(Self.side), .neutral,
        ])
        #expect(sections.map(\.id) == [
            "neutral#0", "claude.main#0", "claude.acct-work#0", "claude.acct-side#0", "neutral#1",
        ])
        // Headers name the accounts and Codex, never the chrome.
        #expect(sections.map(\.key.hasHeader) == [false, true, true, true, false])
    }

    @Test("Each added account's section packs into exactly one row of two half cells")
    func accountSectionIsOneRow() {
        let composition = PopoverComposition.default
            .addingAccountSection(Self.work)
            .addingAccountSection(Self.side)
        for section in groups(composition.visibleElements) where section.key == .claude(Self.work) || section.key == .claude(Self.side) {
            let rows = PopoverRowPacker.pack(section.elements)
            #expect(rows.count == 1)
            #expect(rows.first?.map(\.effectiveWidth) == [.half, .half])
            #expect(rows.first?.map(\.kind) == [.session, .weekly])
        }
        // The main account keeps the layout it had: two gauges, two pace bars.
        let main = groups(composition.visibleElements).first { $0.key == .claude(.main) }
        #expect(main.map { PopoverRowPacker.pack($0.elements).count } == 3)
    }

    @Test("Codex is a section of its own and an account split around it is two sections")
    func codexSplitsARun() {
        let elements = [
            PopoverElement(kind: .session, style: .chip, width: .half),
            PopoverElement(kind: .codexSession, style: .chip, width: .half),
            PopoverElement(kind: .weekly, style: .chip, width: .half),
        ]
        let sections = groups(elements)
        #expect(sections.map(\.key) == [.claude(.main), .codex, .claude(.main)])
        #expect(sections.map(\.id) == ["claude.main#0", "codex#0", "claude.main#1"])
    }

    @Test("Claude mode resolves cells without an account to the focused one")
    func claudeModeUsesTheFocus() {
        let elements = [
            PopoverElement(kind: .session, style: .chip, width: .half),
            PopoverElement(kind: .weekly, style: .chip, width: .half, account: .main),
        ]
        let sections = groups(elements, mode: .claude, focused: Self.work)
        #expect(sections.map(\.key) == [.claude(Self.work), .claude(.main)])
    }

    @Test("A cell pinned to a paused or removed account is left out, and its neighbours merge")
    func pausedAccountIsDropped() {
        let elements = [
            PopoverElement(kind: .session, style: .chip, width: .half),
            PopoverElement(kind: .session, style: .chip, width: .half, account: Self.side),
            PopoverElement(kind: .weekly, style: .chip, width: .half),
        ]
        let sections = groups(elements, running: [.main, Self.work])
        #expect(sections.map(\.key) == [.claude(.main)])
        #expect(sections.first?.elements.count == 2)
    }

    @Test("Neutral elements never join an account's section")
    func neutralStaysApart() {
        let elements = [
            PopoverElement(kind: .session, style: .chip, width: .half, account: Self.work),
            PopoverElement(kind: .timestamp, style: .utilityRow, width: .full),
            PopoverElement(kind: .weekly, style: .chip, width: .half, account: Self.work),
        ]
        let sections = groups(elements)
        #expect(sections.map(\.key) == [.claude(Self.work), .neutral, .claude(Self.work)])
    }

    @Test("The section order sorts the account sections, the chrome stays in place")
    func sectionsFollowTheOrder() {
        let composition = PopoverComposition.default
            .addingAccountSection(Self.work)
            .addingAccountSection(Self.side)
        let order: [HomeSection] = [.claude(Self.side), .codex, .claude(.main), .claude(Self.work)]
        let sections = PopoverSectionGrouping.groups(
            composition.visibleElements, mode: .all, focused: .main, running: Self.running, order: order
        )
        #expect(sections.map(\.key) == [
            .neutral, .claude(Self.side), .claude(.main), .claude(Self.work), .neutral,
        ])
        // Ids stay those of the content, so a reorder animates rather than rebuilds.
        #expect(sections.map(\.id) == [
            "neutral#0", "claude.acct-side#0", "claude.main#0", "claude.acct-work#0", "neutral#1",
        ])
    }

    @Test("Codex follows the order too, around a neutral element in the middle")
    func codexFollowsTheOrder() {
        let elements = [
            PopoverElement(kind: .session, style: .chip, width: .half),
            PopoverElement(kind: .timestamp, style: .utilityRow, width: .full),
            PopoverElement(kind: .codexSession, style: .chip, width: .half),
            PopoverElement(kind: .session, style: .chip, width: .half, account: Self.work),
        ]
        let sections = PopoverSectionGrouping.groups(
            elements, mode: .all, focused: .main, running: Self.running,
            order: [.codex, .claude(Self.work), .claude(.main)]
        )
        #expect(sections.map(\.key) == [.codex, .neutral, .claude(Self.work), .claude(.main)])
        // No order: the composition's own.
        #expect(groups(elements).map(\.key) == [.claude(.main), .neutral, .codex, .claude(Self.work)])
    }
}
