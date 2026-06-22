import Foundation
import SwiftUI

/// Single source of truth for top-level auth state.
///
/// `AppCoordinator` owns one piece of state: whether there is an
/// authenticated `UserSession`. The SwiftUI entry point (`AcmeBankApp`)
/// observes it via `@StateObject` and renders `LoginView` when
/// `session == nil`, otherwise `LandingView(session:)`.
///
/// We deliberately do NOT route auth state through `UserDefaults`,
/// `NotificationCenter`, or a singleton. A `@Published var session`
/// observed at the composition root is enough for the entire app to
/// react to sign-in / sign-out, and it leaves the coordinator trivially
/// unit-testable: instantiate it, call `handleSignIn` / `signOut`,
/// assert on `session`.
///
/// **`@MainActor`.** `session` drives SwiftUI state, so every mutation
/// must land on the main actor. Marking the whole class
/// `@MainActor` makes that guarantee structural rather than something
/// every caller has to remember.
///
/// **Keychain injection.** `signOut` must clear the persisted refresh
/// token so a later launch cannot silently resume. The production
/// instance is the live `KeychainStore` constructed once at the
/// composition root and shared with `AcmeBankApp`'s silent-refresh
/// probe so the whole process operates on a single `KeychainStoring`
/// reference (no two-stores-fighting-over-the-same-account footgun).
/// Tests inject an in-memory `KeychainStoring` spy and assert
/// `clear()` was called.
///
/// **AuthCoordinator injection (the sign-in seam).** The login flow is
/// owned by `AuthCoordinator` (it talks to Okta, gates `keepSignedIn`,
/// and writes tokens to Keychain). `AppCoordinator` owns the
/// navigation-state flip. The two are connected here by holding an
/// `AuthCoordinating` reference: `signIn(username:password:keepSignedIn:)`
/// delegates the credential exchange to `auth` and, on `.success`,
/// flips `session` so the root view swaps to `LandingView`. This is the
/// explicit injection seam that the next PR's `LoginView` wiring will
/// use — no token-persistence logic is duplicated here.
@MainActor
final class AppCoordinator: ObservableObject {

    /// `nil` means "no authenticated session yet — show LoginView".
    /// A non-nil value means "user is signed in — show LandingView".
    @Published var session: UserSession?

    private let keychain: KeychainStoring
    private let auth: AuthCoordinating?

    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - keychain: The shared Keychain reference. Production callers
    ///     pass the same `KeychainStore` instance that `AcmeBankApp`
    ///     uses for the silent-refresh probe, so the entire process
    ///     operates on a single store.
    ///   - auth: The `AuthCoordinating` that owns the Okta exchange
    ///     and token persistence. Optional only so existing call sites
    ///     (and the unit tests that exercise `handleSignIn` / `signOut`
    ///     in isolation) can construct an `AppCoordinator` without
    ///     standing up the full Auth stack. The next PR's `LoginView`
    ///     wiring will always pass a real `AuthCoordinator`.
    init(
        keychain: KeychainStoring = KeychainStore(),
        auth: AuthCoordinating? = nil
    ) {
        self.keychain = keychain
        self.auth = auth
        self.session = nil
    }

    /// Promote the app from "logged out" to "logged in". Called by
    /// `LoginView`'s success closure (wired in a later PR). Flipping
    /// `session` to a non-nil value causes SwiftUI to swap `LoginView`
    /// for `LandingView` at the composition root.
    func handleSignIn(_ session: UserSession) {
        self.session = session
    }

    /// End-to-end sign-in: delegate to `AuthCoordinator` for the
    /// credential exchange + token persistence, and on `.success`
    /// flip `session` to swap the root view to `LandingView`.
    ///
    /// This is the seam the next PR's `LoginView` closure will call:
    /// `LoginView(onSignIn: { u, p, k in Task { await coordinator.signIn(username: u, password: p, keepSignedIn: k) } })`.
    /// Keeping the orchestration here (and not inside `LoginView`)
    /// means the navigation flip and the auth call cannot drift out of
    /// sync.
    ///
    /// - Returns: The underlying `AuthResult`, so the caller (UI layer)
    ///   can surface error copy. `.notConfigured` and `.failure` leave
    ///   `session == nil` so the root view stays on `LoginView`.
    @discardableResult
    func signIn(username: String, password: String, keepSignedIn: Bool) async -> AuthResult {
        guard let auth = auth else {
            // No auth coordinator was injected — this code path is only
            // reachable in tests that exercise `handleSignIn` / `signOut`
            // in isolation. Surfacing `.notConfigured` makes the misuse
            // loud rather than silently doing nothing.
            return .notConfigured("AppCoordinator has no AuthCoordinator injected")
        }

        let result = await auth.signIn(
            username: username,
            password: password,
            keepSignedIn: keepSignedIn
        )

        if case let .success(session, _) = result {
            handleSignIn(session)
        }

        return result
    }

    /// Revert to the logged-out state and best-effort-clear the
    /// Keychain so a later launch cannot resume the session.
    ///
    /// Keychain failure is treated as a CACHE issue (see
    /// `AuthCoordinator` for the same policy): we still drop the
    /// in-memory `session` so the UI returns to `LoginView`. Without
    /// this, a Keychain error would strand the user on the Landing
    /// screen with no way back to login.
    func signOut() {
        do {
            try keychain.clear()
        } catch {
            #if DEBUG
            print("AppCoordinator: keychain clear failed: \(error)")
            #endif
        }
        self.session = nil
    }
}
