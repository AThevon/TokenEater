import Testing

@Suite("Smoke")
struct SmokeTests {
    @Test("project compiles and test target runs")
    func smokeTest() {
        #expect(true)
    }
}
