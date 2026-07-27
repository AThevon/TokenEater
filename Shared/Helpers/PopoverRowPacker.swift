import Foundation

/// Pure row-forming logic for the composable popover grid.
///
/// Rule (deliberately simple and predictable): consecutive elements of the
/// SAME width AND the same group share a row, up to that width's capacity
/// (1 full, 2 halves, 3 thirds). A width change or a group change always
/// breaks the row. The group boundary keeps the header chrome (plan badge +
/// refresh) from merging into the metric grid. Incomplete rows keep the
/// declared width of their elements and are centered by the renderer, so what
/// the user declares is what they see.
enum PopoverRowPacker {
    static func pack(_ elements: [PopoverElement]) -> [[PopoverElement]] {
        packIndices(
            elements.map(\.effectiveWidth),
            groups: elements.map { $0.kind.isChrome ? 1 : 0 }
        ).map { row in row.map { elements[$0] } }
    }

    /// Index-based variant shared with `PopoverGridLayout`, which only knows
    /// its subviews' widths (via a LayoutValueKey), not the elements. All in
    /// one group -> width-only packing (used by the packer unit tests).
    static func packIndices(_ widths: [PopoverElementWidth]) -> [[Int]] {
        packIndices(widths, groups: Array(repeating: 0, count: widths.count))
    }

    /// Group-aware variant: a row also breaks when the group token changes.
    static func packIndices(_ widths: [PopoverElementWidth], groups: [Int]) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []

        for (index, width) in widths.enumerated() {
            if let first = current.first,
               widths[first] == width,
               groups[first] == groups[index],
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
