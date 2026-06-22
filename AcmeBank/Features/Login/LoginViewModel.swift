import Foundation

final class LoginViewModel: ObservableObject {
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var errorMessage: String? = nil

    var isSignInEnabled: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty   // don't trim password — spaces can be intentional
    }

    /// Closure invoked when Sign In is tapped.
    /// The caller injects real auth logic; defaults to a no-op.
    var onSignIn: (String, String) -> Void = { _, _ in }

    /// Forwards credentials to `onSignIn` and then clears the password field
    /// so the cleartext value does not linger in memory after the call.
    func signIn() {
        let u = username, p = password
        onSignIn(u, p)
        // Clear regardless of outcome; the auth layer owns the token.
        password = ""
    }
}
