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
/// instance is the live `KeychainStore`; tests inject an in-memory
/// `KeychainStoring` spy and assert `clear()` was called.
@MainActor
final class AppCoordinator: ObservableObject {

    /// `nil` means "no authenticated session yet \u2014 show LoginView".
    /// A non-nil value means "user is signed in \u2014 show LandingView".
    @Published var session: UserSession?

    private let keychain: KeychainStoring

    /// Designated initializer. Production callers use the default
    /// `KeychainStore`. Tests inject an in-memory conformer.
    init(keychain: KeychainStoring = KeychainStore()) {
        self.keychain = keychain
        self.session = nil
    }

    /// Promote the app from \"logged out\" to \"logged in\". Called by
    /// `LoginView`'s success closure (wired in a later PR). Flipping
    /// `session` to a non-nil value causes SwiftUI to swap `LoginView`
    /// for `LandingView` at the composition root.
    func handleSignIn(_ session: UserSession) {
        self.session = session
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
