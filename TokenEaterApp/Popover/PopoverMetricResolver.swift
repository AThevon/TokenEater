import Foundation

/// Single source of truth mapping an element kind to its live values.
///
/// Before the composable popover, every layout call site hardcoded its own
/// `(pct, resetDate, windowDuration)` tuple; centralising the mapping
/// guarantees every cell feeds `GaugeColorResolver` the same inputs, so Smart
/// Color / threshold coloring can never silently diverge between styles.
@MainActor
enum PopoverMetricResolver {
    struct UsageSnapshot {
        let label: String
        let pct: Int
        let resetDate: Date?
        /// Formatted countdown ("2h 15m"). Empty when the metric has no
        /// reset window (Extra Credits) or no data yet.
        let resetText: String
        /// 0 = no rolling window -> threshold coloring (Extra Credits).
        let windowDuration: TimeInterval
        /// Whose number this is. The cell draws the provider's mark in front
        /// of the label instead of spelling the name into it, so a Codex cell
        /// reads "❀ 5h" next to Claude's "✳ 5h" rather than "Codex weekly"
        /// next to "Weekly". Nil for anything that belongs to no provider.
        var provider: MetricProvider? = nil
    }

    /// Codex windows arrive as a list rather than named buckets, so a kind
    /// resolves by looking one up instead of reading a fixed property. A plan
    /// without that window simply has no entry, which is what `isAvailable`
    /// reads to recompact the row.
    private static func codexWindow(_ wanted: CodexWindowKind, _ codex: CodexUsageStore) -> CodexWindowSnapshot? {
        codex.isEnabled ? codex.windows.first { $0.kind == wanted } : nil
    }

    static func usageSnapshot(for kind: PopoverElementKind, usage: UsageStore, codex: CodexUsageStore) -> UsageSnapshot? {
        switch kind {
        case .codexSession, .codexWeekly:
            guard let window = codexWindow(kind == .codexSession ? .session : .weekly, codex) else { return nil }
            return UsageSnapshot(
                // The window's own short name ("5h", "Weekly"), not "Codex
                // weekly": the mark in front of it says which provider.
                label: window.label,
                pct: window.pct,
                resetDate: window.resetDate,
                resetText: window.relativeReset,
                windowDuration: window.windowDuration,
                provider: .codex
            )
        case .session:
            return UsageSnapshot(
                label: String(localized: "metric.session"),
                pct: usage.fiveHourPct,
                resetDate: usage.lastUsage?.fiveHour?.resetsAtDate,
                resetText: usage.fiveHourReset,
                windowDuration: 5 * 3600,
                provider: .claude
            )
        case .weekly:
            return UsageSnapshot(
                label: String(localized: "metric.weekly"),
                pct: usage.sevenDayPct,
                resetDate: usage.lastUsage?.sevenDay?.resetsAtDate,
                resetText: usage.sevenDayReset,
                windowDuration: 7 * 86_400,
                provider: .claude
            )
        case .sonnet:
            return weeklySnapshot(
                label: String(localized: "metric.sonnet"),
                pct: usage.sonnetPct,
                resetDate: usage.lastUsage?.sevenDaySonnet?.resetsAtDate
            )
        case .fable:
            return weeklySnapshot(
                label: String(localized: "metric.fable"),
                pct: usage.fablePct,
                resetDate: usage.lastUsage?.sevenDayFable?.resetsAtDate
            )
        case .extraCredits:
            // No reset window -> GaugeColorResolver falls back to threshold
            // coloring (windowDuration == 0), same contract as before.
            return UsageSnapshot(
                label: String(localized: "metric.extraCredits"),
                pct: usage.extraCreditsPct,
                resetDate: nil,
                resetText: "",
                windowDuration: 0,
                provider: .claude
            )
        default:
            return nil
        }
    }

    static func pacing(for kind: PopoverElementKind, usage: UsageStore, codex: CodexUsageStore) -> PacingResult? {
        switch kind {
        case .codexSessionPacing: return codexWindow(.session, codex)?.pacing
        case .codexWeeklyPacing: return codexWindow(.weekly, codex)?.pacing
        case .sessionPacing: return usage.fiveHourPacing
        case .weeklyPacing: return usage.pacingResult
        case .fablePacing: return usage.fablePacing
        default: return nil
        }
    }

    /// Presence gating: elements whose data doesn't exist on this account (or
    /// right now) render nothing and their row recompacts, matching the old
    /// satellite behavior.
    /// Whether a cell has any business rendering: its provider must be on and
    /// the current mode must show it. Chrome carries no provider and passes
    /// both tests, so a mode is never an empty shell.
    static func isVisible(
        _ kind: PopoverElementKind,
        usage: UsageStore,
        codex: CodexUsageStore,
        settings: SettingsStore
    ) -> Bool {
        if let provider = kind.provider {
            guard settings.activeProviders.contains(provider) else { return false }
            guard settings.activeProviderMode.shows(provider) else { return false }
        }
        // Never as an element any more: the switcher is pinned chrome above
        // the composition. Any instance left in a layout saved by an older
        // build gates out here rather than rendering a second one.
        if kind == .providerSwitch { return false }
        // The badge draws one capsule per provider the mode shows, so it is
        // present when any of them knows its plan.
        if kind == .planBadge {
            return settings.activeProviders
                .filter { settings.activeProviderMode.shows($0) }
                .contains { $0 == .claude ? usage.planType != .unknown : codex.planType != .unknown }
        }
        return isAvailable(kind, usage: usage, codex: codex)
    }

    static func isAvailable(_ kind: PopoverElementKind, usage: UsageStore, codex: CodexUsageStore) -> Bool {
        switch kind {
        // Same three-state model as the Claude pacing cells: a window that
        // exists but is idle keeps its placeholder, a window this plan does
        // not have disappears and the row recompacts.
        case .codexSession, .codexSessionPacing: return codexWindow(.session, codex) != nil
        case .codexWeekly, .codexWeeklyPacing: return codexWindow(.weekly, codex) != nil
        case .fable: return usage.hasFable
        case .extraCredits: return usage.hasExtraCredits
        // Pacing follows the 3-state model (absent / idle / active): available
        // when the underlying bucket is PRESENT, so an idle bucket (present but
        // no active window yet) still renders its "-" placeholder cell instead
        // of vanishing. `pacing(for:)` returns nil for idle -> the cell draws
        // the placeholder; a truly absent bucket returns false here and the row
        // recompacts.
        case .sessionPacing: return usage.lastUsage?.fiveHour != nil
        case .weeklyPacing: return usage.lastUsage?.sevenDay != nil
        case .fablePacing: return usage.hasFable
        // `planBadge` is gated in `isVisible`, where the mode is known: the
        // badge follows the mode now, so "Claude has a plan" is the wrong
        // question to ask of it.
        default: return true
        }
    }

    private static func weeklySnapshot(label: String, pct: Int, resetDate: Date?) -> UsageSnapshot {
        UsageSnapshot(
            label: label,
            pct: pct,
            resetDate: resetDate,
            resetText: resetDate != nil ? ResetCountdownFormatter.weekly(from: resetDate).relative : "",
            windowDuration: 7 * 86_400,
            provider: .claude
        )
    }
}
