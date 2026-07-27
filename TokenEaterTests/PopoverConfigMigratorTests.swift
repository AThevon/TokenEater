import Testing
import Foundation

@Suite("PopoverConfigMigrator")
struct PopoverConfigMigratorTests {

    private func migrate(
        _ config: PopoverConfig,
        sonnet: Bool = false, design: Bool = false, fable: Bool = false, extraCredits: Bool = false
    ) -> PopoverComposition {
        PopoverConfigMigrator.migrate(
            config,
            displaySonnet: sonnet, displayDesign: design,
            displayFable: fable, displayExtraCredits: extraCredits
        )
    }

    private func defaultConfig(variant: PopoverVariant) -> PopoverConfig {
        var config = PopoverConfig.default
        config.activeVariant = variant
        return config
    }

    // MARK: - Classic

    @Test("default Classic becomes two half rings + full-width middle rows")
    func classicDefault() {
        let result = migrate(defaultConfig(variant: .classic))
        let kinds = result.elements.map(\.kind)
        #expect(kinds == [.session, .weekly, .sessionPacing, .weeklyPacing, .watchers, .timestamp, .openButton, .quitButton])

        let session = result.elements[0]
        #expect(session.style == .gaugeRing)
        #expect(session.width == .half)
        #expect(session.options.showReset)

        #expect(result.elements[2].style == .paceBar)
        #expect(result.elements[2].width == .full)
        #expect(result.elements[6].style == .actionButton)
    }

    @Test("Classic with satellites becomes hero ring + thirds row")
    func classicWithSatellites() {
        let result = migrate(defaultConfig(variant: .classic), sonnet: true, fable: true)
        let head = result.elements.prefix(4)
        #expect(head.map(\.kind) == [.session, .weekly, .sonnet, .fable])
        #expect(head[head.startIndex].width == .full)
        #expect(head[head.startIndex].style == .gaugeRing)
        #expect(Array(head.dropFirst()).allSatisfy { $0.width == .third && $0.style == .gaugeRing })
    }

    @Test("Classic: a stale Design toggle without account access keeps the equal-rings shape")
    func classicStaleToggleKeepsEqualRings() {
        // displayDesign was left on (research preview) but the cached usage
        // says the account no longer has Design: the legacy renderer gated
        // the satellite on presence at every render and kept equal rings.
        let result = PopoverConfigMigrator.migrate(
            defaultConfig(variant: .classic),
            displaySonnet: false, displayDesign: true,
            displayFable: false, displayExtraCredits: false,
            presence: .init(hasDesign: false)
        )
        #expect(result.elements[0].kind == .session)
        #expect(result.elements[0].width == .half)
        #expect(!result.elements.contains { $0.kind == .design })
    }

    @Test("Classic hidden flags survive migration")
    func classicHiddenPreserved() {
        var config = defaultConfig(variant: .classic)
        config.classic.hero[1].hidden = true          // weeklyRing
        config.classic.middle[1].hidden = true        // weeklyPaceBar
        let result = migrate(config)
        #expect(result.elements.first { $0.kind == .weekly }?.isHidden == true)
        #expect(result.elements.first { $0.kind == .weeklyPacing }?.isHidden == true)
        #expect(result.elements.first { $0.kind == .session }?.isHidden == false)
    }

    @Test("Classic middle order is preserved")
    func classicOrderPreserved() {
        var config = defaultConfig(variant: .classic)
        // User moved the quit button above the pacing rows.
        let quit = config.classic.middle.remove(at: 5)
        config.classic.middle.insert(quit, at: 0)
        let result = migrate(config)
        let middleKinds = result.elements.dropFirst(2).map(\.kind)
        #expect(middleKinds.first == .quitButton)
    }

    // MARK: - Compact

    @Test("default Compact becomes half chips + half tiles + full utilities")
    func compactDefault() {
        let result = migrate(defaultConfig(variant: .compact))
        let kinds = result.elements.map(\.kind)
        #expect(kinds == [.session, .weekly, .sessionPacing, .weeklyPacing, .watchers, .timestamp, .openButton, .quitButton])
        #expect(result.elements[0].style == .chip)
        #expect(result.elements[0].width == .half)
        #expect(result.elements[0].options.showReset)
        #expect(result.elements[2].style == .paceTile)
        #expect(result.elements[2].width == .half)
    }

    @Test("Compact extras become a leading thirds satellite-ring row")
    func compactExtras() {
        let result = migrate(defaultConfig(variant: .compact), sonnet: true, design: true)
        #expect(result.elements[0].kind == .sonnet)
        #expect(result.elements[1].kind == .design)
        #expect(result.elements[0].style == .gaugeRing)
        #expect(result.elements[0].width == .third)
    }

    @Test("Compact: a lone visible chip migrates full width like the legacy grouping")
    func compactLoneChipFullWidth() {
        var config = defaultConfig(variant: .compact)
        // Hide weeklyChip: sessionChip is unpaired in the visible sequence,
        // the legacy renderer stretched it full width.
        config.compact.middle[1].hidden = true
        let result = migrate(config)
        #expect(result.elements.first { $0.kind == .session }?.width == .full)
        #expect(result.elements.first { $0.kind == .weekly }?.isHidden == true)
        // The two tiles still pair up at half width.
        #expect(result.elements.first { $0.kind == .sessionPacing }?.width == .half)
        #expect(result.elements.first { $0.kind == .weeklyPacing }?.width == .half)
    }

    @Test("Compact: interleaved chips and tiles migrate full width (legacy never paired across families)")
    func compactInterleavedFullWidth() {
        var config = defaultConfig(variant: .compact)
        // [sessionChip, sessionPaceTile, weeklyChip, weeklyPaceTile, ...]
        let tile = config.compact.middle.remove(at: 2)
        config.compact.middle.insert(tile, at: 1)
        let result = migrate(config)
        for kind in [PopoverElementKind.session, .weekly, .sessionPacing, .weeklyPacing] {
            #expect(result.elements.first { $0.kind == kind }?.width == .full, "\(kind) should be full width")
        }
    }

    @Test("Compact all-hidden legacy blob migrates to the Compact defaults, not the Classic fallback")
    func compactAllHiddenFallsBackToCompactDefault() {
        var config = defaultConfig(variant: .compact)
        for idx in config.compact.middle.indices {
            config.compact.middle[idx].hidden = true
        }
        let result = migrate(config)
        #expect(result.hasVisibleContent)
        // The old init reconciled the variant to its defaults (chips), so the
        // migrated composition must be chips too, not the Classic rings.
        #expect(result.elements.first { $0.kind == .session }?.style == .chip)
    }

    // MARK: - Focus

    @Test("default Focus becomes session reset arc + two bigText satellites + pace texts")
    func focusDefault() {
        let result = migrate(defaultConfig(variant: .focus))
        #expect(result.elements[0].kind == .session)
        #expect(result.elements[0].style == .arc)
        #expect(result.elements[0].options.content == .resetCountdown)

        // satellites(for: .sessionReset) == [.sessionValue, .weeklyValue]
        #expect(result.elements[1].kind == .session)
        #expect(result.elements[1].style == .bigText)
        #expect(result.elements[1].options.content == .percent)
        #expect(result.elements[2].kind == .weekly)
        #expect(result.elements[2].options.content == .percent)

        #expect(result.elements[3].kind == .sessionPacing)
        #expect(result.elements[3].style == .paceText)
    }

    @Test("Focus weeklyValue hero maps to weekly percent arc")
    func focusWeeklyValueHero() {
        var config = defaultConfig(variant: .focus)
        config.focusHero = .weeklyValue
        let result = migrate(config)
        #expect(result.elements[0].kind == .weekly)
        #expect(result.elements[0].options.content == .percent)
        // satellites(for: .weeklyValue) == [.weeklyReset, .sessionValue]
        #expect(result.elements[1].kind == .weekly)
        #expect(result.elements[1].options.content == .resetCountdown)
        #expect(result.elements[2].kind == .session)
        #expect(result.elements[2].options.content == .percent)
    }

    // MARK: - Header + validity

    @Test("header toggles are copied verbatim")
    func headerToggles() {
        var config = defaultConfig(variant: .classic)
        config.showPlanBadge = false
        config.showRefreshButton = false
        let result = migrate(config)
        #expect(result.showPlanBadge == false)
        #expect(result.showRefreshButton == false)
    }

    @Test("every migrated variant yields a valid non-empty composition")
    func migratedCompositionsAreValid() {
        for variant in PopoverVariant.allCases {
            let result = migrate(defaultConfig(variant: variant), sonnet: true, design: true, fable: true, extraCredits: true)
            #expect(result.hasVisibleContent)
            for element in result.elements {
                #expect(element.kind.allowedStyles.contains(element.style))
                #expect(element.style.allowedWidths.contains(element.width))
            }
        }
    }
}
