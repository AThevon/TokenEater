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
        var rows: [[PopoverElement]] = []
        var current: [PopoverElement] = []

        for element in elements {
            let width = element.effectiveWidth
            if let first = current.first,
               first.effectiveWidth == width,
               current.count < width.rowCapacity {
                current.append(element)
            } else {
                if !current.isEmpty { rows.append(current) }
                current = [element]
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }
}
