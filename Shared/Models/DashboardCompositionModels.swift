import Foundation

/// The dashboard as an ordered list of blocks rather than a sequence frozen in
/// a view body.
///
/// Three layouts used to live hand-written in `MonitoringView`: one for All,
/// one for Claude alone, one for Codex alone. Every change meant editing each
/// of them and guessing which arrangement the user wanted, which is exactly
/// the loop this replaces.
///
/// One list drives all three. A provider mode renders it once; All renders it
/// once per provider, side by side, which is what makes the columns line up
/// row for row without anything coordinating them.
///
/// Blocks, not cards, and deliberately so. The dashboard's cards are not
/// interchangeable the way the popover's cells are: the hero flips and carries
/// a trajectory chart, the grid reflows to however many buckets the account
/// has, the pacing row carries workweek badges and cooldown estimates. A kind
/// enum pretending they are the same shape would be a lie, and an editor
/// would have to lay out five different heights.
enum DashboardBlock: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The big gauge. One per provider.
    case hero
    /// The secondary windows: weekly, Sonnet, Opus, Fable for Claude; the
    /// windows the plan declares for Codex.
    case windows
    /// Pacing cards for every window that has a rate.
    case pacing
    /// Claude's paid pool. Nothing on the Codex side, so the block simply does
    /// not render there.
    case extraCredits
    /// Plan, organisation, credits: the facts that are not measurements.
    case footer

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .hero:         return String(localized: "dashboard.block.hero")
        case .windows:      return String(localized: "dashboard.block.windows")
        case .pacing:       return String(localized: "dashboard.block.pacing")
        case .extraCredits: return String(localized: "dashboard.block.extraCredits")
        case .footer:       return String(localized: "dashboard.block.footer")
        }
    }

    var symbolName: String {
        switch self {
        case .hero:         return "gauge.high"
        case .windows:      return "square.grid.2x2.fill"
        case .pacing:       return "speedometer"
        case .extraCredits: return "creditcard.fill"
        case .footer:       return "tag.fill"
        }
    }

    /// Which providers can draw this block at all. A block no provider in the
    /// current mode can draw is skipped rather than rendered empty.
    var providers: Set<MetricProvider> {
        switch self {
        case .extraCredits: return [.claude]
        default:            return Set(MetricProvider.allCases)
        }
    }
}

/// An ordered, hideable list of blocks. Persisted per provider mode under the
/// same key scheme as the popover and menu bar compositions.
struct DashboardComposition: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Identifiable, Sendable {
        var block: DashboardBlock
        var isHidden: Bool = false

        var id: String { block.rawValue }
    }

    /// Bumped only if the entry shape changes. Adding a block does not: an
    /// unknown one drops on decode and a missing one is appended on load, so
    /// the list is always complete and always in a known order.
    static let currentVersion = 1

    var version: Int = currentVersion
    var entries: [Entry]

    /// The layout the app has always had, read top to bottom.
    static var `default`: DashboardComposition {
        DashboardComposition(entries: DashboardBlock.allCases.map { Entry(block: $0) })
    }

    var visibleBlocks: [DashboardBlock] {
        entries.filter { !$0.isHidden }.map(\.block)
    }

    /// Appends any block this build knows that the stored list is missing, so
    /// an older layout gains a new block at the end instead of silently never
    /// showing it. Blocks a build does not know are already gone by the time
    /// this runs: the lossy decoder drops those entries.
    static func reconciled(_ composition: DashboardComposition) -> DashboardComposition {
        var entries = composition.entries
        let known = Set(entries.map(\.block))
        for block in DashboardBlock.allCases where !known.contains(block) {
            entries.append(Entry(block: block))
        }
        return DashboardComposition(version: currentVersion, entries: entries)
    }

    init(version: Int = currentVersion, entries: [Entry]) {
        self.version = version
        self.entries = entries
    }

    enum CodingKeys: String, CodingKey { case version, entries }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? Self.currentVersion
        // Lossy on purpose, same contract as the popover composition: a block
        // written by a newer build is dropped rather than failing the decode
        // and throwing the user's whole layout away.
        entries = container.decodeLossyArray(Entry.self, forKey: .entries)
    }
}
