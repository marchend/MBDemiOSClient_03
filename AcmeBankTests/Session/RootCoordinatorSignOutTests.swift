import XCTest
@testable import AcmeBank

// `SpyKeychainStore` lives in `AcmeBankTests/TestDoubles/` so a
// single definition is shared with `AppCoordinatorTests`. See that
// file's doc comment for why we don't use a real `KeychainStore` on
// CI.

private func makeSession() -> UserSession {
    return UserSession(
        userId: "00u-jane",
        displayName: "Jane Doe",
        email: "jane@example.com",
        accessToken: "access-123",
        authTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
        deviceName: "Test iPhone"
    )
}

/// Verifies the `SessionCoordinating` conformance on the root
/// coordinator (`AppCoordinator`).
///
/// The two protocol entry points — `signOut()` (voluntary) and
/// `handleSessionExpired()` (involuntary, 401) — MUST converge on the
/// same underlying behaviour:
///   1. clear the stored Okta credential via `KeychainStoring.clear()`,
///   2. drop the in-memory `UserSession` (`session = nil`),
///   3. which routes the root view back to `LoginView`.
///
/// These tests pin that contract so a future refactor cannot make the
/// two paths drift apart.
@MainActor
final class RootCoordinatorSignOutTests: XCTestCase {

    // MARK: - Voluntary sign-out

    func test_signOut_clearsSessionAndOktaCredential_andRoutesToLogin() {
        let keychain = SpyKeychainStore()
        let coordinator: AppCoordinator = AppCoordinator(keychain: keychain)
        coordinator.handleSignIn(makeSession())
        XCTAssertNotNil(coordinator.session, "Pre-condition: session is set.")

        // Call through the protocol surface so we exercise the
        // conformance, not just the bare instance method.
        let sessionCoordinator: SessionCoordinating = coordinator
        sessionCoordinator.signOut()

        XCTAssertEqual(keychain.clearCallCount, 1,
                       "signOut() must call KeychainStoring.clear() exactly once to wipe the stored Okta credential.")
        XCTAssertNil(coordinator.session,
                     "signOut() must clear `session` so the root view routes back to LoginView.")
    }

    // MARK: - Involuntary session-expired (401)

    func test_handleSessionExpired_clearsSessionAndOktaCredential_andRoutesToLogin() {
        let keychain = SpyKeychainStore()
        let coordinator = AppCoordinator(keychain: keychain)
        coordinator.handleSignIn(makeSession())

        let sessionCoordinator: SessionCoordinating = coordinator
        sessionCoordinator.handleSessionExpired()

        XCTAssertEqual(keychain.clearCallCount, 1,
                       "handleSessionExpired() must wipe the stored Okta credential — the 401 means the server already invalidated it, but we must catch up on the client.")
        XCTAssertNil(coordinator.session,
                     "handleSessionExpired() must clear `session` so the root view routes back to LoginView.")
    }

    // MARK: - Both paths share the same routing code

    /// The voluntary (`signOut`) and involuntary
    /// (`handleSessionExpired`) paths MUST produce the same observable
    /// effect on the coordinator. The two are kept as separate
    /// protocol methods only so analytics / telemetry can distinguish
    /// the intent — they must not diverge in what they actually do.
    func test_handleSessionExpired_andSignOut_produceTheSameRoutingEffect() {
        // Path A: signOut()
        let keychainA = SpyKeychainStore()
        let coordinatorA = AppCoordinator(keychain: keychainA)
        coordinatorA.handleSignIn(makeSession())
        (coordinatorA as SessionCoordinating).signOut()

        // Path B: handleSessionExpired()
        let keychainB = SpyKeychainStore()
        let coordinatorB = AppCoordinator(keychain: keychainB)
        coordinatorB.handleSignIn(makeSession())
        (coordinatorB as SessionCoordinating).handleSessionExpired()

        XCTAssertEqual(keychainA.clearCallCount, keychainB.clearCallCount,
                       "Both paths must clear the keychain the same number of times.")
        XCTAssertEqual(coordinatorA.session, coordinatorB.session,
                       "Both paths must end with the same session state (nil).")
        XCTAssertNil(coordinatorA.session)
        XCTAssertNil(coordinatorB.session)
    }

    // MARK: - Keychain failure does not strand the user

    /// A keychain failure on the involuntary path must NOT strand the
    /// user on the post-login UI: the 401 already invalidated the
    /// session server-side, so we MUST drop back to Login even if the
    /// local credential wipe failed. Same policy as the voluntary
    /// `signOut()` path (see `AppCoordinatorTests`).
    func test_handleSessionExpired_keychainClearThrows_stillClearsSession() {
        let keychain = SpyKeychainStore()
        keychain.clearError = NSError(domain: "KeychainTest", code: -1)
        let coordinator = AppCoordinator(keychain: keychain)
        coordinator.handleSignIn(makeSession())

        (coordinator as SessionCoordinating).handleSessionExpired()

        XCTAssertEqual(keychain.clearCallCount, 1)
        XCTAssertNil(coordinator.session,
                     "Even when keychain clear throws, session MUST be nil so the user lands on LoginView. Otherwise a keychain glitch would trap them on the post-login UI with an invalid token.")
    }
}
