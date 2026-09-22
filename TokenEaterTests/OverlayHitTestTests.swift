import Testing
import Foundation

/// The watchers dock should only take the mouse over what it actually shows
/// (#271): the colored indicators while it's closed, the cards once it has
/// opened. It used to size both from the hovered card height, plus 40pt above
/// and below, so a closed dock captured many times the area of its indicators.
@Suite("OverlayWindowController hit-test")
struct OverlayHitTestTests {

    // Three watchers at the default 1.1 scale in a 900pt tall panel.
    // Closed, the indicators are 22 x 1.1 = 24.2pt tall with 4pt gaps: an
    // 80.6pt stack centered at 450, spanning 409.7...490.3.
    // Open, the cards are 40 x 1.1 = 44pt tall: a 140pt stack, 380...520.
    private let scale: CGFloat = 1.1
    private let windowHeight: CGFloat = 900
    private let minimalEnter: CGFloat = 18 * 1.1
    private let minimalExit: CGFloat = 110 * 1.1

    private func captures(
        distanceFromEdge: CGFloat,
        cursorY: CGFloat,
        isOpen: Bool = false,
        count: Int = 3,
        contentOffset: CGFloat = 0,
        enterWidth: CGFloat? = nil,
        exitWidth: CGFloat? = nil
    ) -> Bool {
        OverlayHitTest.shouldCapture(
            distanceFromEdge: distanceFromEdge,
            cursorY: cursorY,
            isOpen: isOpen,
            sessionCount: count,
            scale: scale,
            windowHeight: windowHeight,
            contentOffset: contentOffset,
            enterWidth: enterWidth ?? minimalEnter,
            exitWidth: exitWidth ?? minimalExit
        )
    }

    // MARK: - Stack geometry

    @Test("the stack is centered in the panel and moves with the drag offset")
    func stackSpan() throws {
        let span = try #require(OverlayHitTest.stackSpan(
            sessionCount: 3, itemHeight: 24.2, windowHeight: 900, contentOffset: 0
        ))
        #expect(abs(span.lowerBound - 409.7) < 0.001)
        #expect(abs(span.upperBound - 490.3) < 0.001)

        let dragged = try #require(OverlayHitTest.stackSpan(
            sessionCount: 3, itemHeight: 24.2, windowHeight: 900, contentOffset: 200
        ))
        #expect(abs(dragged.lowerBound - 609.7) < 0.001)
    }

    @Test("no sessions means no stack")
    func noStack() {
        #expect(OverlayHitTest.stackSpan(
            sessionCount: 0, itemHeight: 24.2, windowHeight: 900, contentOffset: 0
        ) == nil)
    }

    // MARK: - Closed: only over the indicators

    @Test("closed: the cursor on an indicator captures")
    func closedOnIndicator() {
        #expect(captures(distanceFromEdge: 10, cursorY: 450))
    }

    @Test("closed: a few points past the top indicator still captures")
    func closedWithinTolerance() {
        #expect(captures(distanceFromEdge: 10, cursorY: 409.7 - 5))
    }

    @Test("closed: 30pt above the top indicator does not capture")
    func closedAboveIndicators() {
        #expect(!captures(distanceFromEdge: 10, cursorY: 409.7 - 30))
    }

    @Test("closed: 30pt below the bottom indicator does not capture")
    func closedBelowIndicators() {
        #expect(!captures(distanceFromEdge: 10, cursorY: 490.3 + 30))
    }

    @Test("closed: level with the indicators but past the hover zone does not capture")
    func closedPastHoverZone() {
        #expect(!captures(distanceFromEdge: 60, cursorY: 450))
    }

    @Test("closed: a wider hover zone reaches further out, not further up")
    func closedWiderZone() {
        let medium: CGFloat = 80 * 1.1
        #expect(captures(distanceFromEdge: 60, cursorY: 450, enterWidth: medium))
        #expect(!captures(distanceFromEdge: 60, cursorY: 409.7 - 30, enterWidth: medium))
    }

    // MARK: - Open: over the cards it opened into

    @Test("open: the cursor over the opened cards keeps capturing")
    func openOverCards() {
        // 385 is inside the 140pt card stack, above where the indicators were.
        #expect(captures(distanceFromEdge: 100, cursorY: 385, isOpen: true))
    }

    @Test("open: moving well above the cards releases")
    func openAboveCards() {
        #expect(!captures(distanceFromEdge: 100, cursorY: 380 - 30, isOpen: true))
    }

    @Test("open: moving past the exit width releases")
    func openPastExitWidth() {
        #expect(!captures(distanceFromEdge: minimalExit + 5, cursorY: 450, isOpen: true))
    }

    // MARK: - Edge cases

    @Test("no sessions never captures")
    func noSessions() {
        #expect(!captures(distanceFromEdge: 5, cursorY: 450, count: 0))
    }

    @Test("a dragged stack captures where it is now, not where it was")
    func draggedStack() {
        #expect(!captures(distanceFromEdge: 10, cursorY: 450, contentOffset: 200))
        #expect(captures(distanceFromEdge: 10, cursorY: 650, contentOffset: 200))
    }
}
