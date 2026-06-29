import Testing
import Foundation

@Suite("TokenFormatter")
struct TokenFormatterTests {

    // MARK: - Below 1000: raw integer, no prefix

    @Test func zero() {
        #expect(TokenFormatter.compact(0) == "0")
    }

    @Test func smallValuePassesThrough() {
        #expect(TokenFormatter.compact(96) == "96")
    }

    @Test func justUnderThousand() {
        #expect(TokenFormatter.compact(999) == "999")
    }

    // MARK: - Thousands: one decimal below 10k, none at/above 10k

    @Test func exactlyOneThousandKeepsDecimal() {
        #expect(TokenFormatter.compact(1_000) == "1.0k")
    }

    @Test func lowThousandsKeepDecimal() {
        #expect(TokenFormatter.compact(1_200) == "1.2k")
    }

    @Test func roundsToOneDecimalBelowTenK() {
        // 9_990 -> 9.99k rounds to 10.0k at one decimal; verify the boundary
        // stays in the k branch and rounds as %.1f does.
        #expect(TokenFormatter.compact(5_490) == "5.5k")
    }

    @Test func atTenThousandDropsDecimal() {
        #expect(TokenFormatter.compact(10_000) == "10k")
    }

    @Test func largeThousandsNoDecimal() {
        #expect(TokenFormatter.compact(540_000) == "540k")
    }

    @Test func justUnderMillion() {
        #expect(TokenFormatter.compact(999_000) == "999k")
    }

    // MARK: - Millions: one decimal below 10M, none at/above 10M

    @Test func exactlyOneMillionKeepsDecimal() {
        #expect(TokenFormatter.compact(1_000_000) == "1.0M")
    }

    @Test func lowMillionsKeepDecimal() {
        #expect(TokenFormatter.compact(1_200_000) == "1.2M")
    }

    @Test func atTenMillionDropsDecimal() {
        // Regression guard for the widget alignment: was "12.0M", now "12M".
        #expect(TokenFormatter.compact(12_000_000) == "12M")
    }

    @Test func negativeValuePassesThroughRaw() {
        // Defensive: callers pass abs(...) for deltas, but a raw negative
        // must not crash and must not hit the SI branches.
        #expect(TokenFormatter.compact(-5) == "-5")
    }
}
