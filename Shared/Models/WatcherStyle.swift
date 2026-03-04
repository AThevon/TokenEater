import Foundation

enum WatcherStyle: String, CaseIterable {
    case frost
    case neon

    var label: String {
        switch self {
        case .frost: return String(localized: "settings.watchers.style.frost")
        case .neon: return String(localized: "settings.watchers.style.neon")
        }
    }
}
