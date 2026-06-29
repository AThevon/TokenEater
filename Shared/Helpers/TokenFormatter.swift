import Foundation

/// Compact SI-prefixed token counts for dense UI (tiles, history rows,
/// widget back numbers). One canonical rule shared by the app and the
/// widget so a 12M total never reads as "12.0M" in one place and "12M"
/// in another.
///
/// Rule: a single decimal below 10 of each unit, none at/above 10.
///   96 -> "96", 1_200 -> "1.2k", 10_000 -> "10k",
///   540_000 -> "540k", 1_200_000 -> "1.2M", 12_000_000 -> "12M".
enum TokenFormatter {
    static func compact(_ value: Int) -> String {
        if value >= 1_000_000 {
            let m = Double(value) / 1_000_000
            return String(format: m >= 10 ? "%.0fM" : "%.1fM", m)
        }
        if value >= 1_000 {
            let k = Double(value) / 1_000
            return String(format: k >= 10 ? "%.0fk" : "%.1fk", k)
        }
        return "\(value)"
    }
}
