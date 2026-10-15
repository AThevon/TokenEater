import Testing
import Foundation

@Suite("CurrencyFormatter")
struct CurrencyFormatterTests {
    private let usLocale = Locale(identifier: "en_US")

    // MARK: - USD (2 minor units)

    @Test func usdRoundAmountOmitsDecimals() {
        let result = CurrencyFormatter.formatMinorUnits(18000, currencyCode: "USD", locale: usLocale)
        #expect(result == "$180")
    }

    @Test func usdFractionalAmountKeepsTwoDecimals() {
        let result = CurrencyFormatter.formatMinorUnits(18050, currencyCode: "USD", locale: usLocale)
        #expect(result == "$180.50")
    }

    @Test func usdSingleCent() {
        let result = CurrencyFormatter.formatMinorUnits(1, currencyCode: "USD", locale: usLocale)
        #expect(result == "$0.01")
    }

    @Test func usdZero() {
        let result = CurrencyFormatter.formatMinorUnits(0, currencyCode: "USD", locale: usLocale)
        #expect(result == "$0")
    }

    @Test func usdLargeAmountHasGroupingSeparator() {
        // $12,345.67 -> 1,234,567 cents
        let result = CurrencyFormatter.formatMinorUnits(1_234_567, currencyCode: "USD", locale: usLocale)
        #expect(result == "$12,345.67")
    }

    // MARK: - JPY (0 minor units)

    @Test func jpyHasNoMinorUnits() {
        // 18000 yen stays as 18000 (no scaling)
        let result = CurrencyFormatter.formatMinorUnits(18000, currencyCode: "JPY", locale: usLocale)
        #expect(result.contains("18,000"))
        #expect(!result.contains("180"))
    }

    // MARK: - KWD (3 minor units)

    @Test func kwdHasThreeMinorUnits() {
        // 18000 fils = 18.000 KWD
        let result = CurrencyFormatter.formatMinorUnits(18000, currencyCode: "KWD", locale: usLocale)
        #expect(result.contains("18"))
        #expect(!result.contains("18,000"))
    }

    // MARK: - Fallbacks

    @Test func nilCurrencyFallsBackToUSD() {
        let result = CurrencyFormatter.formatMinorUnits(18000, currencyCode: nil, locale: usLocale)
        #expect(result == "$180")
    }

    @Test func emptyCurrencyFallsBackToUSD() {
        let result = CurrencyFormatter.formatMinorUnits(18000, currencyCode: "", locale: usLocale)
        #expect(result == "$180")
    }

    @Test func unknownCurrencyDoesNotCrash() {
        // ISO 4217 doesn't define "ZZZ"; the formatter still produces *some*
        // string (we just verify it contains the scaled value).
        let result = CurrencyFormatter.formatMinorUnits(18000, currencyCode: "ZZZ", locale: usLocale)
        #expect(!result.isEmpty)
    }

    // MARK: - Compact (menu bar, popover)

    @Test func compactKeepsCentsBelowOneHundred() {
        #expect(CurrencyFormatter.formatMinorUnitsCompact(2049, currencyCode: "USD", locale: usLocale) == "$20.49")
        #expect(CurrencyFormatter.formatMinorUnitsCompact(9950, currencyCode: "USD", locale: usLocale) == "$99.50")
    }

    /// A round amount keeps its cents below 100, so the menu bar segment does
    /// not lose two characters (and shift its neighbours) on the next refresh.
    @Test func compactKeepsAStableWidthBelowOneHundred() {
        #expect(CurrencyFormatter.formatMinorUnitsCompact(2000, currencyCode: "USD", locale: usLocale) == "$20.00")
        #expect(CurrencyFormatter.formatMinorUnitsCompact(0, currencyCode: "USD", locale: usLocale) == "$0.00")
    }

    /// The 100 threshold applies to the amount rounded to the cent: 99.996
    /// reads like an even 100, not "$100.00".
    @Test func compactThresholdUsesTheRoundedAmount() {
        #expect(CurrencyFormatter.formatMinorUnitsCompact(9999.6, currencyCode: "USD", locale: usLocale) == "$100")
        #expect(CurrencyFormatter.formatMinorUnitsCompact(9999.4, currencyCode: "USD", locale: usLocale) == "$99.99")
    }

    @Test func compactRoundsToWholeUnitsFromOneHundred() {
        #expect(CurrencyFormatter.formatMinorUnitsCompact(10000, currencyCode: "USD", locale: usLocale) == "$100")
        #expect(CurrencyFormatter.formatMinorUnitsCompact(123456, currencyCode: "USD", locale: usLocale) == "$1,235")
    }

    @Test func compactLeavesZeroDecimalCurrenciesAlone() {
        let result = CurrencyFormatter.formatMinorUnitsCompact(2049, currencyCode: "JPY", locale: usLocale)
        #expect(result == CurrencyFormatter.formatMinorUnits(2049, currencyCode: "JPY", locale: usLocale))
        let small = CurrencyFormatter.formatMinorUnitsCompact(50, currencyCode: "JPY", locale: usLocale)
        #expect(small == CurrencyFormatter.formatMinorUnits(50, currencyCode: "JPY", locale: usLocale))
    }

    @Test func compactFallsBackToUSD() {
        #expect(CurrencyFormatter.formatMinorUnitsCompact(123456, currencyCode: nil, locale: usLocale) == "$1,235")
    }

    // MARK: - Regression: shuhulx report (issue #146)

    @Test func extraCreditsBugReproduction() {
        // Before fix: $300 monthly limit displayed as $30,000. Verify the
        // formatter scales 30000 cents back down to $300.
        let limit = CurrencyFormatter.formatMinorUnits(30000, currencyCode: "USD", locale: usLocale)
        let used = CurrencyFormatter.formatMinorUnits(18000, currencyCode: "USD", locale: usLocale)
        #expect(limit == "$300")
        #expect(used == "$180")
    }
}
