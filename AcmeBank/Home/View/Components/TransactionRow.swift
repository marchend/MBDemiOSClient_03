import SwiftUI

/// A single posted transaction inside `TransactionsSection`.
///
/// Visual contract:
///   - Leading circular monochrome avatar carrying the first letter
///     of `merchant_name ?? description` (so payroll / internal
///     transfers with a nil merchant still get a sensible glyph).
///   - Primary label: the BFF `description` (NOT `merchantName`). The
///     description is always present and is the customer-facing label
///     the BFF curates.
///   - Secondary label: `posted_date` formatted `"MMM d, yyyy"`.
///   - Trailing signed amount in the SAME primary text colour as
///     positives. The leading U+2212 on negatives comes from
///     `MoneyFormatter` - we do NOT colour negatives red.
///
/// Avatar-letter, formatted-date, and formatted-amount builders are
/// exposed as static helpers so `HomeViewModelRenderingTests` can
/// assert on them.
struct TransactionRow: View {
    let transaction: Transaction
    /// The transaction's currency code is not on the wire today (the
    /// BFF treats transactions as same-currency as the parent account
    /// for now); the parent section passes the account's currency
    /// code down so amounts format consistently.
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(BankPalette.navy)
                    .frame(width: 36, height: 36)
                Text(TransactionRow.avatarLetter(for: transaction))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BankPalette.onNavy)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BankPalette.primaryText)
                    .lineLimit(1)

                Text(TransactionRow.formattedDate(for: transaction))
                    .font(.footnote)
                    .foregroundStyle(BankPalette.secondaryText)
            }

            Spacer(minLength: 0)

            Text(TransactionRow.formattedAmount(for: transaction, currencyCode: currencyCode))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BankPalette.primaryText)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BankPalette.surface)
        )
    }

    // MARK: - Test-visible string builders

    /// First letter of `merchantName` when present, otherwise first
    /// letter of `description`. Falls back to `"?"` if both are
    /// empty - defensive only; the BFF guarantees a non-empty
    /// description.
    static func avatarLetter(for tx: Transaction) -> String {
        if let merchant = tx.merchantName, let c = merchant.first {
            return String(c).uppercased()
        }
        if let c = tx.description.first {
            return String(c).uppercased()
        }
        return "?"
    }

    /// `posted_date` rendered as `"MMM d, yyyy"`.
    static func formattedDate(for tx: Transaction) -> String {
        return DateFormatters.formatPostedDate(tx.postedDate)
    }

    /// Currency-formatted amount with U+2212 on negatives, via
    /// `MoneyFormatter`.
    static func formattedAmount(for tx: Transaction, currencyCode: String) -> String {
        return MoneyFormatter.format(tx.amount, currencyCode: currencyCode)
    }
}
