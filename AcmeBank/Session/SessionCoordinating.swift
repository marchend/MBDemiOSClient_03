import Foundation

/// Coordination seam between feature view models (Home today, every
/// authenticated feature later) and whatever owns the top-level
/// auth-state flip back to the Login screen.
///
/// The production conformer is `AppCoordinator` (see
/// `RootCoordinator+SignOut.swift`). Tests inject a spy that records
/// which method was called so they can assert, for example, that a
/// 401 from the BFF routes through `handleSessionExpired()` and NOT
/// through `signOut()`.
///
/// **Why two methods and not one.** Both methods ultimately land the
/// user back on `LoginView`, but they have different semantics that a
/// future audit / analytics / telemetry layer will want to
/// distinguish:
///
/// - `handleSessionExpired()` is the *involuntary* path. The BFF
///   rejected the bearer token with a 401, so the session is already
///   gone server-side; the client just has to catch up. A future PR
///   will hook a "your session has expired — please sign in again"
///   toast off this method.
/// - `signOut()` is the *voluntary* path. The user tapped the sign-out
///   button. Same destination (Login), but the analytics event and the
///   on-screen messaging differ.
///
/// Both methods MUST converge on the same underlying routing code so
/// the two paths cannot drift out of sync. See
/// `RootCoordinator+SignOut.swift` for the shared implementation.
@MainActor
protocol SessionCoordinating: AnyObject {
    /// Invoked by a feature view model when an authenticated BFF call
    /// returns 401. The coordinator MUST clear the in-memory
    /// `UserSession` and the stored Okta credential, then route the
    /// root view back to `LoginView`.
    ///
    /// View models calling this MUST NOT also publish stale or
    /// partially-loaded data into their own `@Published` state — the
    /// user is, as of right now, unauthenticated, and the next thing
    /// they see is the Login screen.
    func handleSessionExpired()

    /// Invoked by an explicit user gesture (the sign-out button in
    /// the post-login UI). Same destination as
    /// `handleSessionExpired()` — clears the in-memory session,
    /// deletes the stored Okta credential, routes back to Login —
    /// but represents a different intent at the analytics / telemetry
    /// layer.
    func signOut()
}
