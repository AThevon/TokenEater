import Foundation

/// One-shot conversion of the legacy variant-based `PopoverConfig` (pre-5.9)
/// into an equivalent `PopoverComposition`, so upgrading users see the same
/// popover they had before the composable system landed.
///
/// Pure function: `SettingsStore` calls it once when the new
/// `popoverComposition` blob is absent but the old `popoverConfig` one exists.
/// The old blob is deliberately left in UserDefaults so downgrading restores
/// the previous popover untouched.
enum PopoverConfigMigrator {
    /// Account-presence snapshot at migration time, read from the cached
    /// usage in shared.json. The legacy renderer gated the Design / Fable /
    /// Extra Credits satellites on `displayX && hasX` at every render;
    /// migration must apply the same gate or a stale toggle (e.g. Design
    /// enabled during the research preview, access lost since) would flip
    /// the layout shape the user never saw. Sonnet was never presence-gated.
    struct AccountPresence {
        var hasDesign: Bool
        var hasFable: Bool
        var hasExtraCredits: Bool

        init(hasDesign: Bool = true, hasFable: Bool = true, hasExtraCredits: Bool = true) {
            self.hasDesign = hasDesign
            self.hasFable = hasFable
            self.hasExtraCredits = hasExtraCredits
        }

        /// Derives presence exactly like `UsageStore.updateUI` does. A nil
        /// cache (fresh machine, wiped shared dir) trusts the toggles, which
        /// matches the optimistic pre-refresh state of the old renderer.
        init(cachedUsage: UsageResponse?) {
            guard let usage = cachedUsage else {
                self.init()
                return
            }
            self.init(
                hasDesign: usage.sevenDayDesign != nil,
                hasFable: usage.sevenDayFable != nil,
                hasExtraCredits: usage.extraUsage?.isEnabled == true
            )
        }
    }

    /// - Parameters:
    ///   - displaySonnet...displayExtraCredits: the legacy "Show X" switches
    ///     that gated the extra satellites outside the block system. An
    ///     enabled switch becomes a real element when the account also has
    ///     the metric (same render-time gate as the old layouts).
    static func migrate(
        _ config: PopoverConfig,
        displaySonnet: Bool,
        displayDesign: Bool,
        displayFable: Bool,
        displayExtraCredits: Bool,
        presence: AccountPresence = AccountPresence()
    ) -> PopoverComposition {
        // The old init reconciled per variant: an all-hidden layout rendered
        // as that variant's defaults. Reproduce it before converting so an
        // all-hidden Compact blob still migrates to Compact chips, not to
        // the global Classic fallback.
        var config = config
        if !config.hasVisibleContent(for: .classic) { config.classic = .classicDefault }
        if !config.hasVisibleContent(for: .compact) { config.compact = .compactDefault }

        let extras = extraKinds(
            sonnet: displaySonnet,
            design: displayDesign && presence.hasDesign,
            fable: displayFable && presence.hasFable,
            extraCredits: displayExtraCredits && presence.hasExtraCredits
        )

        let elements: [PopoverElement]
        switch config.activeVariant {
        case .classic:
            elements = migrateClassic(config.classic, extras: extras)
        case .compact:
            elements = migrateCompact(config.compact, extras: extras)
        case .focus:
            elements = migrateFocus(config.focus, hero: config.focusHero, extras: extras)
        }

        // Version 1 on purpose: the legacy config predates the chrome
        // elements, so `PopoverChromeMigrator` must still convert the two
        // header toggles below into real elements.
        return PopoverComposition(
            elements: elements,
            version: 1,
            showPlanBadge: config.showPlanBadge,
            showRefreshButton: config.showRefreshButton
        )
    }

    // MARK: - Classic

    private static func migrateClassic(_ layout: VariantLayout, extras: [PopoverElementKind]) -> [PopoverElement] {
        var out: [PopoverElement] = []
        let sessionState = layout.hero.first { $0.id == .sessionRing }
        let weeklyState = layout.hero.first { $0.id == .weeklyRing }
        let sessionVisible = sessionState.map { !$0.hidden } ?? false

        if !extras.isEmpty && sessionVisible {
            // Legacy hero + satellites arrangement: big session ring, then a
            // row of small rings (weekly + enabled extras) at third width.
            out.append(PopoverElement(kind: .session, style: .gaugeRing, width: .full, options: .init(showReset: true)))
            if let weeklyState {
                out.append(PopoverElement(kind: .weekly, style: .gaugeRing, width: .third, isHidden: weeklyState.hidden))
            }
            for kind in extras {
                out.append(PopoverElement(kind: kind, style: .gaugeRing, width: .third))
            }
        } else {
            // Equal rings, following stored hero order + hidden flags.
            for state in layout.hero {
                guard let kind = usageKind(forHeroBlock: state.id) else { continue }
                out.append(PopoverElement(
                    kind: kind, style: .gaugeRing, width: .half,
                    isHidden: state.hidden, options: .init(showReset: true)
                ))
            }
            // Extras were enabled but the session ring is hidden - the legacy
            // renderer fell back to equal rings and dropped them; keep them as
            // a satellites row so the user's intent survives.
            for kind in extras {
                out.append(PopoverElement(kind: kind, style: .gaugeRing, width: .third))
            }
        }

        out.append(contentsOf: migrateSharedMiddle(layout.middle, paceStyle: .paceBar, paceWidth: .full))
        return out
    }

    // MARK: - Compact

    private static func migrateCompact(_ layout: VariantLayout, extras: [PopoverElementKind]) -> [PopoverElement] {
        // Extras render as small satellite rings: a card chip at a third of
        // the row crushes its label, so `.chip` no longer allows `.third`.
        var out: [PopoverElement] = extras.map {
            PopoverElement(kind: $0, style: .gaugeRing, width: .third)
        }
        // The legacy renderer paired only consecutive VISIBLE chips with
        // chips and tiles with tiles; anything unpaired rendered full width.
        // Reproduce that so a lone chip doesn't shrink to half after the
        // migration. Hidden chips/tiles default to half (they render nothing
        // until the user unhides them in the new editor anyway).
        let pairedWidths = legacyCompactWidths(layout.middle)
        for state in layout.middle {
            switch state.id {
            case .sessionChip:
                out.append(PopoverElement(kind: .session, style: .chip, width: pairedWidths[state.id] ?? .half, isHidden: state.hidden, options: .init(showReset: true)))
            case .weeklyChip:
                out.append(PopoverElement(kind: .weekly, style: .chip, width: pairedWidths[state.id] ?? .half, isHidden: state.hidden, options: .init(showReset: true)))
            case .sessionPaceTile:
                out.append(PopoverElement(kind: .sessionPacing, style: .paceTile, width: pairedWidths[state.id] ?? .half, isHidden: state.hidden))
            case .weeklyPaceTile:
                out.append(PopoverElement(kind: .weeklyPacing, style: .paceTile, width: pairedWidths[state.id] ?? .half, isHidden: state.hidden))
            default:
                if let element = utilityElement(for: state) { out.append(element) }
            }
        }
        return out
    }

    /// Widths the legacy Compact grouping produced: consecutive visible
    /// same-family blocks (chip+chip, tile+tile) shared a row at half width,
    /// unpaired ones stretched full width.
    private static func legacyCompactWidths(_ middle: [BlockState]) -> [PopoverBlockID: PopoverElementWidth] {
        let chips: Set<PopoverBlockID> = [.sessionChip, .weeklyChip]
        let tiles: Set<PopoverBlockID> = [.sessionPaceTile, .weeklyPaceTile]
        let visible = middle.filter { !$0.hidden }.map(\.id)

        var widths: [PopoverBlockID: PopoverElementWidth] = [:]
        var i = 0
        while i < visible.count {
            let id = visible[i]
            let family: Set<PopoverBlockID>? = chips.contains(id) ? chips : (tiles.contains(id) ? tiles : nil)
            guard let family else { i += 1; continue }
            if i + 1 < visible.count, family.contains(visible[i + 1]) {
                widths[id] = .half
                widths[visible[i + 1]] = .half
                i += 2
            } else {
                widths[id] = .full
                i += 1
            }
        }
        return widths
    }

    // MARK: - Focus

    private static func migrateFocus(
        _ layout: VariantLayout,
        hero: FocusHeroChoice,
        extras: [PopoverElementKind]
    ) -> [PopoverElement] {
        var out: [PopoverElement] = []

        out.append(PopoverElement(
            kind: metricKind(for: hero), style: .arc, width: .full,
            options: .init(content: content(for: hero))
        ))
        for satellite in FocusHeroChoice.satellites(for: hero) {
            out.append(PopoverElement(
                kind: metricKind(for: satellite), style: .bigText, width: .half,
                options: .init(content: content(for: satellite))
            ))
        }
        out.append(contentsOf: extras.map {
            PopoverElement(kind: $0, style: .gaugeRing, width: .third)
        })
        out.append(contentsOf: migrateSharedMiddle(layout.middle, paceStyle: .paceText, paceWidth: .full))
        return out
    }

    // MARK: - Shared pieces

    /// Maps the middle zone of Classic / Focus: pacing blocks take the
    /// variant's pacing style, utility blocks map one-to-one. Order and
    /// hidden flags are preserved.
    private static func migrateSharedMiddle(
        _ middle: [BlockState],
        paceStyle: PopoverElementStyle,
        paceWidth: PopoverElementWidth
    ) -> [PopoverElement] {
        middle.compactMap { state in
            switch state.id {
            case .sessionPaceBar, .sessionPaceMini:
                return PopoverElement(kind: .sessionPacing, style: paceStyle, width: paceWidth, isHidden: state.hidden)
            case .weeklyPaceBar, .weeklyPaceMini:
                return PopoverElement(kind: .weeklyPacing, style: paceStyle, width: paceWidth, isHidden: state.hidden)
            default:
                return utilityElement(for: state)
            }
        }
    }

    private static func utilityElement(for state: BlockState) -> PopoverElement? {
        switch state.id {
        case .watchers:
            return PopoverElement(kind: .watchers, style: .utilityRow, width: .full, isHidden: state.hidden)
        case .timestamp:
            return PopoverElement(kind: .timestamp, style: .utilityRow, width: .full, isHidden: state.hidden)
        case .openTokenEaterButton:
            return PopoverElement(kind: .openButton, style: .actionButton, width: .full, isHidden: state.hidden)
        case .quitButton:
            return PopoverElement(kind: .quitButton, style: .actionButton, width: .full, isHidden: state.hidden)
        default:
            return nil
        }
    }

    private static func extraKinds(
        sonnet: Bool, design: Bool, fable: Bool, extraCredits: Bool
    ) -> [PopoverElementKind] {
        var kinds: [PopoverElementKind] = []
        if sonnet { kinds.append(.sonnet) }
        if design { kinds.append(.design) }
        if fable { kinds.append(.fable) }
        if extraCredits { kinds.append(.extraCredits) }
        return kinds
    }

    private static func usageKind(forHeroBlock id: PopoverBlockID) -> PopoverElementKind? {
        switch id {
        case .sessionRing: return .session
        case .weeklyRing: return .weekly
        default: return nil
        }
    }

    private static func metricKind(for choice: FocusHeroChoice) -> PopoverElementKind {
        switch choice {
        case .sessionReset, .sessionValue: return .session
        case .weeklyReset, .weeklyValue: return .weekly
        }
    }

    private static func content(for choice: FocusHeroChoice) -> PopoverMetricContent {
        switch choice {
        case .sessionReset, .weeklyReset: return .resetCountdown
        case .sessionValue, .weeklyValue: return .percent
        }
    }
}
