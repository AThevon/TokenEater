import Foundation

/// How wide the strip at the edge of the screen that captures mouse clicks
/// for the watchers overlay. A narrower zone leaves more of the screen
/// clickable through to underlying apps. Minimal is the click-through
/// best case: you have to hover the visible indicator strip itself, but
/// once the overlay has expanded it stays grabable over a larger zone so
/// the mouse doesn't have to stay pixel-pinned. See issue #134.
enum OverlayTriggerZone: String, CaseIterable, Identifiable {
    case minimal
    case narrow
    case medium
    case wide

    var id: String { rawValue }

    /// Width (points, before multiplying by `overlayScale`) of the zone that
    /// captures mouse clicks while the overlay is NOT already active.
    var enterWidth: CGFloat {
        switch self {
        case .minimal: return 18
        case .narrow: return 40
        case .medium: return 80
        case .wide: return 130
        }
    }

    /// Width (points) the overlay keeps grabbing clicks within once it has
    /// already been triggered - lets the cursor drift away from the strip
    /// without the overlay snapping shut mid-hover. Minimal gets the
    /// largest expansion since its entry zone is the tightest.
    var exitWidth: CGFloat {
        switch self {
        case .minimal: return 110
        case .narrow: return 100
        case .medium: return 120
        case .wide: return 150
        }
    }

    var localizedLabel: String {
        switch self {
        case .minimal: return String(localized: "settings.watchers.trigger.minimal")
        case .narrow: return String(localized: "settings.watchers.trigger.narrow")
        case .medium: return String(localized: "settings.watchers.trigger.medium")
        case .wide: return String(localized: "settings.watchers.trigger.wide")
        }
    }
}
