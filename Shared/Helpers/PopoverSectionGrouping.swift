import Foundation

/// Splits the popover's elements into the sections it draws once two Claude
/// accounts run: one per run of consecutive elements that belong to the same
/// account (or to Codex), each under a small header naming it, and the
/// neutral chrome (plan badge, refresh, timestamp, buttons) in sections of
/// its own with no header.
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
    static func groups(
        _ elements: [PopoverElement],
        mode: ProviderMode,
        focused: AccountID,
        running: Set<AccountID>
    ) -> [Section] {
        var sections: [(key: Key, elements: [PopoverElement])] = []
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
            if let last = sections.last, last.key == key {
                sections[sections.count - 1].elements.append(element)
            } else {
                sections.append((key, [element]))
            }
        }
        var seen: [Key: Int] = [:]
        return sections.map { section in
            let occurrence = seen[section.key, default: 0]
            seen[section.key] = occurrence + 1
            return Section(key: section.key, elements: section.elements, id: "\(section.key.id)#\(occurrence)")
        }
    }
}
