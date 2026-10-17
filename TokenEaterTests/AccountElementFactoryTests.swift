import Testing
import Foundation

@Suite("Adding an element or a segment for an account")
struct AccountElementFactoryTests {

    private static let work = AccountID(rawValue: "acct-work")

    @Test("An element added in an added account's group carries that account")
    func popoverElementCarriesAccount() {
        let element = PopoverElement.added(kind: .session, account: Self.work)
        #expect(element.account == Self.work)
        #expect(element.options.showReset)
        #expect(element.style == PopoverElementKind.session.allowedStyles.first)
        #expect(element.width == element.style.defaultWidth)
    }

    @Test("The main account, Codex and neutral kinds never carry an account")
    func popoverElementNeutral() {
        #expect(PopoverElement.added(kind: .session, account: .main).account == nil)
        #expect(PopoverElement.added(kind: .session, account: nil).account == nil)
        #expect(PopoverElement.added(kind: .codexSession, account: Self.work).account == nil)
        #expect(PopoverElement.added(kind: .timestamp, account: Self.work).account == nil)
        #expect(!PopoverElement.added(kind: .fable, account: nil).options.showReset)
    }

    @Test("A segment added in an added account's group carries that account")
    func menuBarSegmentCarriesAccount() {
        let segment = MenuBarSegment.added(kind: .weekly, account: Self.work)
        #expect(segment.account == Self.work)
        #expect(segment.style == MenuBarSegmentKind.weekly.allowedStyles.first)
        #expect(MenuBarSegment.added(kind: .weekly, account: .main).account == nil)
        #expect(MenuBarSegment.added(kind: .codexWeekly, account: Self.work).account == nil)
        #expect(MenuBarSegment.added(kind: .serviceStatus, account: Self.work).account == nil)
    }
}
