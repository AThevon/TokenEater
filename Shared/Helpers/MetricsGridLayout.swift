import Foundation

/// Lays out the dashboard's secondary metric tiles into rows that always fill
/// the full row width, so a variable number of visible tiles never leaves an
/// empty trailing cell (the old fixed 3-column `LazyVGrid` left a hole whenever
/// the tile count was not a multiple of 3 - e.g. when the Design card is absent).
///
/// Up to 3 tiles per row, except a count of exactly 4 lays out as 2x2 to avoid a
/// lone full-width tile on the second row.
/// Shapes: 1->[1], 2->[2], 3->[3], 4->[2,2], 5->[3,2], 6->[3,3].
enum MetricsGridLayout {
    static func rows<T>(_ items: [T]) -> [[T]] {
        guard !items.isEmpty else { return [] }
        let perRow = items.count == 4 ? 2 : 3
        return stride(from: 0, to: items.count, by: perRow).map {
            Array(items[$0 ..< Swift.min($0 + perRow, items.count)])
        }
    }
}
