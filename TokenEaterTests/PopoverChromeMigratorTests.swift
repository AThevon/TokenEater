import Testing
import Foundation

@Suite("PopoverChromeMigrator")
struct PopoverChromeMigratorTests {

    /// A version-1 composition the way a 5.9 blob decodes: elements without
    /// chrome kinds, header state carried by the two legacy toggles.
    private func v1(
        elements: [PopoverElement]? = nil,
        planBadge: Bool = true,
        refreshButton: Bool = true
    ) -> PopoverComposition {
        PopoverComposition(
            elements: elements ?? [
                PopoverElement(kind: .session, style: .gaugeRing, width: .half),
                PopoverElement(kind: .weekly, style: .gaugeRing, width: .half),
            ],
            version: 1,
            showPlanBadge: planBadge,
            showRefreshButton: refreshButton
        )
    }

    @Test("v1 with both toggles on gains a visible badge+refresh half row at the top")
    func migratesVisibleChrome() {
        let result = PopoverChromeMigrator.migrate(v1())

        #expect(result.version == PopoverComposition.currentVersion)
        #expect(result.elements.map(\.kind) == [.planBadge, .refreshButton, .session, .weekly])
        let badge = result.elements[0]
        let refresh = result.elements[1]
        #expect(badge.style == .badge)
        #expect(badge.width == .half)
        #expect(!badge.isHidden)
        #expect(refresh.style == .actionButton)
        #expect(refresh.width == .half)
        #expect(!refresh.isHidden)
    }

    @Test("v1 toggles off become hidden chrome elements, not dropped ones")
    func migratesHiddenChrome() {
        let result = PopoverChromeMigrator.migrate(v1(planBadge: false, refreshButton: false))

        #expect(result.elements.map(\.kind) == [.planBadge, .refreshButton, .session, .weekly])
        #expect(result.elements[0].isHidden)
        #expect(result.elements[1].isHidden)
    }

    @Test("mixed toggles migrate each element's hidden flag independently")
    func migratesMixedToggles() {
        let result = PopoverChromeMigrator.migrate(v1(planBadge: false, refreshButton: true))

        #expect(result.elements[0].kind == .planBadge)
        #expect(result.elements[0].isHidden)
        #expect(result.elements[1].kind == .refreshButton)
        #expect(!result.elements[1].isHidden)
    }

    @Test("a v2 composition passes through untouched, so deleted chrome never comes back")
    func v2PassesThrough() {
        let noChrome = PopoverComposition(elements: [
            PopoverElement(kind: .session, style: .gaugeRing, width: .full),
        ])
        let result = PopoverChromeMigrator.migrate(noChrome)

        #expect(result == noChrome)
        #expect(!result.elements.contains { $0.kind == .planBadge || $0.kind == .refreshButton })
    }

    @Test("migration is one-shot: a second pass over the result is a no-op")
    func idempotent() {
        let once = PopoverChromeMigrator.migrate(v1())
        let twice = PopoverChromeMigrator.migrate(once)

        #expect(twice == once)
    }

    @Test("a v1 blob that already carries a chrome kind never gets a duplicate")
    func noDuplicateChrome() {
        let handEdited = v1(elements: [
            PopoverElement(kind: .planBadge, style: .badge, width: .full),
            PopoverElement(kind: .session, style: .gaugeRing, width: .half),
        ])
        let result = PopoverChromeMigrator.migrate(handEdited)

        #expect(result.elements.filter { $0.kind == .planBadge }.count == 1)
        #expect(result.elements.filter { $0.kind == .refreshButton }.count == 1)
        // The pre-existing badge keeps its shape; only the missing refresh
        // button is prepended.
        #expect(result.elements.map(\.kind) == [.refreshButton, .planBadge, .session])
    }

    @Test("the legacy config migrator emits version 1 so the chrome chain still runs")
    func legacyConfigChain() {
        let migrated = PopoverConfigMigrator.migrate(
            PopoverConfig.default,
            displaySonnet: false,
            displayFable: false,
            displayExtraCredits: false
        )
        #expect(migrated.version == 1)

        let chromed = PopoverChromeMigrator.migrate(migrated)
        #expect(chromed.version == PopoverComposition.currentVersion)
        #expect(chromed.elements.first?.kind == .planBadge)
        #expect(chromed.elements.dropFirst().first?.kind == .refreshButton)
    }

    // MARK: - Codable behavior backing the migration

    @Test("a blob without a version field decodes as version 1")
    func missingVersionDecodesAsV1() throws {
        let json = """
        {"elements": [], "showPlanBadge": true, "showRefreshButton": false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PopoverComposition.self, from: json)

        #expect(decoded.version == 1)
        #expect(decoded.showPlanBadge)
        #expect(!decoded.showRefreshButton)
    }

    @Test("encoding a v2 composition mirrors chrome visibility into the legacy toggles")
    func encodeDerivesLegacyToggles() throws {
        var composition = PopoverBuiltinTemplate.classic.composition
        // Hide the refresh button element; the badge stays visible.
        if let idx = composition.elements.firstIndex(where: { $0.kind == .refreshButton }) {
            composition.elements[idx].isHidden = true
        }

        let data = try JSONEncoder().encode(composition)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["version"] as? Int == PopoverComposition.currentVersion)
        #expect(object["showPlanBadge"] as? Bool == true)
        #expect(object["showRefreshButton"] as? Bool == false)
    }

    @Test("a v2 composition round trips with its version and chrome elements intact")
    func v2RoundTrip() throws {
        let original = PopoverBuiltinTemplate.complete.composition
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PopoverComposition.self, from: data)

        #expect(decoded.version == PopoverComposition.currentVersion)
        #expect(decoded.elements.map(\.kind) == original.elements.map(\.kind))
        #expect(decoded.elements.map(\.isHidden) == original.elements.map(\.isHidden))
    }

    @Test("every built-in template opens with the visible chrome pair")
    func templatesCarryChrome() {
        for template in PopoverBuiltinTemplate.allCases {
            let composition = template.composition
            #expect(composition.version == PopoverComposition.currentVersion)
            #expect(composition.elements.count >= 2)
            #expect(composition.elements[0].kind == .planBadge)
            #expect(composition.elements[0].style == .badge)
            #expect(composition.elements[1].kind == .refreshButton)
            #expect(composition.elements[1].style == .actionButton)
            #expect(!composition.elements[0].isHidden)
            #expect(!composition.elements[1].isHidden)
        }
    }
}
