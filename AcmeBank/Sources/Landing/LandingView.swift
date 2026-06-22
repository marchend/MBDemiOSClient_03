import SwiftUI

/// Post-sign-in landing screen.
///
/// Intentionally minimal for this PR: exactly two text rows sourced
/// from the injected `UserSession`. Future PRs replace this with the
/// real Home / Dashboard tree; the contract is that whatever lives here
/// reads from the `UserSession` passed in by `AppCoordinator`, never
/// from a hardcoded string or a global.
///
/// The two display strings are exposed as `static` helpers so that
/// `LandingViewTests` can assert on the produced copy without needing
/// ViewInspector or a snapshot framework in the test target.
struct LandingView: View {
    let session: UserSession

    init(session: UserSession) {
        self.session = session
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LandingView.greeting(for: session))
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Color(.label))
                .accessibilityIdentifier("landingGreeting")

            Text(LandingView.subhead(for: session))
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))
                .accessibilityIdentifier("landingEmail")
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
    }

    // MARK: - Test-visible string builders

    /// Greeting headline copy. Reads `session.displayName` so that
    /// asserting `greeting(for: a) != greeting(for: b)` for two
    /// sessions with different names proves the value is NOT hardcoded.
    static func greeting(for session: UserSession) -> String {
        return "Welcome, \(session.displayName)"
    }

    /// Subhead copy \u2014 the user's email, as-is.
    static func subhead(for session: UserSession) -> String {
        return session.email
    }
}
