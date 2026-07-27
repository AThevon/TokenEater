import Foundation

/// One-shot v1 -> v2 migration of the popover composition: the fixed header
/// chrome (plan badge + refresh button) becomes two regular composable
/// elements at the top of the element list, and the legacy visibility
/// toggles turn into the elements' hidden flags.
///
/// v2 compositions pass through untouched, so a user who later deletes the
/// chrome elements never sees them come back. Pure function, no I/O; called
/// from `SettingsStore.init` on whatever composition the decode / legacy
/// migration produced.
enum PopoverChromeMigrator {
    static func migrate(_ composition: PopoverComposition) -> PopoverComposition {
        guard composition.version < PopoverComposition.currentVersion else {
            return composition
        }

        var result = composition
        result.version = PopoverComposition.currentVersion

        // Badge on the left, refresh on the right -> one half+half row that
        // mirrors the old fixed header. Safety guard on `contains` so a
        // hand-edited v1 blob that somehow already carries a chrome element
        // never gets a duplicate.
        var chrome: [PopoverElement] = []
        if !composition.elements.contains(where: { $0.kind == .planBadge }) {
            chrome.append(PopoverElement(
                kind: .planBadge,
                style: .badge,
                width: .half,
                isHidden: !composition.showPlanBadge
            ))
        }
        if !composition.elements.contains(where: { $0.kind == .refreshButton }) {
            chrome.append(PopoverElement(
                kind: .refreshButton,
                style: .actionButton,
                width: .half,
                isHidden: !composition.showRefreshButton
            ))
        }
        result.elements.insert(contentsOf: chrome, at: 0)
        return result
    }
}
