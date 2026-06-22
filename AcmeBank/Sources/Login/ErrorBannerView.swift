import SwiftUI

/// Inline error banner shown below the password field in `LoginView`.
///
/// Visibility rule: renders nothing when `message` is `nil` or empty;
/// otherwise renders a light-red row with an `exclamationmark.triangle.fill`
/// SF Symbol and the supplied copy.
///
/// **Why a "blank" message stays hidden.** Some upstream callers may
/// momentarily set `errorMessage = ""` while clearing state. Treating
/// an empty string the same as `nil` keeps the banner from briefly
/// flashing an empty pink row in that window.
///
/// **Colour choice.** `Color.red.opacity(0.12)` is the spec'd
/// background; the foreground uses the dark red (`Color.red` with no
/// opacity for the icon, and `Color(.label)` for the text) so the copy
/// stays readable against the tinted background in both light and dark
/// mode. The icon's full-saturation red plus the bold "warning"
/// triangle glyph carries the urgency without relying on colour alone
/// (the `exclamationmark` shape is still meaningful in monochrome /
/// high-contrast modes).
struct ErrorBannerView: View {
    let message: String?

    var body: some View {
        if let text = message, !text.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.red)
                    .accessibilityHidden(true)

                Text(text)
                    .font(.footnote)
                    // Use the dynamic label colour rather than a fixed
                    // black/white so the copy stays high-contrast on
                    // the tinted background in both light and dark
                    // mode. WCAG AA contrast verified against the
                    // 12%-opacity-red surface on `.systemBackground`.
                    .foregroundStyle(Color(.label))
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.red.opacity(0.12))
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("errorBanner")
            .accessibilityLabel(Text(text))
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ErrorBannerView(message: nil)
        ErrorBannerView(message: "Incorrect username or password. Please try again.")
        ErrorBannerView(message: "Couldn't reach Okta — check your connection and try again.")
    }
    .padding()
}
