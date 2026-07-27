import SwiftUI
import UniformTypeIdentifiers

/// Drag-to-reorder drop delegate for an `Identifiable` list, driving a live
/// swap on every drag tick (no "release to commit" surprise). Generic so the
/// composable popover and the composable menu bar editors share one
/// implementation.
///
/// `draggingID` is the id set in the row's `.onDrag`; a nil value means the
/// active drag wasn't started by our list (e.g. an external text drag), which
/// both delegates decline instead of swallowing.
struct ReorderDropDelegate<Item: Identifiable>: DropDelegate where Item.ID: Equatable {
    let item: Item.ID
    @Binding var items: [Item]
    @Binding var draggingID: Item.ID?

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingID, dragging != item else { return }
        guard let from = items.firstIndex(where: { $0.id == dragging }),
              let to = items.firstIndex(where: { $0.id == item })
        else { return }
        if from != to {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let wasDragging = draggingID != nil
        draggingID = nil
        return wasDragging
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: draggingID != nil ? .move : .cancel)
    }
}

/// Container-level catch-all: ends the drag session when the drop lands in the
/// spacing gaps between rows (outside any row's drop target), clearing the
/// lifted styling instead of leaving a row stuck mid-drag.
struct ReorderGapDropDelegate<ID: Equatable>: DropDelegate {
    @Binding var draggingID: ID?

    func performDrop(info: DropInfo) -> Bool {
        let wasDragging = draggingID != nil
        draggingID = nil
        return wasDragging
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: draggingID != nil ? .move : .cancel)
    }
}
