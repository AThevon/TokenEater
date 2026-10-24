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
    /// The secondary windows: weekly plus whichever per-model limits the
    /// account carries (Fable, rarely Sonnet or Opus) for Claude; the
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

// MARK: - Home sections

/// One section of the home page in All: a Claude account, or Codex. A
/// section is drawn whole (header, notice, blocks), the way a provider mode
/// draws its one provider.
enum HomeSection: Hashable, Identifiable, Sendable {
    case claude(AccountID)
    case codex

    /// What `sectionOrder` stores: the account's own identifier (`main`,
    /// `acct-<id>`) or `codex`.
    var storageID: String {
        switch self {
        case .claude(let account): return account.rawValue
        case .codex: return Self.codexID
        }
    }

    var id: String { storageID }

    var provider: MetricProvider {
        switch self {
        case .claude: return .claude
        case .codex: return .codex
        }
    }

    static let codexID = "codex"

    /// Nil for anything this build would never have written, so a stored
    /// order cannot smuggle an arbitrary string into an account id.
    init?(storageID: String) {
        if storageID == Self.codexID {
            self = .codex
        } else if AccountID.isValid(storageID) {
            self = .claude(AccountID(rawValue: storageID))
        } else {
            return nil
        }
    }
}

/// How the home page in All lays its sections out.
enum HomeLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    /// One section full width, two side by side, three or more stacked.
    case auto
    /// Always stacked, full width.
    case oneColumn
    /// Two per row, in order, top aligned.
    case twoColumns

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .auto:       return String(localized: "dashboard.layout.auto")
        case .oneColumn:  return String(localized: "dashboard.layout.oneColumn")
        case .twoColumns: return String(localized: "dashboard.layout.twoColumns")
        }
    }

    var localizedHelp: String {
        switch self {
        case .auto:       return String(localized: "dashboard.layout.auto.help")
        case .oneColumn:  return String(localized: "dashboard.layout.oneColumn.help")
        case .twoColumns: return String(localized: "dashboard.layout.twoColumns.help")
        }
    }

    var symbolName: String {
        switch self {
        case .auto:       return "sparkles"
        case .oneColumn:  return "rectangle.grid.1x2"
        case .twoColumns: return "rectangle.split.2x1"
        }
    }
}

/// The order of the sections, as the user arranged them in Studio. It sorts
/// the home sections, the popover's account sections in All and the mode
/// pills, so an account sits at the same place everywhere. The menu bar keeps
/// its own composition order.
///
/// Pure, so the reconciliation is unit tested: the stored list is only ever
/// written by the Studio control, and every reader goes through `reconciled`.
enum HomeSectionOrder {
    /// The order with nothing stored: the main account then Codex, as 6.0
    /// laid them out, then the added accounts in the order they were added.
    /// A new account lands at the end whether or not the order was ever
    /// rearranged, so two people with the same order on screen see a new
    /// account land at the same place.
    static func defaultOrder(accounts: [AccountID]) -> [HomeSection] {
        accounts.filter(\.isMain).map(HomeSection.claude)
            + [.codex]
            + accounts.filter { !$0.isMain }.map(HomeSection.claude)
    }

    /// Every tracked account and Codex, once each. The stored ids come first
    /// in their order; an id that is malformed, repeated or no longer tracked
    /// (a removed account) is dropped; a section the stored list does not name
    /// yet (an account added since) goes at the end.
    static func reconciled(_ stored: [String], accounts: [AccountID]) -> [HomeSection] {
        let known = defaultOrder(accounts: accounts)
        let knownSet = Set(known)
        var result: [HomeSection] = []
        for id in stored {
            guard let section = HomeSection(storageID: id),
                  knownSet.contains(section),
                  !result.contains(section) else { continue }
            result.append(section)
        }
        for section in known where !result.contains(section) {
            result.append(section)
        }
        return result
    }

    /// The full order once the sections on screen were rearranged: they take
    /// the places they already held in `full`, in their new order, so a
    /// paused account or Codex switched off keeps its own place.
    static func applying(_ visible: [HomeSection], to full: [HomeSection]) -> [HomeSection] {
        let shown = Set(visible)
        var queue = visible.filter { full.contains($0) }[...]
        var result = full.map { section -> HomeSection in
            guard shown.contains(section), let next = queue.popFirst() else { return section }
            return next
        }
        // A visible section `full` did not hold (never the case once both
        // come from the same store) still lands somewhere.
        result.append(contentsOf: visible.filter { !full.contains($0) })
        return result
    }
}
