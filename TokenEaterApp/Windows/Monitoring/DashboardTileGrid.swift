import SwiftUI

// MARK: - Column context

private struct DashboardTilesPerRowKey: EnvironmentKey {
    static let defaultValue = MetricsGridLayout.widestRow
}

private struct DashboardColumnHeadedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct DashboardTileStyleKey: EnvironmentKey {
    static let defaultValue: DashboardTileStyle? = nil
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

    /// How much every card of a grid says, decided once for the whole grid.
    /// Nil lets each card shed what it must on its own, which is the last
    /// resort when no shared style fits.
    var dashboardTileStyle: DashboardTileStyle? {
        get { self[DashboardTileStyleKey.self] }
        set { self[DashboardTileStyleKey.self] = newValue }
    }
}

/// What a small card's label and reset line carry. A grid picks one for all
/// its cards, so two cards side by side never word the same thing two ways.
struct DashboardTileStyle: Equatable {
    /// The column's name in front of the label, when the card has one.
    var prefix: Bool
    /// "Resets in" before the countdown.
    var resetWords: Bool
    /// The clock time after the countdown.
    var clock: Bool

    static let full = DashboardTileStyle(prefix: true, resetWords: true, clock: true)
    /// The name stays, the words go: next to another provider's column with
    /// no header, whose card this is matters more than "resets in".
    static let named = DashboardTileStyle(prefix: true, resetWords: false, clock: true)
    /// Nothing is cut: the countdown and the clock time stay, only the words
    /// and the name go.
    static let compact = DashboardTileStyle(prefix: false, resetWords: false, clock: true)
    /// The countdown alone. Two narrow cards still say the same thing.
    static let minimal = DashboardTileStyle(prefix: false, resetWords: false, clock: false)
}

// MARK: - Grid

/// The rows of small metric cards of one column.
///
/// The cap comes from the column (`dashboardTilesPerRow`). Under a cap of
/// three, three abreast is kept as long as the three fit at an equal width
/// in their compact style (no truncation, the countdown and clock time
/// whole); otherwise the cards go two per row. Within a row shape the grid
/// tries the fullest style first, and the style it settles on applies to
/// every card, so the cards of one grid always read alike. Only when not
/// even the countdown alone fits does each card shed on its own.
///
/// In a column that shares its row with another one, every row of cards is
/// judged as if it were full, a lone card included: the grid next door
/// usually has two cards abreast at the same column width, and judging the
/// lone card on its own would word it differently ("Resets in" on one side,
/// not on the other).
struct DashboardTileGrid<Tile: View>: View {
    let tiles: [TileDescriptor]
    @ViewBuilder let tile: (TileDescriptor) -> Tile

    @Environment(\.dashboardTilesPerRow) private var cap

    var body: some View {
        let wide = MetricsGridLayout.rows(tiles, maxPerRow: cap)
        let narrow = MetricsGridLayout.rows(tiles, maxPerRow: MetricsGridLayout.sideBySideRow)
        let threeAbreast = wide.map(\.count) != narrow.map(\.count)
        let prefixed = tiles.contains { $0.prefix != nil }
        let judgedAs = cap == MetricsGridLayout.sideBySideRow ? cap : 0
        ViewThatFits(in: .horizontal) {
            if threeAbreast {
                rows(wide, style: .full)
                if prefixed { rows(wide, style: .named) }
                rows(wide, style: .compact)
            }
            rows(narrow, style: .full, judgedAs: judgedAs)
            if prefixed { rows(narrow, style: .named, judgedAs: judgedAs) }
            rows(narrow, style: .compact, judgedAs: judgedAs)
            rows(narrow, style: .minimal, judgedAs: judgedAs)
            rows(narrow, style: nil, judgedAs: judgedAs)
        }
    }

    private func rows(_ rows: [[TileDescriptor]], style: DashboardTileStyle?, judgedAs: Int = 0) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                EqualWidthRow(spacing: DS.Spacing.sm, judgedAs: judgedAs) {
                    ForEach(row, id: \.id) { descriptor in
                        tile(descriptor)
                    }
                }
            }
        }
        .environment(\.dashboardTileStyle, style)
    }
}

// MARK: - Equal-width row

/// Lays its subviews out side by side at one shared width.
///
/// An `HStack` of flexible cards splits the width evenly too, but asked for
/// its ideal width it answers the sum of the cards' ideal widths, so a wide
/// card next to two short ones "fits" and then gets a third of the row and
/// truncates. This answers the widest card's ideal width times the count,
/// which is what an even split actually needs, and that is what lets
/// `ViewThatFits` decide honestly.
struct EqualWidthRow: Layout {
    var spacing: CGFloat
    /// Asked for its ideal width, the row answers as if it held at least
    /// this many subviews. It still lays out the ones it has.
    var judgedAs: Int = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let count = CGFloat(subviews.count)
        let gaps = spacing * (count - 1)
        if let width = proposal.width, width.isFinite {
            let each = max(0, (width - gaps) / count)
            let height = subviews
                .map { $0.sizeThatFits(ProposedViewSize(width: each, height: nil)).height }
                .max() ?? 0
            return CGSize(width: width, height: height)
        }
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let widest = ideals.map(\.width).max() ?? 0
        let judged = CGFloat(max(subviews.count, judgedAs))
        return CGSize(width: widest * judged + spacing * (judged - 1), height: ideals.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let count = CGFloat(subviews.count)
        let each = max(0, (bounds.width - spacing * (count - 1)) / count)
        var x = bounds.minX
        for subview in subviews {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: each, height: nil)
            )
            x += each + spacing
        }
    }
}
