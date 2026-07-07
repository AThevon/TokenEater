import Foundation

enum MetricID: String, CaseIterable {
    case fiveHour = "fiveHour"
    case sessionReset = "sessionReset"
    case sevenDay = "sevenDay"
    case sonnet = "sonnet"
    case design = "design"
    case fable = "fable"
    case extraCredits = "extraCredits"
    case sessionPacing = "sessionPacing"
    case weeklyPacing = "weeklyPacing"
    case serviceStatus = "serviceStatus"

    var label: String {
        switch self {
        case .fiveHour: return String(localized: "metric.session")
        case .sessionReset: return String(localized: "metric.sessionReset")
        case .sevenDay: return String(localized: "metric.weekly")
        case .sonnet: return String(localized: "metric.sonnet")
        case .design: return String(localized: "metric.design")
        case .fable: return String(localized: "metric.fable")
        case .extraCredits: return String(localized: "metric.extraCredits")
        case .sessionPacing: return String(localized: "pacing.session.label")
        case .weeklyPacing: return String(localized: "pacing.weekly.label")
        case .serviceStatus: return String(localized: "metric.serviceStatus")
        }
    }

    var shortLabel: String {
        switch self {
        case .fiveHour: return "5h"
        case .sessionReset: return ""
        case .sevenDay: return "7d"
        case .sonnet: return "S"
        case .design: return "D"
        case .fable: return "F"
        case .extraCredits: return "EC"
        case .sessionPacing: return "5hP"
        case .weeklyPacing: return "7dP"
        case .serviceStatus: return ""
        }
    }
}

enum PacingDisplayMode: String, CaseIterable {
    case dot
    case dotDelta
    case delta
}

enum AppErrorState: Equatable {
    case none
    case tokenUnavailable
    case rateLimited
    case networkError
}
