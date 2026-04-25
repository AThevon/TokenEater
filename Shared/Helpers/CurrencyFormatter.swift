import Foundation

/// Formats monetary values returned by the Anthropic API for the "Extra Credits"
/// pool. The API returns amounts in the **minor unit** of the configured
/// currency (cents for USD/EUR, no division for JPY/KRW, mils for KWD/BHD).
/// Naively passing those values through a `.currency` `NumberFormatter` shows
/// them x100 (or x1000) too large. This helper looks up the canonical
/// fraction-digit count per ISO 4217 currency and divides accordingly.
enum CurrencyFormatter {
    /// Formats a minor-unit amount (e.g. `18000` cents) as a localised currency
    /// string (e.g. `$180`).
    ///
    /// - Parameters:
    ///   - minorUnits: amount in the currency's minor unit.
    ///   - currencyCode: ISO 4217 code. Falls back to `USD` when nil/empty so
    ///     the dashboard never renders a raw number without a symbol.
    ///   - locale: locale used for digit grouping and symbol placement.
    ///     Defaults to the user's current locale; tests pin it for stability.
    /// - Returns: localised currency string. Whole major-unit values omit
    ///   trailing zeros (`$180`, not `$180.00`); fractional values keep the
    ///   currency's canonical fraction digits (`$180.50`).
    static func formatMinorUnits(
        _ minorUnits: Double,
        currencyCode: String?,
        locale: Locale = .current
    ) -> String {
        let code = (currencyCode?.isEmpty == false) ? currencyCode! : "USD"

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = locale

        // Once `currencyCode` is set, `maximumFractionDigits` reflects the
        // canonical minor-unit count for that ISO 4217 code:
        // USD/EUR=2, JPY/KRW=0, KWD/BHD=3. We use that to scale the raw value
        // back to the major unit.
        let fractionDigits = formatter.maximumFractionDigits
        let divisor = pow(10.0, Double(fractionDigits))
        let majorValue = divisor > 0 ? minorUnits / divisor : minorUnits

        let isWhole = majorValue.truncatingRemainder(dividingBy: 1) == 0
        formatter.maximumFractionDigits = isWhole ? 0 : fractionDigits
        formatter.minimumFractionDigits = isWhole ? 0 : fractionDigits

        return formatter.string(from: NSNumber(value: majorValue))
            ?? "\(code) \(majorValue)"
    }
}
