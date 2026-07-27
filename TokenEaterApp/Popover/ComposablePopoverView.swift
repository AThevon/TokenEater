import SwiftUI

// MARK: - Preview interaction environment
//
// The settings editor renders the same view with these values set so tapping
// a cell in the live preview selects it in the element list. The real popover
// never sets them, so the tap layer costs nothing there.

private struct PopoverElementTapKey: EnvironmentKey {
    static let defaultValue: ((UUID) -> Void)? = nil
}

private struct PopoverSelectedElementKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var popoverElementTap: ((UUID) -> Void)? {
        get { self[PopoverElementTapKey.self] }
        set { self[PopoverElementTapKey.self] = newValue }
    }

    var popoverSelectedElement: UUID? {
        get { self[PopoverSelectedElementKey.self] }
        set { self[PopoverSelectedElementKey.self] = newValue }
    }
}

// MARK: - Renderer

/// The composable popover renderer: fixed chrome (status + error banners),
/// then the element grid. Replaces the three variant layouts. The old fixed
/// header (plan badge + refresh button) is composition v2 elements now; only
/// its top breathing room remains as chrome.
struct ComposablePopoverView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore

    static let popoverWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 12)

            VendorStatusBanner()

            if usageStore.hasError {
                PopoverErrorBanner()
            }

            PopoverGrid()
        }
        .frame(width: Self.popoverWidth)
        .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)))
    }
}

/// The element grid. Rows come from `PopoverRowPacker` (pure, unit-tested),
/// applied by a custom `Layout` over ONE flat ForEach keyed by element id.
/// Flat identity is load-bearing: a reorder is a genuine SwiftUI "move", so
/// cells glide to their new frame under the container animation, with no
/// duplicated identities during transitions (the nested-ForEach +
/// matchedGeometryEffect approach mounted the same id twice mid-reorder,
/// which SwiftUI documents as undefined geometry).
private struct PopoverGrid: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.popoverElementTap) private var tapHandler
    @Environment(\.popoverSelectedElement) private var selectedID

    @State private var appeared = false

    private static let horizontalPadding: CGFloat = 16
    private static let cellSpacing: CGFloat = 8
    private static let rowSpacing: CGFloat = 10

    var body: some View {
        let visible = visibleElements
        Group {
            if visible.isEmpty {
                emptyState
            } else {
                grid(visible)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private func grid(_ visible: [PopoverElement]) -> some View {
        let rowIndexByID = rowIndexMap(visible)
        return PopoverGridLayout(cellSpacing: Self.cellSpacing, rowSpacing: Self.rowSpacing) {
            ForEach(visible) { element in
                cell(element, rowIndex: rowIndexByID[element.id] ?? 0)
                    .layoutValue(key: PopoverGridWidthKey.self, value: element.effectiveWidth)
            }
        }
        // Edit-time reflow: flat stable ids make position changes animate as
        // moves, cells glide to their new row instead of jump-cutting.
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: settingsStore.popoverComposition.elements)
        .onAppear { appeared = true }
    }

    private var visibleElements: [PopoverElement] {
        settingsStore.popoverComposition.visibleElements.filter {
            PopoverMetricResolver.isAvailable($0.kind, usage: usageStore)
        }
    }

    private func rowIndexMap(_ visible: [PopoverElement]) -> [UUID: Int] {
        var map: [UUID: Int] = [:]
        for (rowIndex, row) in PopoverRowPacker.pack(visible).enumerated() {
            for element in row { map[element.id] = rowIndex }
        }
        return map
    }

    @ViewBuilder
    private func cell(_ element: PopoverElement, rowIndex: Int) -> some View {
        let selected = selectedID == element.id
        PopoverElementCellView(element: element)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.7), lineWidth: 1.5)
                        .dsGlow(.blue, radius: 6, opacity: 0.5)
                        .padding(-3)
                }
            }
            .contentShape(Rectangle())
            .modifier(PreviewTapModifier(id: element.id, handler: tapHandler))
            // Entrance cascade: 25ms per row, fade + 6px rise. Subtle enough
            // for a surface opened dozens of times a day; skipped under
            // Reduce Motion.
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 6)
            .animation(
                reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85).delay(min(Double(rowIndex) * 0.025, 0.25)),
                value: appeared
            )
    }

    /// Shown when every element is hidden or unavailable right now (e.g. a
    /// pacing-only composition before the first refresh, or a metric the
    /// account no longer has). Static validation can't catch these, they
    /// depend on live data.
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.dashed")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))
            Text(String(localized: "popover.empty"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text(String(localized: "popover.empty.hint"))
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// MARK: - Grid layout

private struct PopoverGridWidthKey: LayoutValueKey {
    static let defaultValue: PopoverElementWidth = .full
}

/// Places one flat run of cells into centered rows. Row formation delegates
/// to `PopoverRowPacker.packIndices` so the renderer, the editor schematics,
/// and the tests all share the same rule.
private struct PopoverGridLayout: Layout {
    let cellSpacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? ComposablePopoverView.popoverWidth
        let rows = rowGroups(subviews)
        var height: CGFloat = 0
        for row in rows {
            height += rowHeight(row, subviews: subviews, totalWidth: width)
        }
        if rows.count > 1 {
            height += rowSpacing * CGFloat(rows.count - 1)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rowGroups(subviews) {
            let cellW = cellWidth(for: rowWidth(row, subviews: subviews), totalWidth: bounds.width)
            let heights = row.map {
                subviews[$0].sizeThatFits(ProposedViewSize(width: cellW, height: nil)).height
            }
            let rowH = heights.max() ?? 0
            let contentW = CGFloat(row.count) * cellW + CGFloat(row.count - 1) * cellSpacing
            var x = bounds.minX + (bounds.width - contentW) / 2
            for (i, index) in row.enumerated() {
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (rowH - heights[i]) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: cellW, height: heights[i])
                )
                x += cellW + cellSpacing
            }
            y += rowH + rowSpacing
        }
    }

    private func rowGroups(_ subviews: Subviews) -> [[Int]] {
        PopoverRowPacker.packIndices(subviews.map { $0[PopoverGridWidthKey.self] })
    }

    private func rowWidth(_ row: [Int], subviews: Subviews) -> PopoverElementWidth {
        row.first.map { subviews[$0][PopoverGridWidthKey.self] } ?? .full
    }

    private func rowHeight(_ row: [Int], subviews: Subviews, totalWidth: CGFloat) -> CGFloat {
        let cellW = cellWidth(for: rowWidth(row, subviews: subviews), totalWidth: totalWidth)
        return row.map {
            subviews[$0].sizeThatFits(ProposedViewSize(width: cellW, height: nil)).height
        }.max() ?? 0
    }

    /// Fractions resolve against the proposed width (300 - 2x16 = 268):
    /// full 268, half 130, third 84.
    private func cellWidth(for width: PopoverElementWidth, totalWidth: CGFloat) -> CGFloat {
        let spacing = cellSpacing * CGFloat(width.rowCapacity - 1)
        return ((totalWidth - spacing) / CGFloat(width.rowCapacity)).rounded(.down)
    }
}

/// Adds the tap layer only when the editor preview installed a handler, so
/// the real popover keeps its buttons and toggles fully interactive.
private struct PreviewTapModifier: ViewModifier {
    let id: UUID
    let handler: ((UUID) -> Void)?

    func body(content: Content) -> some View {
        if let handler {
            // Transparent layer above the cell so its own buttons / toggles
            // never swallow the selection tap in the editor preview.
            content.overlay(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { handler(id) }
            )
        } else {
            content
        }
    }
}
