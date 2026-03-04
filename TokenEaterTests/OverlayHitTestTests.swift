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

    // MARK: - Content offset (drag displacement)

    @Test("offset shifts bounds down — cursor at new position is near")
    func offsetShiftsDown() {
        // Sessions at 300–500, dragged down by 200 → effective 500–700
        #expect(OverlayHitTest.isCursorNearSessions(
            cursorY: 600, sessionsMinY: 500, sessionsMaxY: 700
        ))
    }

    @Test("offset shifts bounds down — cursor at old position is no longer near")
    func offsetOldPositionNotNear() {
        // Sessions were at 300–500, now at 500–700
        #expect(!OverlayHitTest.isCursorNearSessions(
            cursorY: 400, sessionsMinY: 500, sessionsMaxY: 700
        ))
    }

    @Test("offset shifts bounds up — cursor at new position is near")
    func offsetShiftsUp() {
        // Sessions at 300–500, dragged up by 200 → effective 100–300
        #expect(OverlayHitTest.isCursorNearSessions(
            cursorY: 200, sessionsMinY: 100, sessionsMaxY: 300
        ))
    }

    @Test("custom padding is respected")
    func customPadding() {
        // With padding=10, cursor at 289 (11px above 300) should NOT be near
        #expect(!OverlayHitTest.isCursorNearSessions(
            cursorY: 289, sessionsMinY: 300, sessionsMaxY: 500, padding: 10
        ))
        // But cursor at 291 (9px above 300) should be near
        #expect(OverlayHitTest.isCursorNearSessions(
            cursorY: 291, sessionsMinY: 300, sessionsMaxY: 500, padding: 10
        ))
    }
}
