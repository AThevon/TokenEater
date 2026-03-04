import Foundation

enum OverlayHitTest {
    static let padding: CGFloat = 40

    /// Returns true if the cursor Y position is within the sessions' vertical bounds (plus padding).
    static func isCursorNearSessions(
        cursorY: CGFloat,
        sessionsMinY: CGFloat,
        sessionsMaxY: CGFloat,
        padding: CGFloat = Self.padding
    ) -> Bool {
        sessionsMaxY > sessionsMinY
            && cursorY >= sessionsMinY - padding
            && cursorY <= sessionsMaxY + padding
    }
}
