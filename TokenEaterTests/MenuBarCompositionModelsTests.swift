import Testing
import Foundation

@Suite("MenuBarCompositionModels")
struct MenuBarCompositionModelsTests {

    @Test("every kind declares at least one style, all self-consistent")
    func kindStyleMatrix() {
        for kind in MenuBarSegmentKind.allCases {
            #expect(!kind.allowedStyles.isEmpty)
        }
    }

    @Test("fablePacing is a presence-gated pacing segment (#241)")
    func fablePacingSegmentShape() {
        #expect(MenuBarSegmentKind.fablePacing.family == .pacing)
        #expect(MenuBarSegmentKind.fablePacing.isPresenceGated)
        #expect(MenuBarSegmentKind.fablePacing.allowedStyles == [.dot, .dotDelta, .delta, .pill])
    }

    @Test("effectiveStyle clamps an illegal style to the kind's first legal one")
    func effectiveStyleClamps() {
        // A usage kind can't render as a pacing dot.
        let seg = MenuBarSegment(kind: .session, style: .dot)
        #expect(seg.effectiveStyle == .labelValue)
        let ok = MenuBarSegment(kind: .session, style: .pill)
        #expect(ok.effectiveStyle == .pill)
    }

    @Test("composition survives an encode / decode round trip")
    func roundTrip() throws {
        let original = MenuBarBuiltinTemplate.complete.composition
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MenuBarComposition.self, from: data)
        #expect(decoded == original)
    }

    @Test("unknown segment kind is dropped, valid siblings survive")
    func unknownKindDropped() throws {
        let json = """
        {"segments": [
            {"id":"\(UUID().uuidString)","kind":"session","style":"labelValue","isHidden":false,"options":{}},
            {"id":"\(UUID().uuidString)","kind":"telepathy","style":"labelValue","isHidden":false,"options":{}}
        ]}
        """
        let decoded = try JSONDecoder().decode(MenuBarComposition.self, from: Data(json.utf8))
        #expect(decoded.segments.count == 1)
        #expect(decoded.segments[0].kind == .session)
    }

    @Test("unknown style drops only that segment")
    func unknownStyleDropped() throws {
        let json = """
        {"segments": [
            {"kind":"session","style":"hologram"},
            {"kind":"weekly","style":"labelValue"}
        ]}
        """
        let decoded = try JSONDecoder().decode(MenuBarComposition.self, from: Data(json.utf8))
        #expect(decoded.segments.count == 1)
        #expect(decoded.segments[0].kind == .weekly)
    }

    @Test("missing optional fields decode to defaults")
    func missingFieldsDefault() throws {
        let json = """
        {"segments": [{"kind":"sessionPacing","style":"dotDelta"}]}
        """
        let decoded = try JSONDecoder().decode(MenuBarComposition.self, from: Data(json.utf8))
        let seg = try #require(decoded.segments.first)
        #expect(seg.isHidden == false)
        #expect(seg.options == MenuBarSegmentOptions())
    }

    @Test("hasVisibleContent reflects hidden segments")
    func visibility() {
        var c = MenuBarBuiltinTemplate.classic.composition
        #expect(c.hasVisibleContent)
        for i in c.segments.indices { c.segments[i].isHidden = true }
        #expect(!c.hasVisibleContent)
        #expect(c.visibleSegments.isEmpty)
    }

    @Test("every built-in template is valid: legal styles, non-empty")
    func builtinTemplatesValid() {
        for template in MenuBarBuiltinTemplate.allCases {
            let c = template.composition
            #expect(c.hasVisibleContent, "\(template.rawValue) must have visible content")
            for seg in c.segments {
                #expect(seg.kind.allowedStyles.contains(seg.style),
                        "\(template.rawValue): \(seg.kind) cannot render as \(seg.style)")
            }
        }
    }

    @Test("templates mint fresh segment ids on every access")
    func templatesMintFreshIDs() {
        let a = MenuBarBuiltinTemplate.classic.composition
        let b = MenuBarBuiltinTemplate.classic.composition
        #expect(Set(a.segments.map(\.id)).isDisjoint(with: Set(b.segments.map(\.id))))
    }

    @Test("user template round trips through Codable")
    func userTemplateRoundTrip() throws {
        let t = MenuBarUserTemplate(name: "My bar", composition: MenuBarBuiltinTemplate.pills.composition)
        let data = try JSONEncoder().encode([t])
        let decoded = try JSONDecoder().decode([MenuBarUserTemplate].self, from: data)
        #expect(decoded == [t])
    }
}
