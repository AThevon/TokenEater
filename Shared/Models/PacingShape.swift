import Foundation

/// Glyph used as the pacing indicator in both the menu bar and the popover.
/// Unicode block element so it renders consistently in every font without
/// requiring an SF Symbols fallback in the menu bar's NSAttributedString path.
enum PacingShape: String, Codable, CaseIterable, Identifiable {
    case circle, diamond, square, triangle, star

    var id: String { rawValue }

    var glyph: String {
        switch self {
        case .circle:   return "\u{25CF}"  // ●
        case .diamond:  return "\u{25C6}"  // ◆
        case .square:   return "\u{25A0}"  // ■
        case .triangle: return "\u{25B2}"  // ▲
        case .star:     return "\u{2605}"  // ★
        }
    }

    var localizedLabel: String {
        NSLocalizedString("pacingShape.\(rawValue)", comment: "")
    }
}
