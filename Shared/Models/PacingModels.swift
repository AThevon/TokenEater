import Foundation

enum PacingZone: String {
    case chill
    case onTrack
    case hot
}

struct PacingResult {
    let delta: Double
    let expectedUsage: Double
    let actualUsage: Double
    let zone: PacingZone
    let message: String
    let resetDate: Date?
}
