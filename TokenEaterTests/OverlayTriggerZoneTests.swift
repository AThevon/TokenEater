import Testing

@Suite("OverlayTriggerZone")
struct OverlayTriggerZoneTests {

    @Test("the default hover zone is the indicator strip itself (#271)")
    func defaultIsMinimal() {
        #expect(OverlayTriggerZone.defaultZone == .minimal)
    }
}
