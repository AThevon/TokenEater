import Foundation

/// Splits the popover's elements into the sections it draws once two Claude
/// accounts run: between two pieces of neutral chrome (plan badge, refresh,
/// timestamp, buttons), one section per account and one for Codex, each
/// under a small header naming it and in the section order; the chrome in
/// sections of its own with no header.
///
/// Pure: the views decide which elements are visible, and this only groups
/// what they hand it. `PopoverRowPacker` then packs each section on its own,
/// so a half-width cell never shares a row with another account's.
enum PopoverSectionGrouping {
    enum Key: Hashable {
        case claude(AccountID)
        case codex
        case neutral

        var id: String {
            switch self {
            case .claude(let account): return "claude." + account.rawValue
            case .codex: return "codex"
            case .neutral: return "neutral"
            }
        }

        /// Sections that name what they hold. Neutral chrome belongs to no
        /// account and needs no header.
        var hasHeader: Bool { self != .neutral }
    }

    struct Section: Equatable, Identifiable {
        let key: Key
        let elements: [PopoverElement]
        /// Stable across renders: the key, plus how many sections of the same
        /// key came before it (an account split by a Codex run gets two).
        let id: String
    }

    /// The account each element resolves to, then the runs of equal keys.
    /// A Claude element whose account is not running (see
    /// `AccountID.effective`) is left out, as the renderer leaves it out.
    ///
    /// The sections that name an account or Codex then follow `order` (the
    /// section order of Studio), so the popover lists the accounts as the
    /// home page and the mode pills do (see `ordered`).
    static func groups(
        _ elements: [PopoverElement],
        mode: ProviderMode,
        focused: AccountID,
        running: Set<AccountID>,
        order: [HomeSection] = []
    ) -> [Section] {
        var runs: [Run] = []
        for element in elements {
            let key: Key
            switch element.kind.provider {
            case .claude:
                guard let account = AccountID.effective(
                    declared: element.account, mode: mode, focused: focused, running: running
                ) else { continue }
                key = .claude(account)
            case .codex:
                key = .codex
            case nil:
                key = .neutral
            }
            add(element, key: key, to: &runs)
        }
        var seen: [Key: Int] = [:]
        return ordered(runs, by: order).map { run in
            let occurrence = seen[run.key, default: 0]
            seen[run.key] = occurrence + 1
            return Section(key: run.key, elements: run.elements, id: "\(run.key.id)#\(occurrence)")
        }
    }

    /// Consecutive elements of one key, before they become a `Section`.
    struct Run: Equatable {
        let key: Key
        var elements: [PopoverElement]
    }

    /// Adds the element to the last run when it has the same key, or opens
    /// a new one.
    private static func add(_ element: PopoverElement, key: Key, to runs: inout [Run]) {
        if let last = runs.last, last.key == key {
            runs[runs.count - 1].elements.append(element)
        } else {
            runs.append(Run(key: key, elements: [element]))
        }
    }

    /// The runs with each stretch of headed sections sorted by `order`, then
    /// the neighbours of one key merged into one section.
    ///
    /// A stretch ends at neutral chrome, so the order never carries an
    /// account across it: the header row stays on top, the buttons at the
    /// bottom, and a section the composition put below Quit stays below it.
    /// Merging is what keeps an interleaved layout ("Side by side" puts
    /// Claude and Codex cells in turn) to one header per account rather
    /// than one per cell. Stable: a key `order` does not name comes after
    /// the named ones, in the composition's order.
    static func ordered(_ runs: [Run], by order: [HomeSection]) -> [Run] {
        guard !order.isEmpty else { return runs }
        var rank: [Key: Int] = [:]
        for (index, section) in order.enumerated() {
            switch section {
            case .claude(let account): rank[.claude(account)] = index
            case .codex: rank[.codex] = index
            }
        }
        var result: [Run] = []
        var stretch: [Run] = []
        func flush() {
            let sorted = stretch.enumerated().sorted { lhs, rhs in
                let left = rank[lhs.element.key] ?? Int.max
                let right = rank[rhs.element.key] ?? Int.max
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            for (_, run) in sorted {
                for element in run.elements { add(element, key: run.key, to: &result) }
            }
            stretch = []
        }
        for run in runs {
            if run.key.hasHeader {
                stretch.append(run)
            } else {
                flush()
                result.append(run)
            }
        }
        flush()
        return result
    }
}
