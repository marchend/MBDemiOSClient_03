import SwiftUI

/// A reusable monochrome error banner.
/// Renders zero height when `message` is `nil`; shows a rounded-rectangle
/// banner with the error copy when non-nil.
struct ErrorBannerView: View {
    let message: String?

    var body: some View {
        if let text = message {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Color(.secondaryLabel))
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.systemGray6))
            )
            .accessibilityIdentifier("errorBanner")
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ErrorBannerView(message: nil)
        ErrorBannerView(message: "Incorrect username or password.")
    }
    .padding()
}
