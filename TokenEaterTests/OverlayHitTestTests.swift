import Testing

@Suite("OverlayWindowController hit-test")
struct OverlayHitTestTests {

    // Sessions rendered between Y 300–500

    @Test("cursor inside sessions bounds is near")
    func cursorInsideBounds() {
        #expect(OverlayHitTest.isCursorNearSessions(
            cursorY: 400, sessionsMinY: 300, sessionsMaxY: 500
        ))
    }

    @Test("cursor within padding above sessions is near")
    func cursorAboveWithinPadding() {
        #expect(OverlayHitTest.isCursorNearSessions(
            cursorY: 270, sessionsMinY: 300, sessionsMaxY: 500
        ))
    }

    @Test("cursor within padding below sessions is near")
    func cursorBelowWithinPadding() {
        #expect(OverlayHitTest.isCursorNearSessions(
            cursorY: 530, sessionsMinY: 300, sessionsMaxY: 500
        ))
    }

    @Test("cursor far above sessions is not near")
    func cursorFarAbove() {
        #expect(!OverlayHitTest.isCursorNearSessions(
            cursorY: 100, sessionsMinY: 300, sessionsMaxY: 500
        ))
    }

    @Test("cursor far below sessions is not near")
    func cursorFarBelow() {
        #expect(!OverlayHitTest.isCursorNearSessions(
            cursorY: 700, sessionsMinY: 300, sessionsMaxY: 500
        ))
    }

    @Test("no sessions (zero bounds) is never near")
    func noSessions() {
        #expect(!OverlayHitTest.isCursorNearSessions(
            cursorY: 400, sessionsMinY: 0, sessionsMaxY: 0
        ))
    }
}
