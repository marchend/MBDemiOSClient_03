import Foundation

final class LoginViewModel: ObservableObject {
    @Published var username: String = ""
    @Published var password: String = ""
    /// Mirrors the "Keep me signed in" toggle in `LoginView`. Threaded
    /// down to `AuthCoordinator.signIn(username:password:keepSignedIn:)`
    /// where it gates persistence of the refresh token. Defaults to
    /// `false` so a fresh launch never opts into long-lived persistence
    /// by accident.
    @Published var keepSignedIn: Bool = false
    @Published var errorMessage: String? = nil

    var isSignInEnabled: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty   // don't trim password — spaces can be intentional
    }

    /// Closure invoked when Sign In is tapped.
    ///
    /// The three-arg signature is required by the ticket's acceptance
    /// criteria: `keepSignedIn` must reach
    /// `AuthCoordinator.signIn(username:password:keepSignedIn:)` so the
    /// refresh-token persistence branch is reachable from the UI. Truncating
    /// to `(String, String) -> Void` would silently always pass `false`.
    ///
    /// The caller injects real auth logic; defaults to a no-op.
    var onSignIn: (String, String, Bool) -> Void = { _, _, _ in }

    /// Forwards credentials to `onSignIn` and then clears the password field
    /// so the cleartext value does not linger in memory after the call.
    func signIn() {
        let u = username, p = password, k = keepSignedIn
        onSignIn(u, p, k)
        // Clear regardless of outcome; the auth layer owns the token.
        password = ""
    }
}
