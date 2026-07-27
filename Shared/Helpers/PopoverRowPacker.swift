import Foundation

/// Pure row-forming logic for the composable popover grid.
///
/// Rule (deliberately simple and predictable): consecutive elements of the
/// SAME width share a row, up to that width's capacity (1 full, 2 halves,
/// 3 thirds). A width change always breaks the row. Incomplete rows keep the
/// declared width of their elements and are centered by the renderer, so what
/// the user declares is what they see.
enum PopoverRowPacker {
    static func pack(_ elements: [PopoverElement]) -> [[PopoverElement]] {
        packIndices(elements.map(\.effectiveWidth)).map { row in row.map { elements[$0] } }
    }

    /// Index-based variant shared with `PopoverGridLayout`, which only knows
    /// its subviews' widths (via a LayoutValueKey), not the elements.
    static func packIndices(_ widths: [PopoverElementWidth]) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []

        for (index, width) in widths.enumerated() {
            if let first = current.first,
               widths[first] == width,
               current.count < width.rowCapacity {
                current.append(index)
            } else {
                if !current.isEmpty { rows.append(current) }
                current = [index]
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }
}
