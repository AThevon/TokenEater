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

    // MARK: - Accounts

    /// A menu bar blob exactly as 6.0 wrote it, keys sorted.
    private static let blob60 = #"{"segments":[{"id":"6F1B1D0C-6B1F-4C5B-9A43-1B6E8A6F0A01","isHidden":false,"kind":"session","options":{"pacingShape":"circle","resetFormat":"relative"},"style":"labelValue"},{"id":"6F1B1D0C-6B1F-4C5B-9A43-1B6E8A6F0A02","isHidden":true,"kind":"codexWeekly","options":{"pacingShape":"diamond","resetFormat":"both"},"style":"pill"}]}"#

    private func sortedEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    @Test("a 6.0 blob decodes and re-encodes byte for byte")
    func blob60IsByteIdentical() throws {
        let decoded = try JSONDecoder().decode(MenuBarComposition.self, from: Data(Self.blob60.utf8))
        #expect(decoded.accountLabel == .dotAndName)
        #expect(decoded.segments.allSatisfy { $0.account == nil })
        let encoded = try sortedEncoder().encode(decoded)
        #expect(String(data: encoded, encoding: .utf8) == Self.blob60)
    }

    @Test("a segment's account survives the round trip")
    func accountRoundTrip() throws {
        let id = AccountID(rawValue: "acct-1")
        let composition = MenuBarComposition(
            segments: [MenuBarSegment(kind: .session, style: .labelValue, account: id)],
            accountLabel: .dot
        )
        let data = try JSONEncoder().encode(composition)
        let decoded = try JSONDecoder().decode(MenuBarComposition.self, from: data)
        #expect(decoded == composition)
        #expect(decoded.segments[0].account == id)
        #expect(decoded.accountLabel == .dot)
    }

    @Test("an unreadable account falls back to the mode's account, the segment stays")
    func invalidAccountIsNil() throws {
        let json = #"{"segments":[{"kind":"session","style":"labelValue","account":42},{"kind":"weekly","style":"labelValue","account":"acct-../x"}]}"#
        let decoded = try JSONDecoder().decode(MenuBarComposition.self, from: Data(json.utf8))
        #expect(decoded.segments.count == 2)
        #expect(decoded.segments.allSatisfy { $0.account == nil })
    }

    @Test("the default account label is never written")
    func accountLabelOmittedWhenDefault() throws {
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(MenuBarComposition.default)) as? [String: Any]
        #expect(plain?.keys.sorted() == ["segments"])
        let custom = MenuBarComposition(segments: [], accountLabel: .dot)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(custom)) as? [String: Any]
        #expect(object?["accountLabel"] as? String == "dot")
    }

    @Test("two layouts that differ only by account are not equivalent")
    func equivalenceSeesAccount() {
        let a = MenuBarComposition(segments: [MenuBarSegment(kind: .session, style: .labelValue)])
        let b = MenuBarComposition(segments: [MenuBarSegment(kind: .session, style: .labelValue, account: AccountID(rawValue: "acct-1"))])
        #expect(!a.isEquivalent(to: b))
        #expect(a.isEquivalent(to: MenuBarComposition(segments: [MenuBarSegment(kind: .session, style: .labelValue)])))
    }
}
