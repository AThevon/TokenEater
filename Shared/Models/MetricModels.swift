import Foundation

enum MetricID: String, CaseIterable {
    case fiveHour = "fiveHour"
    case sevenDay = "sevenDay"
    case sonnet = "sonnet"
    case sessionPacing = "sessionPacing"
    case weeklyPacing = "weeklyPacing"
    case sonnetPacing = "sonnetPacing"

    var label: String {
        switch self {
        case .fiveHour: return String(localized: "metric.session")
        case .sevenDay: return String(localized: "metric.weekly")
        case .sonnet: return String(localized: "metric.sonnet")
        case .sessionPacing: return String(localized: "pacing.session.label")
        case .weeklyPacing: return String(localized: "pacing.weekly.label")
        case .sonnetPacing: return String(localized: "pacing.sonnet.label")
        }
    }

    var shortLabel: String {
        switch self {
        case .fiveHour: return "5h"
        case .sevenDay: return "7d"
        case .sonnet: return "S"
        case .sessionPacing: return "5hP"
        case .weeklyPacing: return "7dP"
        case .sonnetPacing: return "SP"
        }
    }
}

enum PacingDisplayMode: String, CaseIterable {
    case dot
    case dotDelta
    case delta
}

enum GaugeColorMode: String, CaseIterable {
    case `static`
    case smart
}

enum AppErrorState: Equatable {
    case none
    case tokenUnavailable
    case rateLimited
    case networkError
}
