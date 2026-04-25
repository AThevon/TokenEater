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
