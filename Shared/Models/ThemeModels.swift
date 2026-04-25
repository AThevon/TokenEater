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

    /// Smart gauge color -> couples the threshold severity (utilization vs
    /// `warningPercent` / `criticalPercent`) with the pacing severity (delta
    /// vs ideal pace at this point in the cycle), and takes the worst of the
    /// two. A "reset imminent" override pulls everything back to green when
    /// less than ~10% of the window remains, on the basis that an imminent
    /// reset cancels any short-term escalation.
    ///
    /// Why not the old `risk = utilization × remainingFraction` formula:
    /// it triggered orange far too eagerly. At 33% util with 64% of the window
    /// remaining, risk = 21 -> already orange while the user is calmly on
    /// track. The user-visible signal felt out of step with the pacing pill.
    ///
    /// Returns:
    /// - red   if util >= 100 (limit hit, override)
    /// - green if reset imminent (< 10% of 5h windows, < 5% of weekly windows)
    /// - max(threshold severity, pacing severity) otherwise
    ///
    /// Where:
    /// - threshold severity = green/orange/red from `gaugeColor(for:thresholds:)`
    /// - pacing severity    = green (chill / onTrack), orange (warning), red (hot)
    ///   based on delta = utilization - elapsedFraction*100, vs `pacingMargin`
    func smartGaugeColor(
        utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds,
        pacingMargin: Double = 10,
        now: Date = Date()
    ) -> Color {
        switch smartLevel(
            utilization: utilization,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: thresholds,
            pacingMargin: pacingMargin,
            now: now
        ) {
        case .critical: return Color(hex: gaugeCritical)
        case .warning:  return Color(hex: gaugeWarning)
        case .normal:   return Color(hex: gaugeNormal)
        }
    }

    func smartGaugeNSColor(
        utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds,
        pacingMargin: Double = 10,
        now: Date = Date()
    ) -> NSColor {
        switch smartLevel(
            utilization: utilization,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: thresholds,
            pacingMargin: pacingMargin,
            now: now
        ) {
        case .critical: return NSColor(hex: gaugeCritical)
        case .warning:  return NSColor(hex: gaugeWarning)
        case .normal:   return NSColor(hex: gaugeNormal)
        }
    }

    func smartGaugeGradient(
        utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds,
        pacingMargin: Double = 10,
        now: Date = Date(),
        startPoint: UnitPoint = .topLeading,
        endPoint: UnitPoint = .bottomTrailing
    ) -> LinearGradient {
        let base = smartGaugeColor(
            utilization: utilization,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: thresholds,
            pacingMargin: pacingMargin,
            now: now
        )
        return LinearGradient(colors: [base, base.lighter()], startPoint: startPoint, endPoint: endPoint)
    }

    /// Severity buckets the smart system collapses into. Internal type used
    /// to share logic between the SwiftUI Color, AppKit NSColor, and the
    /// notification level computations.
    enum SmartLevel {
        case normal, warning, critical

        var rank: Int {
            switch self {
            case .normal:   return 0
            case .warning:  return 1
            case .critical: return 2
            }
        }

        static func max(_ a: SmartLevel, _ b: SmartLevel) -> SmartLevel {
            a.rank >= b.rank ? a : b
        }
    }

    /// Single source of truth for the smart-color decision tree.
    /// Returns the severity that the gauge / notification should surface,
    /// based on the worst of (threshold severity, pacing severity) with a
    /// "reset imminent" green override.
    func smartLevel(
        utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds,
        pacingMargin: Double = 10,
        now: Date = Date()
    ) -> SmartLevel {
        // Hard limit hit.
        if utilization >= 100 { return .critical }

        // No date / no window -> degrade to threshold-only logic.
        guard let resetDate, windowDuration > 0 else {
            return thresholdLevel(utilization: utilization, thresholds: thresholds)
        }

        let remaining = max(resetDate.timeIntervalSince(now), 0)
        let remainingFraction = max(0, min(1, remaining / windowDuration))

        // Reset imminent override : a 5h window with < 30 min left, or a 7d
        // window with < ~8h left, is so close to wiping the slate that we
        // ignore everything except the hard 100% override above. 5h windows
        // are short enough that a 10% margin is generous; 7d windows benefit
        // from a tighter 5% margin because the projection is more reliable.
        let imminentThreshold: Double = windowDuration <= 6 * 3600 ? 0.10 : 0.05
        if remainingFraction < imminentThreshold { return .normal }

        // Threshold severity (how much have you actually consumed).
        let absolute = thresholdLevel(utilization: utilization, thresholds: thresholds)

        // Pacing severity (how does the current rate compare to ideal).
        let elapsedFraction = 1.0 - remainingFraction
        let expectedUsage = elapsedFraction * 100
        let delta = utilization - expectedUsage
        let pacing: SmartLevel
        if delta > pacingMargin * 2 {
            pacing = .critical
        } else if delta > pacingMargin {
            pacing = .warning
        } else {
            pacing = .normal
        }

        return SmartLevel.max(absolute, pacing)
    }

    /// Pure threshold mapping, kept private to mirror `gaugeColor(for:thresholds:)`.
    private func thresholdLevel(utilization: Double, thresholds: UsageThresholds) -> SmartLevel {
        if utilization >= Double(thresholds.criticalPercent) { return .critical }
        if utilization >= Double(thresholds.warningPercent)  { return .warning }
        return .normal
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
