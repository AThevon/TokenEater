import AppKit
import Foundation

/// Utilities for resolving user-picked hex strings to NSColors for the
/// menu bar. We store colours as hex strings in SettingsStore (a single
/// source of truth with the rest of the theming code). An empty string
/// means "use the system default" - rendered as the caller's fallback.
enum MenuBarTextColorResolver {
    /// Resolves `hex` to an NSColor, falling back to `defaultColor` when
    /// the hex is empty / malformed.
    static func resolve(hex: String, fallback defaultColor: NSColor) -> NSColor {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let color = NSColor.fromHex(trimmed) else {
            return defaultColor
        }
        return color
    }
}

extension NSColor {
    /// Parses "#RRGGBB" / "RRGGBB" / "#RGB" / "RGB" into an NSColor.
    /// Returns nil for anything that isn't exactly 3 or 6 hex digits.
    static func fromHex(_ hex: String) -> NSColor? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }

        switch cleaned.count {
        case 3:
            cleaned = cleaned.map { "\($0)\($0)" }.joined()
        case 6:
            break
        default:
            return nil
        }

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }

        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// Converts this color to a "#RRGGBB" string using sRGB components.
    func hexString() -> String {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
