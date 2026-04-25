import SwiftUI

// MARK: - Theme Colors

struct ThemeColors: Codable, Equatable {
    var gaugeNormal: String
    var gaugeWarning: String
    var gaugeCritical: String
    var pacingChill: String
    var pacingOnTrack: String
    var pacingWarning: String
    var pacingHot: String
    var widgetBackground: String
    var widgetText: String

    init(
        gaugeNormal: String,
        gaugeWarning: String,
        gaugeCritical: String,
        pacingChill: String,
        pacingOnTrack: String,
        pacingWarning: String,
        pacingHot: String,
        widgetBackground: String,
        widgetText: String
    ) {
        self.gaugeNormal = gaugeNormal
        self.gaugeWarning = gaugeWarning
        self.gaugeCritical = gaugeCritical
        self.pacingChill = pacingChill
        self.pacingOnTrack = pacingOnTrack
        self.pacingWarning = pacingWarning
        self.pacingHot = pacingHot
        self.widgetBackground = widgetBackground
        self.widgetText = widgetText
    }

    /// Custom decoder so older saved themes (pre-`pacingWarning` migration)
    /// degrade gracefully to the default warning color instead of failing the
    /// whole decode and dropping the user's custom theme.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.gaugeNormal     = try c.decode(String.self, forKey: .gaugeNormal)
        self.gaugeWarning    = try c.decode(String.self, forKey: .gaugeWarning)
        self.gaugeCritical   = try c.decode(String.self, forKey: .gaugeCritical)
        self.pacingChill     = try c.decode(String.self, forKey: .pacingChill)
        self.pacingOnTrack   = try c.decode(String.self, forKey: .pacingOnTrack)
        self.pacingWarning   = try c.decodeIfPresent(String.self, forKey: .pacingWarning) ?? "#FF9500"
        self.pacingHot       = try c.decode(String.self, forKey: .pacingHot)
        self.widgetBackground = try c.decode(String.self, forKey: .widgetBackground)
        self.widgetText      = try c.decode(String.self, forKey: .widgetText)
    }

    private enum CodingKeys: String, CodingKey {
        case gaugeNormal, gaugeWarning, gaugeCritical
        case pacingChill, pacingOnTrack, pacingWarning, pacingHot
        case widgetBackground, widgetText
    }

    // MARK: Presets

    static let `default` = ThemeColors(
        gaugeNormal: "#22C55E",
        gaugeWarning: "#F97316",
        gaugeCritical: "#EF4444",
        pacingChill: "#32D74B",
        pacingOnTrack: "#0A84FF",
        pacingWarning: "#FF9500",
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
        pacingWarning: "#D6D6D6",
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
        pacingWarning: "#FFD000",
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
        pacingWarning: "#FDE68A",
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
        case .chill:   return Color(hex: pacingChill)
        case .onTrack: return Color(hex: pacingOnTrack)
        case .warning: return Color(hex: pacingWarning)
        case .hot:     return Color(hex: pacingHot)
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

    // MARK: - Smart (risk-aware) gauge

    /// Smart gauge color -> integrates time-to-reset, normalised by the total
    /// window length, so the same formula behaves consistently on a 5h session
    /// or a 7-day window.
    ///
    /// Formula : `risk = utilization × (remaining / windowDuration)`. Values:
    ///   - risk > 30 -> critical
    ///   - risk > 20 -> warning
    ///   - else       -> normal
    ///
    /// The previous version multiplied by `remainingMinutes` in absolute, which
    /// blew up on long windows (13% utilisation × 9600 minutes / 100 = 1248 ->
    /// always critical, regardless of how reasonable the usage actually was).
    /// Normalising by `windowDuration` makes "almost full window remaining"
    /// behave the same on 5h and on 7d.
    ///
    /// Edge cases :
    ///   - `utilization >= 100` always surfaces critical (genuinely capped).
    ///   - `resetDate == nil` falls back to threshold-based coloring.
    func smartGaugeColor(
        utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds,
        now: Date = Date()
    ) -> Color {
        if utilization >= 100 { return Color(hex: gaugeCritical) }
        guard let resetDate, windowDuration > 0 else {
            return gaugeColor(for: utilization, thresholds: thresholds)
        }
        let remaining = max(resetDate.timeIntervalSince(now), 0)
        let remainingFraction = max(0, min(1, remaining / windowDuration))
        let risk = utilization * remainingFraction
        if risk > 30 { return Color(hex: gaugeCritical) }
        if risk > 20 { return Color(hex: gaugeWarning) }
        return Color(hex: gaugeNormal)
    }

    func smartGaugeNSColor(
        utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds,
        now: Date = Date()
    ) -> NSColor {
        if utilization >= 100 { return NSColor(hex: gaugeCritical) }
        guard let resetDate, windowDuration > 0 else {
            return gaugeNSColor(for: utilization, thresholds: thresholds)
        }
        let remaining = max(resetDate.timeIntervalSince(now), 0)
        let remainingFraction = max(0, min(1, remaining / windowDuration))
        let risk = utilization * remainingFraction
        if risk > 30 { return NSColor(hex: gaugeCritical) }
        if risk > 20 { return NSColor(hex: gaugeWarning) }
        return NSColor(hex: gaugeNormal)
    }

    func smartGaugeGradient(
        utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds,
        now: Date = Date(),
        startPoint: UnitPoint = .topLeading,
        endPoint: UnitPoint = .bottomTrailing
    ) -> LinearGradient {
        let base = smartGaugeColor(
            utilization: utilization,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: thresholds,
            now: now
        )
        return LinearGradient(colors: [base, base.lighter()], startPoint: startPoint, endPoint: endPoint)
    }

    func pacingNSColor(for zone: PacingZone) -> NSColor {
        switch zone {
        case .chill:   return NSColor(hex: pacingChill)
        case .onTrack: return NSColor(hex: pacingOnTrack)
        case .warning: return NSColor(hex: pacingWarning)
        case .hot:     return NSColor(hex: pacingHot)
        }
    }
}

// MARK: - Usage Thresholds

struct UsageThresholds: Codable, Equatable {
    var warningPercent: Int
    var criticalPercent: Int

    static let `default` = UsageThresholds(warningPercent: 60, criticalPercent: 85)
}
