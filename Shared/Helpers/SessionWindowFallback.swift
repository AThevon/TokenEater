import Foundation

/// What a layout draws for an account whose plan has no 5-hour session
/// window (Claude Ultra), asked by the popover and the menu bar alike, and
/// by their Studio editors so a row says what the surface actually draws.
///
/// Hiding the session slots alone would leave a Focus popover without its
/// arc, a Minimalist menu bar with nothing but the logo, and an added
/// account's section with nothing in it. So a session slot shows the week
/// instead, exactly like the dashboard's glance card: the session metric
/// becomes the weekly one, session pacing becomes weekly pacing. A slot
/// that has no weekly counterpart (the session reset countdown) is dropped.
///
/// The week is never drawn twice for one account. When a layout already
/// shows the same weekly figure for the same account (Classic: a session
/// ring next to a weekly ring), the wider of the two is kept, the layout's
/// own weekly element on a tie. Complete's full-width session hero therefore
/// becomes a weekly hero and its third-width weekly ring steps aside.
///
/// Render-time only: nothing is ever written back to a stored layout, so
/// the same layout draws its session slots again the day the window comes
/// back (Ultra to Max, or another account behind the element).
enum SessionWindowFallback {
    /// What an element or a segment is, as far as the session window goes.
    enum Role: Hashable, Sendable {
        /// The 5-hour usage figure.
        case session
        /// The 5-hour pace.
        case sessionPacing
        /// A session fact with no weekly counterpart (the reset countdown).
        case sessionOnly
        /// The weekly usage figure.
        case weekly
        /// The weekly pace.
        case weeklyPacing
        /// Anything else, left alone.
        case other

        /// Reads the 5-hour window.
        var isSession: Bool { self == .session || self == .sessionPacing || self == .sessionOnly }
    }

    enum Outcome: Equatable, Sendable {
        /// Drawn as stored.
        case unchanged
        /// A session slot drawing the weekly figure (or pace) instead.
        case renderedAsWeekly
        /// A session slot drawing nothing: no weekly counterpart, or the
        /// layout already shows the same weekly figure for this account.
        case dropped
        /// A weekly element the layout keeps but does not draw, because a
        /// wider session slot of the same account now shows that figure.
        case shownBySessionSlot
    }

    struct Item<ID: Hashable> {
        let id: ID
        let role: Role
        /// The account the element reads, resolved: twins are only ever
        /// looked for within one account.
        let account: AccountID?
        /// Whether that account's plan has no session window.
        let lacksSessionWindow: Bool
        /// What the element shows of its window ("percent", "countdown",
        /// "pace"): only elements showing the same thing are twins, so a
        /// countdown arc never swallows a percentage next to it.
        let shows: String
        /// The room the element takes, for keeping the wider twin.
        let width: Int

        init(
            id: ID, role: Role, account: AccountID?, lacksSessionWindow: Bool,
            shows: String = "", width: Int = 0
        ) {
            self.id = id
            self.role = role
            self.account = account
            self.lacksSessionWindow = lacksSessionWindow
            self.shows = shows
            self.width = width
        }
    }

    private struct TwinKey: Hashable {
        let role: Role
        let account: AccountID?
        let shows: String
    }

    /// The outcome of every item, in a dictionary keyed by id. Items that
    /// draw as stored map to `.unchanged`.
    static func outcomes<ID: Hashable>(for items: [Item<ID>]) -> [ID: Outcome] {
        var outcomes: [ID: Outcome] = [:]
        for item in items { outcomes[item.id] = .unchanged }

        // Every weekly element, real or standing in for a session slot,
        // grouped by what it shows for which account.
        var groups: [TwinKey: [(index: Int, standsIn: Bool)]] = [:]
        var order: [TwinKey] = []
        func add(_ key: TwinKey, _ entry: (index: Int, standsIn: Bool)) {
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(entry)
        }

        for (index, item) in items.enumerated() {
            switch item.role {
            case .session where item.lacksSessionWindow:
                outcomes[item.id] = .renderedAsWeekly
                add(TwinKey(role: .weekly, account: item.account, shows: item.shows), (index, true))
            case .sessionPacing where item.lacksSessionWindow:
                outcomes[item.id] = .renderedAsWeekly
                add(TwinKey(role: .weeklyPacing, account: item.account, shows: item.shows), (index, true))
            case .sessionOnly where item.lacksSessionWindow:
                outcomes[item.id] = .dropped
            case .weekly, .weeklyPacing:
                add(TwinKey(role: item.role, account: item.account, shows: item.shows), (index, false))
            default:
                break
            }
        }

        // Only a group a session slot joined changes anything: a layout
        // that shows the week twice on its own keeps doing so.
        for key in order {
            guard let entries = groups[key], entries.count > 1, entries.contains(where: \.standsIn) else { continue }
            // Widest first, then the layout's own weekly element, then the
            // earliest.
            let keeper = entries.min { a, b in
                let wa = items[a.index].width, wb = items[b.index].width
                if wa != wb { return wa > wb }
                if a.standsIn != b.standsIn { return !a.standsIn }
                return a.index < b.index
            }!
            for entry in entries where entry.index != keeper.index {
                outcomes[items[entry.index].id] = entry.standsIn ? .dropped : .shownBySessionSlot
            }
        }
        return outcomes
    }
}

// MARK: - Popover and menu bar

extension SessionWindowFallback {
    /// A popover element's part in the fallback.
    static func role(of kind: PopoverElementKind) -> Role {
        switch kind {
        case .session: return .session
        case .sessionPacing: return .sessionPacing
        case .weekly: return .weekly
        case .weeklyPacing: return .weeklyPacing
        default: return .other
        }
    }

    /// A menu bar segment's part in the fallback. The reset countdown has no
    /// weekly counterpart in the menu bar and is dropped.
    static func role(of kind: MenuBarSegmentKind) -> Role {
        switch kind {
        case .session: return .session
        case .sessionPacing: return .sessionPacing
        case .sessionReset: return .sessionOnly
        case .weekly: return .weekly
        case .weeklyPacing: return .weeklyPacing
        default: return .other
        }
    }

    /// What a popover element shows of its window: an arc or a big number
    /// set to the countdown is not the twin of a percentage.
    static func shows(_ element: PopoverElement) -> String {
        switch element.style {
        case .arc, .bigText: return element.options.content.rawValue
        case .paceBar, .paceTile, .paceText: return "pace"
        default: return PopoverMetricContent.percent.rawValue
        }
    }

    static func width(_ width: PopoverElementWidth) -> Int {
        switch width {
        case .full: return 3
        case .half: return 2
        case .third: return 1
        }
    }

    /// The popover elements as drawn: a session slot standing in for the
    /// week carries the weekly kind (same id, style, width and options), and
    /// the dropped ones are gone. `lacksSessionWindow` answers for an element
    /// of a Claude kind; `account` resolves the account it reads.
    static func rendered(
        _ elements: [PopoverElement],
        account: (PopoverElement) -> AccountID?,
        lacksSessionWindow: (PopoverElement) -> Bool
    ) -> (elements: [PopoverElement], outcomes: [UUID: Outcome]) {
        let outcomes = outcomes(for: elements.map { element in
            Item(
                id: element.id,
                role: role(of: element.kind),
                account: account(element),
                lacksSessionWindow: element.kind.provider == .claude && lacksSessionWindow(element),
                shows: shows(element),
                width: width(element.width)
            )
        })
        let drawn = elements.compactMap { element -> PopoverElement? in
            switch outcomes[element.id] ?? .unchanged {
            case .unchanged: return element
            case .dropped, .shownBySessionSlot: return nil
            case .renderedAsWeekly:
                var copy = element
                copy.kind = element.kind == .sessionPacing ? .weeklyPacing : .weekly
                return copy
            }
        }
        return (drawn, outcomes)
    }

    /// The menu bar segments as drawn, same contract.
    static func rendered(
        _ segments: [MenuBarSegment],
        account: (MenuBarSegment) -> AccountID?,
        lacksSessionWindow: (MenuBarSegment) -> Bool
    ) -> (segments: [MenuBarSegment], outcomes: [UUID: Outcome]) {
        let outcomes = outcomes(for: segments.map { segment in
            Item(
                id: segment.id,
                role: role(of: segment.kind),
                account: account(segment),
                lacksSessionWindow: segment.kind.provider == .claude && lacksSessionWindow(segment),
                shows: segment.kind.isPacing ? "pace" : "percent"
            )
        })
        let drawn = segments.compactMap { segment -> MenuBarSegment? in
            switch outcomes[segment.id] ?? .unchanged {
            case .unchanged: return segment
            case .dropped, .shownBySessionSlot: return nil
            case .renderedAsWeekly:
                var copy = segment
                copy.kind = segment.kind == .sessionPacing ? .weeklyPacing : .weekly
                // A style the weekly kind cannot draw falls back to its first.
                if !copy.kind.allowedStyles.contains(copy.style) {
                    copy.style = copy.kind.allowedStyles[0]
                }
                return copy
            }
        }
        return (drawn, outcomes)
    }
}
