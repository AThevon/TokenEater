import SwiftUI

/// Why a metric sitting in a layout would draw nothing right now.
///
/// Both editors used to answer that with a single line, "not active on this
/// account", whatever the reason was. That sentence is right for exactly one
/// case and actively misleading for the most common one: a ChatGPT plan with
/// no 5h window (Pro Lite returns a weekly primary window and a null
/// secondary) is a connected, working account, and reading "not active on
/// this account" next to its Session segment says the opposite. Reported on
/// #267 by the contributor testing the live OpenAI path.
///
/// The cases are ordered from the most actionable to the least: a switch the
/// user can flip, then a scope they chose, then a fact about their plan, then
/// simply not having fetched anything yet.
@MainActor
enum EditorUnavailability {
    /// The provider's tracking switch is off in Settings.
    case providerOff(MetricProvider)
    /// The layout being edited belongs to a mode that does not show this
    /// provider, so the metric is dropped whatever the account holds.
    case outOfScope(mode: String)
    /// Fetched and connected, and the plan simply has no such window or pool.
    case notOnPlan(MetricProvider)
    /// Nothing fetched yet, so nothing can be said about the plan.
    case noDataYet

    var label: String {
        switch self {
        case .providerOff(let provider):
            return String(format: String(localized: "editor.unavailable.providerOff"), provider.displayName)
        case .outOfScope(let mode):
            return String(format: String(localized: "editor.unavailable.scope"), mode)
        case .notOnPlan(let provider):
            return String(format: String(localized: "editor.unavailable.plan"), provider.displayName)
        case .noDataYet:
            return String(localized: "editor.unavailable.noData")
        }
    }
}

// MARK: - Resolution

extension EditorUnavailability {
    /// nil when the segment draws. Availability itself is still asked of
    /// `MenuBarSegmentAvailability`, which mirrors the renderer: this type
    /// only explains a "no" that has already been decided elsewhere.
    static func reason(
        for kind: MenuBarSegmentKind,
        settings: SettingsStore,
        usage: UsageStore,
        codex: CodexUsageStore
    ) -> EditorUnavailability? {
        guard !MenuBarSegmentAvailability.isAvailable(
            kind, settings: settings, usage: usage, codex: codex
        ) else { return nil }
        return reason(
            provider: kind.provider,
            isPlanFact: isPlanFact(kind),
            settings: settings, usage: usage, codex: codex
        )
    }

    /// Same contract for the popover, asking `PopoverMetricResolver`.
    static func reason(
        for kind: PopoverElementKind,
        settings: SettingsStore,
        usage: UsageStore,
        codex: CodexUsageStore
    ) -> EditorUnavailability? {
        guard !PopoverMetricResolver.isVisible(
            kind, usage: usage, codex: codex, settings: settings
        ) else { return nil }
        // Pinned chrome since 5.13, never drawn from the composition. A copy
        // left in a layout by an older build is not a gap the user has to fix,
        // so it gets no warning.
        if kind == .providerSwitch { return nil }
        return reason(
            provider: kind.provider,
            isPlanFact: isPlanFact(kind),
            settings: settings, usage: usage, codex: codex
        )
    }

    private static func reason(
        provider: MetricProvider?,
        isPlanFact: Bool,
        settings: SettingsStore,
        usage: UsageStore,
        codex: CodexUsageStore
    ) -> EditorUnavailability {
        if let provider {
            guard settings.activeProviders.contains(provider) else {
                return .providerOff(provider)
            }
            guard settings.activeProviderMode.shows(provider) else {
                return .outOfScope(mode: settings.activeProviderMode.localizedLabel)
            }
        }
        // "Your plan does not have this" is only sayable once a payload has
        // landed. Before that the honest answer is that we do not know yet,
        // which is also what a Claude-only machine sees for every Codex
        // segment while the first refresh is in flight.
        guard hasFetched(provider, usage: usage, codex: codex) else { return .noDataYet }
        guard isPlanFact, let provider else { return .noDataYet }
        return .notOnPlan(provider)
    }

    private static func hasFetched(
        _ provider: MetricProvider?,
        usage: UsageStore,
        codex: CodexUsageStore
    ) -> Bool {
        switch provider {
        case .claude: return usage.lastUpdate != nil
        case .codex: return codex.lastUpdate != nil
        case nil: return usage.lastUpdate != nil || codex.lastUpdate != nil
        }
    }

    /// Kinds whose absence is a property of the plan rather than of the
    /// fetch: a window the subscription does not include, a pool it does not
    /// grant. Everything else that reports unavailable is missing data.
    private static func isPlanFact(_ kind: MenuBarSegmentKind) -> Bool {
        switch kind {
        case .fable, .fablePacing, .extraCredits,
             .codexSession, .codexSessionPacing,
             .codexWeekly, .codexWeeklyPacing:
            return true
        default:
            return false
        }
    }

    private static func isPlanFact(_ kind: PopoverElementKind) -> Bool {
        switch kind {
        case .fable, .fablePacing, .extraCredits,
             .codexSession, .codexSessionPacing,
             .codexWeekly, .codexWeeklyPacing:
            return true
        default:
            return false
        }
    }
}
