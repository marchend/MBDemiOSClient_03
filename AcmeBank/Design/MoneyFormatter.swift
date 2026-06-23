import Foundation

/// Currency formatting helper for the Home screen.
///
/// The Home AC requires negative balances to use a leading U+2212
/// MINUS SIGN \(not the ASCII hyphen-minus `-`\) and positive amounts
/// to render with the account's `currencyCode` symbol. `Foundation`'s
/// `NumberFormatter` already does the currency-symbol lookup; the
/// only thing we have to enforce manually is the U+2212 swap, because
/// `NumberFormatter.minusSign` ships as `-` on most locales.
///
/// All money values across the app flow through this single helper
/// so the U+2212 rule cannot drift \- a future PR that adds a
/// transfer screen reuses `format\(_:currencyCode:\)` rather than
/// re-implementing the rule.
enum MoneyFormatter {

    /// Format `amount` with `currencyCode`'s symbol/grouping rules,
    /// using U+2212 as the negative sign.
    ///
    /// - Parameters:
    ///   - amount: Signed `Decimal`. Negative values produce a
    ///     `"\u{2212}1,234.56"`-shaped string; positive values are
    ///     unsigned.
    ///   - currencyCode: ISO-4217 code, e.g. `"CAD"`, `"USD"`. Passed
    ///     to `NumberFormatter.currencyCode` so the symbol matches
    ///     the account's reporting currency rather than the device
    ///     locale.
    /// - Returns: A localized currency string with U+2212 on
    ///   negatives. Falls back to `"<symbol><amount>"` if the
    ///   formatter unexpectedly returns nil so the UI never shows
    ///   an empty cell.
    static func format(_ amount: Decimal, currencyCode: String) -> String {
        let formatter = makeFormatter(currencyCode: currencyCode)
        let nsAmount = NSDecimalNumber(decimal: amount)
        let formatted = formatter.string(from: nsAmount) ?? "\(currencyCode) \(nsAmount.stringValue)"
        return formatted
    }

    /// Build a configured `NumberFormatter` for the given currency
    /// code. Extracted so unit tests can assert on the formatter's
    /// configuration if needed without re-deriving it.
    ///
    /// The U+2212 swap is performed by overriding
    /// `minusSign` directly. `NumberFormatter` then uses this string
    /// in place of the locale default `-` when it renders a
    /// negative value.
    private static func makeFormatter(currencyCode: String) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        // U+2212 MINUS SIGN. Using the explicit braced escape (and
        // the literal Unicode scalar) so a reviewer can grep for it
        // and the source compiles independent of any glyph the IDE
        // tries to render.
        f.minusSign = "\u{2212}"
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }
}
