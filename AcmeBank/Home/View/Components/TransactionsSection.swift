import SwiftUI

/// Section header + the recent-transactions list. Renders an inline
/// empty-state message when the BFF returns an empty list (e.g. a
/// brand-new account with no posted transactions).
///
/// `currencyCode` is the currency code of the FIRST account on the
/// dashboard - the BFF doesn't yet emit per-transaction currency, so
/// we render transactions in the same currency as the user's primary
/// account.
struct TransactionsSection: View {
    let transactions: [Transaction]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent transactions")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BankPalette.secondaryText)
                .padding(.horizontal, 20)

            if transactions.isEmpty {
                Text("No recent transactions yet.")
                    .font(.subheadline)
                    .foregroundStyle(BankPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(BankPalette.surface)
                    )
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(transactions, id: \.id) { tx in
                        TransactionRow(transaction: tx, currencyCode: currencyCode)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}
