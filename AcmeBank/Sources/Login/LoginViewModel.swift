import Foundation

/// `LoginView`'s ObservableObject backing store.
///
/// Responsibilities:
/// - Owns the text-field bindings (`username`, `password`),
///   the "Keep me signed in" toggle (`keepSignedIn`), the inline
///   error copy (`errorMessage`), and the in-flight flag
///   (`isSigningIn`).
/// - Drives the sign-in attempt by delegating to an injected
///   `AuthCoordinating`. The View struct never touches `AuthCoordinator`
///   directly: it asks the ViewModel, which returns a `UserSession?` so
///   the View can hand the success path to `AppCoordinator.handleSignIn`.
///
/// **Why `signIn` returns `UserSession?` instead of mutating a published
/// `session`.** The navigation-state flip lives on `AppCoordinator` (PR
/// 3). Pushing a second `@Published var session` here would create two
/// sources of truth for "are we logged in?". Returning the optional
/// keeps the ViewModel about the FORM, and the View hands the result to
/// the coordinator.
///
/// **Concurrency.** The async sign-in worker is `@MainActor`-isolated
/// so every `@Published` write lands on the main actor. The whole class
/// is intentionally NOT `@MainActor` so SwiftUI default-arg initializers
/// like `LoginView(viewModel: LoginViewModel(...))` keep compiling under
/// Swift 5.10 strict concurrency.
final class LoginViewModel: ObservableObject {

    // MARK: - Form state

    @Published var username: String = ""
    @Published var password: String = ""

    /// Mirrors the "Keep me signed in" toggle in `LoginView`. Threaded
    /// down to `AuthCoordinator.signIn(username:password:keepSignedIn:)`
    /// where it gates persistence of the refresh token. Defaults to
    /// `false` so a fresh launch never opts into long-lived persistence
    /// by accident.
    @Published var keepSignedIn: Bool = false

    /// Non-nil while the inline error banner is showing. Cleared the
    /// moment the user edits either credential field (`onFieldEdit`).
    @Published var errorMessage: String? = nil

    /// True while a `signIn(...)` is in flight. Drives the Sign In
    /// button's spinner + disabled state and the text fields'
    /// disabled state.
    @Published var isSigningIn: Bool = false

    // MARK: - Dependencies

    private let auth: AuthCoordinating

    /// Designated initializer.
    ///
    /// - Parameter auth: The auth seam used by `signIn(...)`. Production
    ///   passes the shared `AuthCoordinator` built at the composition
    ///   root; tests inject a mock `AuthCoordinating` and drive the
    ///   `AuthResult` they want to exercise.
    init(auth: AuthCoordinating) {
        self.auth = auth
    }

    // MARK: - Derived state

    /// Sign In button is enabled when both fields are non-empty AND we
    /// are not currently signing in. Exposed so the View can bind
    /// `.disabled(!viewModel.isSignInEnabled)` rather than re-deriving
    /// the rule inline.
    var isSignInEnabled: Bool {
        !isSigningIn &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty   // don't trim password — spaces can be intentional
    }

    // MARK: - User actions

    /// Called from each `TextField.onChange` in `LoginView`. The moment
    /// the user edits either credential, dismiss the inline error so
    /// the banner does not linger over a freshly typed value.
    func onFieldEdit() {
        if errorMessage != nil {
            errorMessage = nil
        }
    }

    /// Attempt sign-in.
    ///
    /// Sets `isSigningIn = true` for the duration; delegates to the
    /// injected `AuthCoordinating`; maps the returned `AuthResult` to
    /// either a `UserSession` (success) or a published `errorMessage`
    /// (failure cases). On return — success OR failure —
    /// `isSigningIn` is reset to `false` so the spinner clears.
    ///
    /// - Returns: The decoded `UserSession` on `.success`, otherwise
    ///   `nil`. The View hands a non-nil return value to
    ///   `AppCoordinator.handleSignIn(_:)` which flips the root view
    ///   to `LandingView`.
    @MainActor
    @discardableResult
    func signIn(username: String, password: String, keepSignedIn: Bool) async -> UserSession? {
        isSigningIn = true
        // Clear any prior banner before the request goes out — leaving
        // a stale "Couldn't reach Okta" message visible while a new
        // attempt spins would be confusing.
        errorMessage = nil

        let result = await auth.signIn(
            username: username,
            password: password,
            keepSignedIn: keepSignedIn
        )

        // Always reset the in-flight flag, regardless of outcome.
        // `defer` would also work, but writing it explicitly keeps the
        // order obvious to a future reader: clear flag → map result.
        isSigningIn = false

        switch result {
        case let .success(session, _):
            return session
        case .invalidCredentials:
            errorMessage = "Incorrect username or password. Please try again."
            return nil
        case .networkError:
            errorMessage = "Couldn't reach Okta — check your connection and try again."
            return nil
        case .mfaUnsupported:
            errorMessage = "MFA is required but not supported in this build."
            return nil
        case .notConfigured:
            errorMessage = "Okta is not configured on this build — see README."
            return nil
        }
    }
}
