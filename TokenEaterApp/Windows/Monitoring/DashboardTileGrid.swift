import SwiftUI

// MARK: - Column context

private struct DashboardTilesPerRowKey: EnvironmentKey {
    static let defaultValue = MetricsGridLayout.widestRow
}

private struct DashboardColumnHeadedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Most small cards a row of the column holds: two when the column sits
    /// next to another one, three when it has the page to itself.
    var dashboardTilesPerRow: Int {
        get { self[DashboardTilesPerRowKey.self] }
        set { self[DashboardTilesPerRowKey.self] = newValue }
    }

    /// True when a header above the column already names it (an account, or
    /// Codex), so the cards inside do not repeat the name.
    var dashboardColumnHeaded: Bool {
        get { self[DashboardColumnHeadedKey.self] }
        set { self[DashboardColumnHeadedKey.self] = newValue }
    }
}

// MARK: - Grid

/// The rows of small metric cards of one column.
///
/// The cap comes from the column (`dashboardTilesPerRow`). Under a cap of
/// three, three abreast is only kept when the three fit at their full width,
/// labels and reset lines included: `ViewThatFits` measures them and falls
/// back to two per row otherwise, so a narrow single column never truncates
/// its cards either.
struct DashboardTileGrid<Tile: View>: View {
    let tiles: [TileDescriptor]
    @ViewBuilder let tile: (TileDescriptor) -> Tile

    @Environment(\.dashboardTilesPerRow) private var cap

    var body: some View {
        let wide = MetricsGridLayout.rows(tiles, maxPerRow: cap)
        let narrow = MetricsGridLayout.rows(tiles, maxPerRow: MetricsGridLayout.sideBySideRow)
        if wide.map(\.count) == narrow.map(\.count) {
            rows(wide)
        } else {
            ViewThatFits(in: .horizontal) {
                rows(wide)
                rows(narrow)
            }
        }
    }

    private func rows(_ rows: [[TileDescriptor]]) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(row, id: \.id) { descriptor in
                        tile(descriptor)
                    }
                }
            }
        }
    }
}
