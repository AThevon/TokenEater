import Foundation

enum PacingZone: String {
    case chill    // safely below the ideal pace
    case onTrack  // within ±margin of the ideal pace
    case warning  // running ahead by more than the margin but below the hot threshold
    case hot      // running ahead by more than 2x the margin
}

enum PacingBucket: String, CaseIterable {
    case fiveHour
    case sevenDay
    case sonnet

    var periodDuration: TimeInterval {
        switch self {
        case .fiveHour: return 5 * 3600
        case .sevenDay, .sonnet: return 7 * 24 * 3600
        }
    }

    var metricID: MetricID {
        switch self {
        case .fiveHour: return .fiveHour
        case .sevenDay: return .sevenDay
        case .sonnet: return .sonnet
        }
    }
}

struct PacingResult {
    let delta: Double
    let expectedUsage: Double
    let actualUsage: Double
    let zone: PacingZone
    let message: String
    let resetDate: Date?
}
