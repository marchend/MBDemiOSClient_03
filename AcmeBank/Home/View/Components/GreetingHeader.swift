import SwiftUI

/// Two-line greeting: "Welcome back," on top of the customer's bold
/// first name. Reads `firstName` from the loaded `Customer` so the
/// label is provably non-hardcoded.
struct GreetingHeader: View {
    let firstName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Welcome back,")
                .font(.subheadline)
                .foregroundStyle(BankPalette.secondaryText)

            Text(firstName)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(BankPalette.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }
}
