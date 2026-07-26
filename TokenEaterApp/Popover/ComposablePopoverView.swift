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

/// The composable popover renderer: fixed chrome (header, status + error
/// banners), then the element grid. Replaces the three variant layouts.
struct ComposablePopoverView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader()

            VendorStatusBanner()

            if usageStore.hasError {
                PopoverErrorBanner()
            }

            PopoverGrid()
        }
        .frame(width: PopoverGrid.popoverWidth)
        .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)))
    }
}

/// The element grid. Rows come from `PopoverRowPacker` (pure, unit-tested);
/// cell widths are fixed fractions of the content width so what the user
/// declares in the editor is exactly what renders.
private struct PopoverGrid: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.popoverElementTap) private var tapHandler
    @Environment(\.popoverSelectedElement) private var selectedID

    @Namespace private var gridNamespace
    @State private var appeared = false

    static let popoverWidth: CGFloat = 300
    private static let horizontalPadding: CGFloat = 16
    private static let cellSpacing: CGFloat = 8
    private static let rowSpacing: CGFloat = 10

    private struct GridRow: Identifiable {
        let id: UUID
        let index: Int
        let elements: [PopoverElement]
    }

    var body: some View {
        let rows = PopoverRowPacker.pack(visibleElements).enumerated().map { index, elements in
            GridRow(id: elements[0].id, index: index, elements: elements)
        }
        VStack(spacing: Self.rowSpacing) {
            ForEach(rows) { row in
                rowView(row.elements, rowIndex: row.index)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.top, 4)
        .padding(.bottom, 10)
        // Edit-time reflow: stable element ids + matchedGeometryEffect make
        // cells glide to their new row instead of jump-cutting.
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: settingsStore.popoverComposition.elements)
        .onAppear { appeared = true }
    }

    private var visibleElements: [PopoverElement] {
        settingsStore.popoverComposition.visibleElements.filter {
            PopoverMetricResolver.isAvailable($0.kind, usage: usageStore)
        }
    }

    @ViewBuilder
    private func rowView(_ row: [PopoverElement], rowIndex: Int) -> some View {
        HStack(spacing: Self.cellSpacing) {
            ForEach(row) { element in
                cell(element)
                    .frame(width: cellWidth(for: element.effectiveWidth))
            }
        }
        .frame(maxWidth: .infinity)
        // Entrance cascade: 25ms per row, fade + 6px rise. Subtle enough for
        // a surface opened dozens of times a day; skipped under Reduce Motion.
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 6)
        .animation(
            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85).delay(min(Double(rowIndex) * 0.025, 0.25)),
            value: appeared
        )
    }

    @ViewBuilder
    private func cell(_ element: PopoverElement) -> some View {
        let selected = selectedID == element.id
        PopoverElementCellView(element: element)
            .matchedGeometryEffect(id: element.id, in: gridNamespace)
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
    }

    /// Content width is fixed (300 - 2x16 = 268), so fractions resolve to
    /// exact pixel widths: full 268, half 130, third 84.
    private func cellWidth(for width: PopoverElementWidth) -> CGFloat {
        let content = Self.popoverWidth - Self.horizontalPadding * 2
        let spacing = Self.cellSpacing * CGFloat(width.rowCapacity - 1)
        return ((content - spacing) / CGFloat(width.rowCapacity)).rounded(.down)
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
