import Foundation

/// Lays out the dashboard's secondary metric tiles into rows that always fill
/// the full row width, so a variable number of visible tiles never leaves an
/// empty trailing cell (the old fixed 3-column `LazyVGrid` left a hole whenever
/// the tile count was not a multiple of 3 - e.g. when a satellite card is absent).
///
/// Up to `maxPerRow` tiles per row (3 by default), except that with 3 a count
/// of exactly 4 lays out as 2x2 to avoid a lone full-width tile on the second
/// row.
/// Three per row: 1->[1], 2->[2], 3->[3], 4->[2,2], 5->[3,2], 6->[3,3].
/// Two per row: 1->[1], 2->[2], 3->[2,1], 4->[2,2], 5->[2,2,1].
enum MetricsGridLayout {
    /// Most tiles a row ever holds: a single full-width column, when three
    /// fit without truncating.
    static let widestRow = 3

    /// Most tiles a row holds in a column that shares the page with another
    /// one. Three abreast in half a window is where the labels and the reset
    /// lines broke, so two columns side by side never go past two.
    static let sideBySideRow = 2

    static func rows<T>(_ items: [T], maxPerRow: Int = widestRow) -> [[T]] {
        guard !items.isEmpty else { return [] }
        let cap = Swift.max(1, maxPerRow)
        let perRow = (cap >= 3 && items.count == 4) ? 2 : cap
        return stride(from: 0, to: items.count, by: perRow).map {
            Array(items[$0 ..< Swift.min($0 + perRow, items.count)])
        }
    }

    /// The cap for a column: two when it sits next to another column, three
    /// when it has the page to itself (and even then only if three fit, which
    /// the view measures).
    static func maxPerRow(sideBySide: Bool) -> Int {
        sideBySide ? sideBySideRow : widestRow
    }
}
