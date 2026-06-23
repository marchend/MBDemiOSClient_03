import Foundation

/// Conformance of the root coordinator (`AppCoordinator`) to
/// `SessionCoordinating`.
///
/// **Why an extension and not direct conformance on the type.** This
/// keeps the session-routing seam in one file alongside the protocol
/// it implements, so a future audit of "what happens when the user
/// signs out / the BFF returns 401" only has to read
/// `AcmeBank/Session/`. The base `AppCoordinator` stays focused on
/// owning `@Published var session`; this file wires that piece of
/// state to the two protocol entry points.
///
/// **Shared routing path.** Both `handleSessionExpired()` (involuntary
/// — 401 from the BFF) and `signOut()` (voluntary — user tapped the
/// button) MUST converge on the same underlying code. We achieve that
/// by funnelling both through the existing `AppCoordinator.signOut()`
/// instance method, which:
///   1. clears the persisted Okta credential / access token via
///      `KeychainStoring.clear()` (the injected `keychain`); and
///   2. flips `@Published var session` to `nil`, which causes
///      `AcmeBankApp`'s root view to swap back to `LoginView`.
///
/// Keeping the two protocol methods as one-line forwards makes it
/// impossible for them to drift apart over time (e.g. a future change
/// remembering to clear an extra cache on sign-out but forgetting to
/// do the same on session-expired). They are deliberately separate
/// PROTOCOL entry points so view models / analytics can distinguish
/// the user-intent, while the EFFECT is identical.
extension AppCoordinator: SessionCoordinating {

    /// Involuntary path: the BFF returned 401. Same effect as
    /// `signOut()` — clear the stored Okta credential and route the
    /// root view back to `LoginView` — kept as a separate protocol
    /// method so analytics / a future toast can distinguish it from
    /// the user-initiated case.
    func handleSessionExpired() {
        performSignOutEffect()
    }

    // Note: the existing `signOut()` instance method on
    // `AppCoordinator` already does keychain.clear() + session = nil,
    // which is exactly the `SessionCoordinating.signOut()` contract.
    // Adding `: SessionCoordinating` to the type therefore satisfies
    // the `signOut()` requirement automatically — no separate
    // override needed. The `handleSessionExpired()` shim above simply
    // routes through the same code so the two paths cannot drift
    // apart.

    /// Internal helper kept private to this file: the single piece of
    /// routing logic that both protocol entry points funnel through.
    /// Today it is a one-line delegate to the **concrete**
    /// `AppCoordinator.signOut()` instance method (NOT a recursive
    /// call into the `SessionCoordinating.signOut()` protocol
    /// requirement — Swift dispatches the unqualified `signOut()` in
    /// this extension body to the concrete instance method on the
    /// type being extended). Extracting it gives a future PR a single
    /// place to hook additional sign-out side effects (e.g. clearing
    /// an in-memory dashboard cache) without having to touch both
    /// protocol methods.
    ///
    /// Named `performSignOutEffect()` rather than `signOutInternal()`
    /// so the name visibly distinguishes it from the protocol method
    /// it wraps and reads as "the shared effect both paths perform",
    /// not "another sign-out entry point".
    private func performSignOutEffect() {
        // Dispatches to the concrete `AppCoordinator.signOut()`
        // instance method defined on the base type — see doc comment
        // above for why this is not recursive.
        signOut()
    }
}
