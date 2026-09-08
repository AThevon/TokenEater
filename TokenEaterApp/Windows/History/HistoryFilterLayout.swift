import SwiftUI

struct HistoryFilterLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(subviews, width: bounds.width)
        for (view, origin) in zip(subviews, layout.origins) {
            view.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                       proposal: ProposedViewSize(view.sizeThatFits(.unspecified)))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), origins)
    }
}
