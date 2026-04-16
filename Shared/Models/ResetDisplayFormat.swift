import Foundation

enum ResetDisplayFormat: String, CaseIterable, Identifiable {
    case relative   // "1h 39min"
    case absolute   // "20:30" today, "Fri 08:00" other days
    case both       // "1h 39min - 20:30"

    var id: String { rawValue }

    var localizedLabel: String {
        switch self {
        case .relative: return String(localized: "settings.reset.format.relative")
        case .absolute: return String(localized: "settings.reset.format.absolute")
        case .both: return String(localized: "settings.reset.format.both")
        }
    }
}
