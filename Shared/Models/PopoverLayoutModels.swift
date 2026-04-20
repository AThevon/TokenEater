import Foundation

enum PopoverVariant: String, Codable, CaseIterable, Identifiable {
    case classic, compact, focus
    var id: String { rawValue }
}

enum PopoverBlockID: String, Codable, CaseIterable, Identifiable {
    case sessionRing, weeklyRing
    case sessionPaceBar, weeklyPaceBar
    case sessionChip, weeklyChip, sessionPaceTile, weeklyPaceTile
    case sessionPaceMini, weeklyPaceMini
    case watchers, timestamp
    case openTokenEaterButton, quitButton
    var id: String { rawValue }
}

/// Focus-only. Picked via radio in settings, drives which metric renders
/// as the big hero piece. The 3 non-hero candidates automatically feed the
/// 2-card satellites row (the 2 most relevant picked by `satellites(for:)`).
enum FocusHeroChoice: String, Codable, CaseIterable, Identifiable {
    case sessionReset, weeklyReset, sessionValue, weeklyValue
    var id: String { rawValue }
}

enum PopoverZone: String, Codable {
    case hero, middle, footer
}

struct BlockState: Codable, Equatable, Identifiable {
    let id: PopoverBlockID
    var hidden: Bool

    init(_ id: PopoverBlockID, hidden: Bool = false) {
        self.id = id
        self.hidden = hidden
    }
}

struct VariantLayout: Codable, Equatable {
    var hero: [BlockState]
    /// All non-hero blocks in a single ordered list. Merging what used to be
    /// "middle" and "footer" into one zone lets the user intermix action
    /// buttons (Open / Quit) with content rows freely.
    var middle: [BlockState]
}

struct PopoverConfig: Codable, Equatable {
    var activeVariant: PopoverVariant
    var classic: VariantLayout
    var compact: VariantLayout
    var focus: VariantLayout
    var focusHero: FocusHeroChoice
    /// Shows the PRO / MAX / TEAM badge in the popover header. On by default.
    /// Stored at the root because the header is variant-agnostic.
    var showPlanBadge: Bool

    init(
        activeVariant: PopoverVariant,
        classic: VariantLayout,
        compact: VariantLayout,
        focus: VariantLayout,
        focusHero: FocusHeroChoice,
        showPlanBadge: Bool = true
    ) {
        self.activeVariant = activeVariant
        self.classic = classic
        self.compact = compact
        self.focus = focus
        self.focusHero = focusHero
        self.showPlanBadge = showPlanBadge
    }

    // Custom decoder so upgrading from a config stored without `showPlanBadge`
    // doesn't throw - we default the missing field to `true`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeVariant = try c.decode(PopoverVariant.self, forKey: .activeVariant)
        classic = try c.decode(VariantLayout.self, forKey: .classic)
        compact = try c.decode(VariantLayout.self, forKey: .compact)
        focus = try c.decode(VariantLayout.self, forKey: .focus)
        focusHero = try c.decode(FocusHeroChoice.self, forKey: .focusHero)
        showPlanBadge = try c.decodeIfPresent(Bool.self, forKey: .showPlanBadge) ?? true
    }

    /// Fresh defaults that reproduce the v4.10.x popover visually when `activeVariant == .classic`.
    static let `default` = PopoverConfig(
        activeVariant: .classic,
        classic: .classicDefault,
        compact: .compactDefault,
        focus: .focusDefault,
        focusHero: .sessionReset
    )

    /// Rebuild the layout for a given variant without touching the others.
    /// Used by the "Reset to defaults" button per variant.
    mutating func resetLayout(for variant: PopoverVariant) {
        switch variant {
        case .classic: classic = .classicDefault
        case .compact: compact = .compactDefault
        case .focus:
            focus = .focusDefault
            focusHero = .sessionReset
        }
    }

    /// Accessor / writer for the layout of the active variant.
    var activeLayout: VariantLayout {
        get {
            switch activeVariant {
            case .classic: return classic
            case .compact: return compact
            case .focus: return focus
            }
        }
        set {
            switch activeVariant {
            case .classic: classic = newValue
            case .compact: compact = newValue
            case .focus: focus = newValue
            }
        }
    }
}

extension VariantLayout {
    static let classicDefault = VariantLayout(
        hero: [BlockState(.sessionRing), BlockState(.weeklyRing)],
        middle: [
            BlockState(.sessionPaceBar),
            BlockState(.weeklyPaceBar),
            BlockState(.watchers),
            BlockState(.timestamp),
            BlockState(.openTokenEaterButton),
            BlockState(.quitButton),
        ]
    )

    static let compactDefault = VariantLayout(
        hero: [],
        middle: [
            BlockState(.sessionChip),
            BlockState(.weeklyChip),
            BlockState(.sessionPaceTile),
            BlockState(.weeklyPaceTile),
            BlockState(.watchers),
            BlockState(.timestamp),
            BlockState(.openTokenEaterButton),
            BlockState(.quitButton),
        ]
    )

    static let focusDefault = VariantLayout(
        hero: [],
        middle: [
            BlockState(.sessionPaceMini),
            BlockState(.weeklyPaceMini),
            BlockState(.watchers),
            BlockState(.timestamp),
            BlockState(.openTokenEaterButton),
            BlockState(.quitButton),
        ]
    )
}

extension FocusHeroChoice {
    /// The 2 non-hero metrics that auto-render as satellites for a given hero.
    /// Order matters (first card left, second card right).
    static func satellites(for hero: FocusHeroChoice) -> [FocusHeroChoice] {
        switch hero {
        case .sessionReset: return [.sessionValue, .weeklyValue]
        case .weeklyReset:  return [.weeklyValue, .sessionValue]
        case .sessionValue: return [.sessionReset, .weeklyValue]
        case .weeklyValue:  return [.weeklyReset, .sessionValue]
        }
    }
}

// MARK: - Validation

extension PopoverConfig {
    /// Returns true if at least one block is visible in `hero` + `middle` combined.
    /// Footer is allowed to be fully hidden.
    func hasVisibleContent(for variant: PopoverVariant) -> Bool {
        let layout: VariantLayout = {
            switch variant {
            case .classic: return classic
            case .compact: return compact
            case .focus: return focus
            }
        }()
        let heroVisible = layout.hero.contains { !$0.hidden }
        let middleVisible = layout.middle.contains { !$0.hidden }
        // Focus variant always has a hero (driven by focusHero), so treat it as visible.
        if variant == .focus { return true }
        return heroVisible || middleVisible
    }
}

// MARK: - Labels (for settings UI)

extension PopoverBlockID {
    /// Human-readable label used in the BlockListEditor rows.
    /// Localized via NSLocalizedString - String(localized:) with an
    /// interpolated key would turn `rawValue` into a `%@` placeholder
    /// and look up "popoverBlock.%@" instead of the real key.
    var localizedLabel: String {
        NSLocalizedString("popoverBlock.\(rawValue)", comment: "")
    }
}

extension PopoverVariant {
    var localizedLabel: String {
        NSLocalizedString("popoverVariant.\(rawValue)", comment: "")
    }
}

extension FocusHeroChoice {
    var localizedLabel: String {
        NSLocalizedString("focusHero.\(rawValue)", comment: "")
    }
}
