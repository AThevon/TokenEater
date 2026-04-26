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

    // MARK: - Smart (risk-aware) gauge — v2

    /// Continuous risk score [0, 1] surfaced for any UI / logic that
    /// wants the live signal. Combines three components via `max`:
    ///   - absolute (how close to the threshold ladder)
    ///   - projection (will current rate exceed the limit before reset)
    ///   - pacing (gap between actual and linear-pace consumption)
    /// All three are smoothstep-based so the score is C1 continuous; the
    /// time-driven components (projection, pacing) are weighted by a
    /// confidence factor that grows from 0 at e=0 to ~1 at e=1, so the
    /// early-window noise doesn't trigger false alarms.
    /// See `SmartColor` for the math + `SmartColorTests` for the
    /// validation matrix.
    func smartRisk(
        utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds,
        pacingMargin: Double = 10,
        now: Date = Date(),
        profile: SmartColorProfile = .default
    ) -> Double {
        if utilization >= 100 { return 1.0 }
        let u = max(0, utilization) / 100
        let θw = Double(thresholds.warningPercent) / 100
        let θc = Double(thresholds.criticalPercent) / 100
        let params = profile.parameters

        guard let resetDate, windowDuration > 0 else {
            return SmartColor.absoluteRisk(u: u, θw: θw, θc: θc)
        }

        let remaining = max(0, resetDate.timeIntervalSince(now))
        let t = min(1.0, remaining / windowDuration)
        let e = max(0.0, 1.0 - t)
        let m = pacingMargin / 100

        return SmartColor.combinedRisk(u: u, e: e, θw: θw, θc: θc, m: m, params: params)
    }

    /// Smart gauge color -> continuous interpolation across 4 stops
    /// (chill -> warning -> critical) based on the live risk score.
    /// Uses the theme's gauge palette so the color identity stays
    /// consistent with the rest of the app.
    func smartGaugeColor(
        utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds,
        pacingMargin: Double = 10,
        now: Date = Date(),
        profile: SmartColorProfile = .default
    ) -> Color {
        let r = smartRisk(
            utilization: utilization,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: thresholds,
            pacingMargin: pacingMargin,
            now: now,
            profile: profile
        )
        return SmartColor.colorForRisk(r, theme: self)
    }

    func smartGaugeNSColor(
        utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds,
        pacingMargin: Double = 10,
        now: Date = Date(),
        profile: SmartColorProfile = .default
    ) -> NSColor {
        let r = smartRisk(
            utilization: utilization,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: thresholds,
            pacingMargin: pacingMargin,
            now: now,
            profile: profile
        )
        return SmartColor.nsColorForRisk(r, theme: self)
    }

    func smartGaugeGradient(
        utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds,
        pacingMargin: Double = 10,
        now: Date = Date(),
        startPoint: UnitPoint = .topLeading,
        endPoint: UnitPoint = .bottomTrailing,
        profile: SmartColorProfile = .default
    ) -> LinearGradient {
        let base = smartGaugeColor(
            utilization: utilization,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: thresholds,
            pacingMargin: pacingMargin,
            now: now,
            profile: profile
        )
        return LinearGradient(colors: [base, base.lighter()], startPoint: startPoint, endPoint: endPoint)
    }

    /// Legacy 3-level enum kept for back-compat with `NotificationService`
    /// and any caller still on the discrete API. Derived from `smartRisk`
    /// via `SmartColor.legacyLevel(forRisk:)`.
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

    func smartLevel(
        utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds,
        pacingMargin: Double = 10,
        now: Date = Date(),
        profile: SmartColorProfile = .default
    ) -> SmartLevel {
        let r = smartRisk(
            utilization: utilization,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: thresholds,
            pacingMargin: pacingMargin,
            now: now,
            profile: profile
        )
        return SmartColor.legacyLevel(forRisk: r)
    }

    /// 4-zone discretisation (chill / onTrack / warning / hot) used by
    /// the pacing pill + notifications when they need a finer grain
    /// than `SmartLevel`. Pass `previous` to enable hysteresis.
    func smartZone(
        utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds,
        pacingMargin: Double = 10,
        now: Date = Date(),
        previous: PacingZone? = nil,
        profile: SmartColorProfile = .default
    ) -> PacingZone {
        let r = smartRisk(
            utilization: utilization,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: thresholds,
            pacingMargin: pacingMargin,
            now: now,
            profile: profile
        )
        return SmartColor.zoneForRisk(r, previous: previous, params: profile.parameters)
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
