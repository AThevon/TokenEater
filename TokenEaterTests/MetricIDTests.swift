import Testing
import Foundation

@Suite("MetricID")
struct MetricIDTests {

    @Test("extraCredits has a stable raw value for persistence")
    func extraCreditsRawValue() {
        // pinnedMetrics persists raw values to UserDefaults, so this string is
        // a storage contract — changing it would silently drop users' pins.
        #expect(MetricID.extraCredits.rawValue == "extraCredits")
        #expect(MetricID(rawValue: "extraCredits") == .extraCredits)
    }

    @Test("extraCredits is enumerable and labelled")
    func extraCreditsLabels() {
        #expect(MetricID.allCases.contains(.extraCredits))
        #expect(MetricID.extraCredits.shortLabel == "EC")
        #expect(!MetricID.extraCredits.label.isEmpty)
    }
}
