import Foundation

enum WatcherDisplayMode: String, CaseIterable {
    case branchPriority
    case projectAndBranch

    var label: String {
        switch self {
        case .branchPriority: return String(localized: "settings.watchers.display.branchPriority")
        case .projectAndBranch: return String(localized: "settings.watchers.display.projectAndBranch")
        }
    }
}
