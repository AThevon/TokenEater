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
    /// Account-presence snapshot from the cached usage, so a stale pin for a
    /// metric no longer on the account doesn't produce a segment that renders
    /// nothing (same lesson as the popover migrator).
    struct AccountPresence {
        var hasDesign: Bool
        var hasFable: Bool
        var hasExtraCredits: Bool

        init(hasDesign: Bool = true, hasFable: Bool = true, hasExtraCredits: Bool = true) {
            self.hasDesign = hasDesign
            self.hasFable = hasFable
            self.hasExtraCredits = hasExtraCredits
        }

        init(cachedUsage: UsageResponse?) {
            guard let usage = cachedUsage else { self.init(); return }
            self.init(
                hasDesign: usage.sevenDayDesign != nil,
                hasFable: usage.sevenDayFable != nil,
                hasExtraCredits: usage.extraUsage?.isEnabled == true
            )
        }
    }

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
        pacingShape: PacingShape,
        presence: AccountPresence = AccountPresence()
    ) -> MenuBarComposition {
        let segments: [MenuBarSegment] = legacyOrder.compactMap { metric in
            guard pinnedMetrics.contains(metric) else { return nil }
            guard let kind = kind(for: metric) else { return nil }
            // Drop a pinned metric the account no longer has, so migration
            // never produces a permanently-empty segment.
            if kind.isPresenceGated && !isAvailable(kind, presence: presence) { return nil }

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
            if menuBarStyle == .badge { return .pill }
            let mode = (metric == .sessionPacing) ? sessionMode : weeklyMode
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

    private static func isAvailable(_ kind: MenuBarSegmentKind, presence: AccountPresence) -> Bool {
        switch kind {
        case .design: return presence.hasDesign
        case .fable: return presence.hasFable
        case .extraCredits: return presence.hasExtraCredits
        default: return true
        }
    }
}
