import Foundation

/// Where the watchers dock takes the mouse. Mirrors the layout OverlayView and
/// SessionTraitView render, so the capture area follows what is on screen: the
/// colored indicators while the dock is closed, the cards it opens into once
/// it is open (#271).
enum OverlayHitTest {
    /// Slack around the indicators and cards, so the cursor doesn't have to land
    /// on the exact pixel.
    static let tolerance: CGFloat = 6

    /// OverlayView's `VStack` spacing between watchers.
    static let stackSpacing: CGFloat = 4

    /// A closed indicator's height (SessionTraitView at proximity 0).
    static func indicatorHeight(scale: CGFloat) -> CGFloat { 22 * scale }

    /// An open card's height (SessionTraitView at the 0.75 hover proximity).
    static func cardHeight(scale: CGFloat) -> CGFloat { 40 * scale }

    /// Vertical span of the watcher stack: centered in the panel and moved by
    /// the drag offset. Nil when there are no sessions to show.
    static func stackSpan(
        sessionCount: Int,
        itemHeight: CGFloat,
        windowHeight: CGFloat,
        contentOffset: CGFloat
    ) -> ClosedRange<CGFloat>? {
        guard sessionCount > 0 else { return nil }
        let height = CGFloat(sessionCount) * itemHeight + CGFloat(sessionCount - 1) * stackSpacing
        let minY = (windowHeight - height) / 2 + contentOffset
        return minY...(minY + height)
    }

    /// Whether the dock should take the mouse.
    ///
    /// Closed, only over the indicators: within `enterWidth` of the screen edge
    /// and the closed stack's height. Open, over the cards: within `exitWidth`
    /// and the open stack's height, so the cursor can move across the cards
    /// without the dock snapping shut. Both allow `tolerance` above and below.
    static func shouldCapture(
        distanceFromEdge: CGFloat,
        cursorY: CGFloat,
        isOpen: Bool,
        sessionCount: Int,
        scale: CGFloat,
        windowHeight: CGFloat,
        contentOffset: CGFloat,
        enterWidth: CGFloat,
        exitWidth: CGFloat
    ) -> Bool {
        guard distanceFromEdge <= (isOpen ? exitWidth : enterWidth) else { return false }

        let itemHeight = isOpen ? cardHeight(scale: scale) : indicatorHeight(scale: scale)
        guard let span = stackSpan(
            sessionCount: sessionCount,
            itemHeight: itemHeight,
            windowHeight: windowHeight,
            contentOffset: contentOffset
        ) else { return false }

        return cursorY >= span.lowerBound - tolerance && cursorY <= span.upperBound + tolerance
    }
}
