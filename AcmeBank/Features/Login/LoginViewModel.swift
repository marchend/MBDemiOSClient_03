import Foundation

final class LoginViewModel: ObservableObject {
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var errorMessage: String? = nil

    var isSignInEnabled: Bool {
        !username.isEmpty && !password.isEmpty
    }

    /// Closure invoked when Sign In is tapped.
    /// The caller injects real auth logic; defaults to a no-op.
    var onSignIn: (String, String) -> Void = { _, _ in }
}
