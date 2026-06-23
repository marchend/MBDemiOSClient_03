import SwiftUI

/// Footer "Log out" button pinned at the bottom of `HomeView`.
///
/// Invokes the injected `SessionCoordinating.signOut()` - the
/// voluntary sign-out path. The 401 path (involuntary) goes through
/// `handleSessionExpired()` and never reaches this button.
///
/// The button is the ONLY interactive element the PR 4 XCUITest
/// queries with `accessibilityIdentifier("home.logout")`. That
/// identifier is applied at the `HomeView` composition site (on the
/// `Button` itself), NOT inside this view - applying it twice would
/// flatten the accessibility tree.
struct LogOutButton: View {
    /// Held as `unowned` only conceptually - we pass it as a
    /// non-owning reference via the protocol existential. The action
    /// closure is invoked synchronously on tap and never escapes.
    let coordinator: SessionCoordinating

    var body: some View {
        Button {
            coordinator.signOut()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16, weight: .regular))
                Text("Log out")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(BankPalette.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(BankPalette.primaryText.opacity(0.2), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(BankPalette.surface)
                    )
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
