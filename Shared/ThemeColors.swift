import SwiftUI

// MARK: - Theme Colors

struct ThemeColors: Codable, Equatable {
    var gaugeNormal: String
    var gaugeWarning: String
    var gaugeCritical: String
    var pacingChill: String
    var pacingOnTrack: String
    var pacingHot: String
    var widgetBackground: String
    var widgetText: String

    // MARK: Presets

    static let `default` = ThemeColors(
        gaugeNormal: "#22C55E",
        gaugeWarning: "#F97316",
        gaugeCritical: "#EF4444",
        pacingChill: "#32D74B",
        pacingOnTrack: "#0A84FF",
        pacingHot: "#FF453A",
        widgetBackground: "#000000",
        widgetText: "#FFFFFF"
    )

    static let monochrome = ThemeColors(
        gaugeNormal: "#8E8E93",
        gaugeWarning: "#C7C7CC",
        gaugeCritical: "#FFFFFF",
        pacingChill: "#8E8E93",
        pacingOnTrack: "#AEAEB2",
        pacingHot: "#FFFFFF",
        widgetBackground: "#000000",
        widgetText: "#FFFFFF"
    )

    static let neon = ThemeColors(
        gaugeNormal: "#00FF87",
        gaugeWarning: "#FFD000",
        gaugeCritical: "#FF006E",
        pacingChill: "#00FF87",
        pacingOnTrack: "#00D4FF",
        pacingHot: "#FF006E",
        widgetBackground: "#0A0A0A",
        widgetText: "#FFFFFF"
    )

    static let pastel = ThemeColors(
        gaugeNormal: "#86EFAC",
        gaugeWarning: "#FDE68A",
        gaugeCritical: "#FCA5A5",
        pacingChill: "#86EFAC",
        pacingOnTrack: "#93C5FD",
        pacingHot: "#FCA5A5",
        widgetBackground: "#1A1A2E",
        widgetText: "#E2E8F0"
    )

    static let allPresets: [(key: String, label: String, colors: ThemeColors)] = [
        ("default", String(localized: "theme.default"), .default),
        ("monochrome", String(localized: "theme.monochrome"), .monochrome),
        ("neon", String(localized: "theme.neon"), .neon),
        ("pastel", String(localized: "theme.pastel"), .pastel),
    ]

    static func preset(for key: String) -> ThemeColors? {
        allPresets.first { $0.key == key }?.colors
    }

    // MARK: Color Helpers

    func gaugeColor(for pct: Double, thresholds: UsageThresholds) -> Color {
        if pct >= Double(thresholds.criticalPercent) { return Color(hex: gaugeCritical) }
        if pct >= Double(thresholds.warningPercent) { return Color(hex: gaugeWarning) }
        return Color(hex: gaugeNormal)
    }

    func gaugeGradient(for pct: Double, thresholds: UsageThresholds, startPoint: UnitPoint = .topLeading, endPoint: UnitPoint = .bottomTrailing) -> LinearGradient {
        let base = gaugeColor(for: pct, thresholds: thresholds)
        return LinearGradient(colors: [base, base.lighter()], startPoint: startPoint, endPoint: endPoint)
    }

    func pacingColor(for zone: PacingZone) -> Color {
        switch zone {
        case .chill: return Color(hex: pacingChill)
        case .onTrack: return Color(hex: pacingOnTrack)
        case .hot: return Color(hex: pacingHot)
        }
    }

    func pacingGradient(for zone: PacingZone, startPoint: UnitPoint = .topLeading, endPoint: UnitPoint = .bottomTrailing) -> LinearGradient {
        let base = pacingColor(for: zone)
        return LinearGradient(colors: [base, base.lighter()], startPoint: startPoint, endPoint: endPoint)
    }

    func gaugeNSColor(for pct: Double, thresholds: UsageThresholds) -> NSColor {
        if pct >= Double(thresholds.criticalPercent) { return NSColor(hex: gaugeCritical) }
        if pct >= Double(thresholds.warningPercent) { return NSColor(hex: gaugeWarning) }
        return NSColor(hex: gaugeNormal)
    }

    func pacingNSColor(for zone: PacingZone) -> NSColor {
        switch zone {
        case .chill: return NSColor(hex: pacingChill)
        case .onTrack: return NSColor(hex: pacingOnTrack)
        case .hot: return NSColor(hex: pacingHot)
        }
    }
}

// MARK: - Usage Thresholds

struct UsageThresholds: Codable, Equatable {
    var warningPercent: Int
    var criticalPercent: Int

    static let `default` = UsageThresholds(warningPercent: 60, criticalPercent: 85)
}
