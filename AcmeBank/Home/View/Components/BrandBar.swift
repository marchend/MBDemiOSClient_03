import SwiftUI

/// Top-of-screen brand bar: a navy hex "A" logo and the "Acme Bank"
/// wordmark.
///
/// Kept as its own view so the screenshot's brand row is reusable on
/// any future screen (a Settings header, a Splash, etc.) and so the
/// `HomeView` composition reads as a linear stack of named sections
/// rather than a single 400-line `body`.
struct BrandBar: View {
    var body: some View {
        HStack(spacing: 12) {
            // Hex tile with the "A" mark. A rotated square is the
            // simplest approximation of the screenshot's hex without
            // pulling in a custom Shape.
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BankPalette.navy)
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(45))
                    .frame(width: 32, height: 32)
                Text("A")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(BankPalette.onNavy)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            Text("Acme Bank")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(BankPalette.primaryText)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
