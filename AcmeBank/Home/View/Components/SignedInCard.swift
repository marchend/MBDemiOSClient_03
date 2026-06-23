import SwiftUI

/// Navy card that shows the signed-in customer's identity:
///   - an initials avatar (`first + last`, uppercased),
///   - the customer's full name with an optional segment badge
///     (e.g. "PREMIER") trailing the name when `customer.segment`
///     is non-nil,
///   - the phone number when present,
///   - a `checkmark.shield` row with "Authenticated via Okta · Customer <id>".
///
/// The card is a fixed visual on the Home screen confirming **who**
/// the BFF response belongs to - it doubles as a visible audit trail
/// that the JWT-resolved customer matches the user the app thinks is
/// signed in.
struct SignedInCard: View {
    let customer: Customer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                // Initials avatar in navyAlt so it reads as a
                // distinct chip on the navy card without breaking the
                // monochrome contract.
                ZStack {
                    Circle()
                        .fill(BankPalette.navyAlt)
                    Text(initials)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(BankPalette.onNavy)
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(fullName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(BankPalette.onNavy)

                        Spacer()

                        if let segment = customer.segment {
                            SegmentBadgeView(segment: segment)
                        }
                    }

                    if let phone = customer.phoneNumber, !phone.isEmpty {
                        Text(phone)
                            .font(.subheadline)
                            .foregroundStyle(BankPalette.onNavy.opacity(0.8))
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(BankPalette.onNavy)
                    .accessibilityHidden(true)

                Text("Authenticated via Okta \u{00B7} Customer \(customer.id)")
                    .font(.footnote)
                    .foregroundStyle(BankPalette.onNavy.opacity(0.85))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BankPalette.navy)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Derived strings

    /// `"<first> <last>"`.
    var fullName: String {
        return "\(customer.firstName) \(customer.lastName)"
    }

    /// First letter of `firstName` + first letter of `lastName`,
    /// uppercased. Defensive against empty strings - drops the
    /// missing piece rather than crashing on `.first!`.
    var initials: String {
        let f = customer.firstName.first.map { String($0) } ?? ""
        let l = customer.lastName.first.map { String($0) } ?? ""
        return (f + l).uppercased()
    }
}

// MARK: - Previews

#Preview("With PREMIER badge") {
    ZStack {
        BankPalette.background.ignoresSafeArea()
        SignedInCard(customer: HomeDashboardFixtures.previewDashboardWithSegment.customer)
            .padding(.vertical)
    }
}

#Preview("Without segment badge") {
    ZStack {
        BankPalette.background.ignoresSafeArea()
        SignedInCard(customer: HomeDashboardFixtures.previewDashboardNoSegment.customer)
            .padding(.vertical)
    }
}
