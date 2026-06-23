import SwiftUI

/// Section header + the per-account `AccountRow` list.
///
/// Accessibility identifiers:
///   - the container `VStack` carries `"home.accounts.list"` so
///     PR 4's XCUITest can locate the list. Per the SwiftUI
///     accessibility-tree rule, the per-row identifiers
///     (`"home.account.row.<index>"`) are applied to the ROW views,
///     NOT to a wrapping container with its own identifier - applying
///     an identifier to a container collapses its children's
///     accessibility elements and the rows would not be queryable.
struct AccountsSection: View {
    let accounts: [Account]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accounts")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BankPalette.secondaryText)
                .padding(.horizontal, 20)

            // The accounts list. We intentionally do NOT also tag the
            // individual rows' parent container - that would flatten
            // the accessibility tree and PR 4's XCUITest would not
            // find `home.account.row.<index>`.
            VStack(spacing: 10) {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    AccountRow(account: account)
                        .accessibilityIdentifier("home.account.row.\(index)")
                }
            }
            .padding(.horizontal, 20)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.accounts.list")
        }
    }
}
