import Foundation

/// One-shot conversion of the legacy menu bar preferences (pre-5.10:
/// `pinnedMetrics` + the single global `menuBarStyle` + the scattered per-metric
/// display options) into an equivalent `MenuBarComposition`, so upgrading users
/// keep the exact menu bar they had.
///
/// Pure function: `SettingsStore` calls it once when the new `menuBarComposition`
/// blob is absent. The legacy keys stay in UserDefaults so a downgrade restores
/// the previous menu bar untouched.
enum MenuBarConfigMigrator {
    /// The fixed order the pre-5.10 renderer drew pinned metrics in. Preserving
    /// it means the migrated composition looks identical to what the user saw.
    private static let legacyOrder: [MetricID] = [
        .serviceStatus, .sessionReset, .fiveHour, .sessionPacing,
        .sevenDay, .weeklyPacing, .sonnet, .design, .fable, .extraCredits,
    ]

    static func migrate(
        pinnedMetrics: Set<MetricID>,
        menuBarStyle: MenuBarStyle,
        sessionPacingDisplayMode: PacingDisplayMode,
        weeklyPacingDisplayMode: PacingDisplayMode,
        resetDisplayFormat: ResetDisplayFormat,
        pacingShape: PacingShape
    ) -> MenuBarComposition {
        // Every pinned metric becomes a segment - including presence-gated ones
        // (Design / Fable / Extra Credits) that happen to be absent right now.
        // The renderer already gates presence at draw time (isSegmentAvailable),
        // exactly like the pre-5.10 menu bar which kept the pin and re-showed it
        // when the metric returned. Dropping it here instead would permanently
        // lose the pin the next time the pool re-enables (e.g. Extra Credits'
        // `isEnabled` is transient), which the old menu bar never did.
        let segments: [MenuBarSegment] = legacyOrder.compactMap { metric in
            guard pinnedMetrics.contains(metric) else { return nil }
            guard let kind = kind(for: metric) else { return nil }
            return MenuBarSegment(
                kind: kind,
                style: style(for: kind, metric: metric, menuBarStyle: menuBarStyle,
                             sessionMode: sessionPacingDisplayMode, weeklyMode: weeklyPacingDisplayMode),
                options: MenuBarSegmentOptions(pacingShape: pacingShape, resetFormat: resetDisplayFormat)
            )
        }
        return MenuBarComposition(segments: segments)
    }

    // MARK: - Mapping

    private static func kind(for metric: MetricID) -> MenuBarSegmentKind? {
        switch metric {
        case .fiveHour: return .session
        case .sevenDay: return .weekly
        case .sonnet: return .sonnet
        case .design: return .design
        case .fable: return .fable
        case .extraCredits: return .extraCredits
        case .sessionPacing: return .sessionPacing
        case .weeklyPacing: return .weeklyPacing
        case .sessionReset: return .sessionReset
        case .serviceStatus: return .serviceStatus
        }
    }

    private static func style(
        for kind: MenuBarSegmentKind,
        metric: MetricID,
        menuBarStyle: MenuBarStyle,
        sessionMode: PacingDisplayMode,
        weeklyMode: PacingDisplayMode
    ) -> MenuBarSegmentStyle {
        switch kind.family {
        case .usage:
            switch menuBarStyle {
            case .classic: return .labelValue
            case .mono: return .mono
            case .badge: return .pill
            }
        case .pacing:
            let mode = (metric == .sessionPacing) ? sessionMode : weeklyMode
            // Old badge pacing honored the display mode: dotDelta was a
            // glyph+delta pill, but dot / delta showed glyph-only / delta-only.
            // The single `.pill` pacing style is glyph+delta, so only dotDelta
            // maps to it faithfully; dot / delta keep their plain styles (losing
            // the capsule, but preserving the content the user chose).
            if menuBarStyle == .badge && mode == .dotDelta { return .pill }
            switch mode {
            case .dot: return .dot
            case .dotDelta: return .dotDelta
            case .delta: return .delta
            }
        case .status:
            if menuBarStyle == .badge { return .pill }
            return kind == .serviceStatus ? .glyph : .text
        }
    }

}
