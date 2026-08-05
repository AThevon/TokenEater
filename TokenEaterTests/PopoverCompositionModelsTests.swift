import Testing
import Foundation

@Suite("PopoverCompositionModels")
struct PopoverCompositionModelsTests {

    // MARK: - Style / width matrix

    @Test("every style declares at least one width and a legal default")
    func styleWidthMatrix() {
        for style in PopoverElementStyle.allCases {
            #expect(!style.allowedWidths.isEmpty)
            #expect(style.allowedWidths.contains(style.defaultWidth))
        }
    }

    @Test("every kind declares at least one style, all width-compatible")
    func kindStyleMatrix() {
        for kind in PopoverElementKind.allCases {
            #expect(!kind.allowedStyles.isEmpty)
        }
    }

    @Test("fablePacing is a pacing element with the pacing style set (#241)")
    func fablePacingElementShape() {
        #expect(PopoverElementKind.fablePacing.family == .pacing)
        #expect(PopoverElementKind.fablePacing.allowedStyles == [.paceBar, .paceTile, .paceText])
        #expect(!PopoverElementKind.fablePacing.isChrome)
    }

    @Test("effectiveWidth clamps an illegal width to the closest legal one")
    func effectiveWidthClamps() {
        let arc = PopoverElement(kind: .session, style: .arc, width: .third)
        #expect(arc.effectiveWidth == .full)
        let ring = PopoverElement(kind: .session, style: .gaugeRing, width: .half)
        #expect(ring.effectiveWidth == .half)
        // A chip stored at .third (legal in early 5.9 dev builds) falls back
        // to .half, the closest legal fraction, not .full.
        let chip = PopoverElement(kind: .weekly, style: .chip, width: .third)
        #expect(chip.effectiveWidth == .half)
    }

    // MARK: - Codable round trip + forward compat

    @Test("composition survives an encode / decode round trip")
    func roundTrip() throws {
        let original = PopoverBuiltinTemplate.complete.composition
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PopoverComposition.self, from: data)
        #expect(decoded == original)
    }

    @Test("unknown element kind is dropped, valid siblings survive")
    func unknownKindDropped() throws {
        let json = """
        {"elements": [
            {"id":"\(UUID().uuidString)","kind":"session","style":"gaugeRing","width":"half","isHidden":false,"options":{"content":"percent","showReset":true}},
            {"id":"\(UUID().uuidString)","kind":"hologram","style":"gaugeRing","width":"half","isHidden":false,"options":{"content":"percent","showReset":false}}
        ],"showPlanBadge":true,"showRefreshButton":false}
        """
        let decoded = try JSONDecoder().decode(PopoverComposition.self, from: Data(json.utf8))
        #expect(decoded.elements.count == 1)
        #expect(decoded.elements[0].kind == .session)
        #expect(decoded.showRefreshButton == false)
    }

    @Test("unknown style or width drops only that element")
    func unknownStyleDropped() throws {
        let json = """
        {"elements": [
            {"kind":"session","style":"neonTube","width":"half"},
            {"kind":"weekly","style":"gaugeRing","width":"quarter"},
            {"kind":"timestamp","style":"utilityRow","width":"full"}
        ]}
        """
        let decoded = try JSONDecoder().decode(PopoverComposition.self, from: Data(json.utf8))
        #expect(decoded.elements.count == 1)
        #expect(decoded.elements[0].kind == .timestamp)
    }

    @Test("missing optional fields decode to their defaults")
    func missingFieldsDefault() throws {
        let json = """
        {"elements": [{"kind":"weekly","style":"chip","width":"third"}]}
        """
        let decoded = try JSONDecoder().decode(PopoverComposition.self, from: Data(json.utf8))
        #expect(decoded.showPlanBadge == true)
        #expect(decoded.showRefreshButton == true)
        let element = try #require(decoded.elements.first)
        #expect(element.isHidden == false)
        #expect(element.options == PopoverElementOptions())
    }

    // MARK: - Validation

    @Test("hasVisibleContent is false when everything is hidden")
    func allHiddenInvalid() {
        var composition = PopoverBuiltinTemplate.minimalist.composition
        for idx in composition.elements.indices {
            composition.elements[idx].isHidden = true
        }
        #expect(!composition.hasVisibleContent)
        #expect(composition.visibleElements.isEmpty)
    }

    // MARK: - Templates

    @Test("every built-in template is valid: non-empty, legal styles and widths")
    func builtinTemplatesValid() {
        for template in PopoverBuiltinTemplate.allCases {
            let composition = template.composition
            #expect(composition.hasVisibleContent, "\(template.rawValue) must have visible content")
            for element in composition.elements {
                #expect(element.kind.allowedStyles.contains(element.style),
                        "\(template.rawValue): \(element.kind) cannot render as \(element.style)")
                #expect(element.style.allowedWidths.contains(element.width),
                        "\(template.rawValue): \(element.style) cannot be \(element.width)")
            }
        }
    }

    @Test("templates mint fresh element ids on every access")
    func templatesMintFreshIDs() {
        let a = PopoverBuiltinTemplate.classic.composition
        let b = PopoverBuiltinTemplate.classic.composition
        #expect(Set(a.elements.map(\.id)).isDisjoint(with: Set(b.elements.map(\.id))))
    }

    @Test("default composition is the Classic template shape")
    func defaultIsClassic() {
        let def = PopoverComposition.default
        let classic = PopoverBuiltinTemplate.classic.composition
        #expect(def.elements.map(\.kind) == classic.elements.map(\.kind))
        #expect(def.elements.map(\.style) == classic.elements.map(\.style))
        #expect(def.elements.map(\.width) == classic.elements.map(\.width))
    }

    @Test("user template round trips through Codable")
    func userTemplateRoundTrip() throws {
        let template = PopoverUserTemplate(name: "My setup", composition: PopoverBuiltinTemplate.focus.composition)
        let data = try JSONEncoder().encode([template])
        let decoded = try JSONDecoder().decode([PopoverUserTemplate].self, from: data)
        #expect(decoded == [template])
    }
}
