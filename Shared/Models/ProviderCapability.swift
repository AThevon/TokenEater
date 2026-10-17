import Foundation

/// What TokenEater can do, and for whom.
///
/// This is the single declaration the whole provider story reads from. Before
/// it, the answer to "why did Agent Watchers disappear when I switched to
/// OpenAI" lived nowhere: the app just hid things. Writing a helper line under
/// each affected setting would have put the same sentence in six places and
/// left the seventh out on the next change.
///
/// Everything derives from here instead: the badge on a section header, the
/// caption under the mode pills naming what the current mode cannot show, the
/// Coverage page in Settings, and the matrix the what's-new window animates.
/// Adding a provider adds entries to these sets; adding a capability adds one
/// case. Neither touches a view.
enum ProviderCapability: String, CaseIterable, Identifiable, Sendable {
    case usageWindows
    case smartColor
    case pacing
    case notifications
    case surfaces
    case history
    case perModel
    case extraCredits
    case agentWatchers
    case outageDetection
    case widgets

    var id: String { rawValue }

    /// How well a provider is served. Three states, not two: History and the
    /// widgets are genuinely partial, and calling either "supported" or
    /// "missing" would be a lie in one direction or the other.
    enum Support: Equatable, Sendable {
        case full
        /// Carries a short reason, shown in the Coverage page.
        case partial(String)
        case none
    }

    func support(for provider: MetricProvider) -> Support {
        switch self {
        case .usageWindows, .smartColor, .pacing, .notifications, .surfaces:
            return .full

        case .history:
            // Both providers' tokens are charted. Sessions and per-project
            // totals are recorded per bucket rather than per model, so they
            // cannot be split by provider; see `HistoryStore.gate`.
            return provider == .claude
                ? .full
                : .partial(String(localized: "capability.history.partial"))

        case .widgets:
            return provider == .claude
                ? .partial(String(localized: "capability.widgets.claude"))
                : .partial(String(localized: "capability.widgets.codex"))

        case .perModel, .extraCredits, .agentWatchers, .outageDetection:
            return provider == .claude ? .full : .none
        }
    }

    func isSupported(by provider: MetricProvider) -> Bool {
        support(for: provider) != .none
    }

    var providers: Set<MetricProvider> {
        Set(MetricProvider.allCases.filter(isSupported(by:)))
    }

    /// True when the providers do not agree, which is the only case worth
    /// drawing attention to on a section header.
    var isUneven: Bool {
        providers.count != MetricProvider.allCases.count
    }

    var localizedName: String {
        switch self {
        case .usageWindows:    return String(localized: "capability.usageWindows")
        case .smartColor:      return String(localized: "capability.smartColor")
        case .pacing:          return String(localized: "capability.pacing")
        case .notifications:   return String(localized: "capability.notifications")
        case .surfaces:        return String(localized: "capability.surfaces")
        case .history:         return String(localized: "capability.history")
        case .perModel:        return String(localized: "capability.perModel")
        case .extraCredits:    return String(localized: "capability.extraCredits")
        case .agentWatchers:   return String(localized: "capability.agentWatchers")
        case .outageDetection: return String(localized: "capability.outageDetection")
        case .widgets:         return String(localized: "capability.widgets")
        }
    }
}

extension ProviderMode {
    /// What this mode cannot show, in declaration order.
    ///
    /// Empty in `.all`, which is the point: a mode only owes an explanation
    /// when it is actively hiding something. This is what the caption under
    /// the pills reads, so the app names the cost of the choice at the moment
    /// the choice was made rather than leaving the user to discover an empty
    /// panel later.
    var unavailableCapabilities: [ProviderCapability] {
        guard let provider else { return [] }
        return ProviderCapability.allCases.filter { !$0.isSupported(by: provider) }
    }
}
