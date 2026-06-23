import SwiftUI

/// A single account tile inside `AccountsSection`.
///
/// Visual contract:
///   - Leading navy rounded-square icon tile carrying a single SF
///     Symbol (the same symbol for every account type - we keep the
///     monochrome contract by NOT picking different symbols per
///     `AccountType`).
///   - Primary label: `account.name`.
///   - Subtitle: `"<Title-cased Type> \u00b7 \u00b7\u00b7\u00b7\u00b7 <last 4>"`.
///   - Trailing balance, currency-formatted via `MoneyFormatter`. The
///     leading U+2212 minus sign on negative balances is emitted by
///     `MoneyFormatter` - we do NOT prepend one here.
///   - Trailing subtext: the currency code on positive balances; for
///     negative balances we replace it with
///     `"<available_balance> available"`.
///
/// The subtitle and trailing strings are exposed as static helpers so
/// `HomeViewModelRenderingTests` can assert on them without standing
/// up a SwiftUI host.
struct AccountRow: View {
    let account: Account

    var body: some View {
        HStack(spacing: 14) {
            // Icon tile - SAME symbol for every account type to keep
            // the screen monochrome and visually uniform.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BankPalette.navy)
                    .frame(width: 40, height: 40)
                Image(systemName: "creditcard")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(BankPalette.onNavy)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BankPalette.primaryText)

                Text(AccountRow.subtitle(for: account))
                    .font(.footnote)
                    .foregroundStyle(BankPalette.secondaryText)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(AccountRow.formattedBalance(for: account))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BankPalette.primaryText)

                Text(AccountRow.trailingSubtext(for: account))
                    .font(.footnote)
                    .foregroundStyle(BankPalette.secondaryText)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BankPalette.surface)
        )
    }

    // MARK: - Test-visible string builders

    /// `"<Title-cased Type> \u00b7 \u00b7\u00b7\u00b7\u00b7 <last 4>"`.
    ///
    /// `AccountType` raw values come over the wire UPPERCASE
    /// (`"CHEQUING"`); we render them title-cased (`"Chequing"`). The
    /// last-4 is taken as the trailing 4 characters of
    /// `maskedNumber`; if it's shorter we use the whole string rather
    /// than crashing on a slice.
    static func subtitle(for account: Account) -> String {
        let last4 = lastFour(of: account.maskedNumber)
        return "\(titleCased(account.type)) \u{00B7} \u{00B7}\u{00B7}\u{00B7}\u{00B7} \(last4)"
    }

    /// Title-case the account type's wire string. `.unknown` renders
    /// as "Account" rather than "Unknown" so a forward-compatible
    /// account from the server doesn't expose the literal string
    /// `"Unknown"` to the user.
    static func titleCased(_ type: AccountType) -> String {
        switch type {
        case .chequing:   return "Chequing"
        case .savings:    return "Savings"
        case .credit:     return "Credit"
        case .investment: return "Investment"
        case .unknown:    return "Account"
        }
    }

    /// Last four characters of the masked number, or the whole
    /// string if shorter.
    static func lastFour(of masked: String) -> String {
        guard masked.count >= 4 else { return masked }
        return String(masked.suffix(4))
    }

    /// Currency-formatted balance. `MoneyFormatter` handles the
    /// U+2212 minus on negatives.
    static func formattedBalance(for account: Account) -> String {
        return MoneyFormatter.format(account.balance, currencyCode: account.currencyCode)
    }

    /// Trailing subtext below the balance.
    ///   - Positive balance \(>= 0\): the ISO currency code, e.g. `"CAD"`.
    ///   - Negative balance: `"<available_balance> available"`,
    ///     formatted via `MoneyFormatter`. This is the AC's
    ///     "available-balance subtext on negatives only" rule.
    static func trailingSubtext(for account: Account) -> String {
        if account.balance < 0 {
            let avail = MoneyFormatter.format(account.availableBalance, currencyCode: account.currencyCode)
            return "\(avail) available"
        } else {
            return account.currencyCode
        }
    }
}
