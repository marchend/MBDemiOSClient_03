import XCTest
@testable import AcmeBank

/// Spy `KeychainStoring` that records every `clear()` call so the
/// sign-out test can assert the Keychain was wiped exactly once.
///
/// We do NOT use a real `KeychainStore` here: the CI simulator runs
/// with `CODE_SIGNING_ALLOWED=NO`, which strips the
/// `application-identifier` entitlement and causes every `SecItem*`
/// call to return -34018 (errSecMissingEntitlement). Injecting a
/// `KeychainStoring` spy lets us assert on the coordinator's
/// orchestration directly.
private final class SpyKeychainStore: KeychainStoring {
    private(set) var clearCallCount = 0
    private(set) var storeCallCount = 0
    var clearError: Error?

    private var accessToken: String?
    private var refreshToken: String?

    func storeTokens(accessToken: String, refreshToken: String?) throws {
        storeCallCount += 1
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    func loadRefreshToken() throws -> String? {
        return refreshToken
    }

    func clear() throws {
        clearCallCount += 1
        if let error = clearError {
            throw error
        }
        accessToken = nil
        refreshToken = nil
    }
}

/// Spy `AuthCoordinating` that records its inputs and returns a
/// canned `AuthResult`. Lets `AppCoordinator.signIn` tests assert the
/// credentials (including `keepSignedIn`) are forwarded verbatim AND
/// that `session` flips on `.success`.
private final class SpyAuthCoordinator: AuthCoordinating {
    private(set) var signInCallCount = 0
    private(set) var capturedUsername: String?
    private(set) var capturedPassword: String?
    private(set) var capturedKeepSignedIn: Bool?
    var stubbedResult: AuthResult = .invalidCredentials

    func signIn(username: String, password: String, keepSignedIn: Bool) async -> AuthResult {
        signInCallCount += 1
        capturedUsername = username
        capturedPassword = password
        capturedKeepSignedIn = keepSignedIn
        return stubbedResult
    }
}

private func makeSession(name: String = "Jane Doe", email: String = "jane@example.com") -> UserSession {
    return UserSession(
        userId: "00u-jane",
        displayName: name,
        email: email,
        accessToken: "access-123",
        authTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
        deviceName: "Test iPhone"
    )
}

@MainActor
final class AppCoordinatorTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_sessionIsNil() {
        let coordinator = AppCoordinator(keychain: SpyKeychainStore())

        XCTAssertNil(coordinator.session,
                     "AppCoordinator must start logged out so the app launches into LoginView.")
    }

    // MARK: - handleSignIn

    func testHandleSignInSetsSession() {
        let coordinator = AppCoordinator(keychain: SpyKeychainStore())
        let session = makeSession()

        coordinator.handleSignIn(session)

        XCTAssertEqual(coordinator.session, session,
                       "handleSignIn must flip `session` to the provided value so the root view swaps to LandingView.")
    }

    func test_handleSignIn_overwritesExistingSession() {
        let coordinator = AppCoordinator(keychain: SpyKeychainStore())
        coordinator.handleSignIn(makeSession(name: "Old User", email: "old@example.com"))

        let newSession = makeSession(name: "New User", email: "new@example.com")
        coordinator.handleSignIn(newSession)

        XCTAssertEqual(coordinator.session, newSession,
                       "A second handleSignIn must overwrite, not append.")
    }

    // MARK: - signIn (AuthCoordinator delegation seam)

    func test_signIn_forwardsCredentialsAndKeepSignedInToAuthCoordinator() async {
        let auth = SpyAuthCoordinator()
        auth.stubbedResult = .invalidCredentials // doesn't matter for forwarding
        let coordinator = AppCoordinator(keychain: SpyKeychainStore(), auth: auth)

        _ = await coordinator.signIn(username: "alice@acmebank.com", password: "p@ss", keepSignedIn: true)

        XCTAssertEqual(auth.signInCallCount, 1)
        XCTAssertEqual(auth.capturedUsername, "alice@acmebank.com")
        XCTAssertEqual(auth.capturedPassword, "p@ss")
        XCTAssertEqual(auth.capturedKeepSignedIn, true,
                       "keepSignedIn MUST reach AuthCoordinator — that's the AC-mandated seam.")
    }

    func test_signIn_onSuccess_flipsSessionToReturnedUser() async {
        let auth = SpyAuthCoordinator()
        let session = makeSession()
        auth.stubbedResult = .success(session, refreshToken: "rt-xyz")
        let coordinator = AppCoordinator(keychain: SpyKeychainStore(), auth: auth)

        let result = await coordinator.signIn(username: "u", password: "p", keepSignedIn: false)

        XCTAssertEqual(result, .success(session, refreshToken: "rt-xyz"))
        XCTAssertEqual(coordinator.session, session,
                       "On .success, AppCoordinator must flip its session so the root view swaps to LandingView.")
    }

    func test_signIn_onFailure_leavesSessionNil() async {
        let auth = SpyAuthCoordinator()
        auth.stubbedResult = .invalidCredentials
        let coordinator = AppCoordinator(keychain: SpyKeychainStore(), auth: auth)

        let result = await coordinator.signIn(username: "u", password: "p", keepSignedIn: false)

        XCTAssertEqual(result, .invalidCredentials)
        XCTAssertNil(coordinator.session,
                     "On a non-success AuthResult, AppCoordinator must NOT flip session — the root stays on LoginView.")
    }

    func test_signIn_withNoAuthInjected_returnsNotConfigured() async {
        // Defensive case for tests/preview code that build an
        // AppCoordinator without standing up the full auth stack. The
        // production composition root always injects an auth coordinator.
        let coordinator = AppCoordinator(keychain: SpyKeychainStore(), auth: nil)

        let result = await coordinator.signIn(username: "u", password: "p", keepSignedIn: false)

        if case .notConfigured = result {
            // expected
        } else {
            XCTFail("Expected .notConfigured when no AuthCoordinator is injected, got \(result)")
        }
        XCTAssertNil(coordinator.session)
    }

    // MARK: - signOut

    func testSignOutClearsSessionAndKeychain() {
        let keychain = SpyKeychainStore()
        let coordinator = AppCoordinator(keychain: keychain)
        coordinator.handleSignIn(makeSession())
        XCTAssertNotNil(coordinator.session, "Pre-condition: session is set.")

        coordinator.signOut()

        XCTAssertNil(coordinator.session,
                     "signOut must reset `session` to nil so the app returns to LoginView.")
        XCTAssertEqual(keychain.clearCallCount, 1,
                       "signOut must call KeychainStoring.clear() exactly once to wipe the persisted refresh token.")
    }

    func test_signOut_clearsSessionEvenWhenKeychainClearThrows() {
        // Keychain failures are CACHE failures \u2014 they must NOT strand
        // the user on the Landing screen. The UI must still drop back
        // to LoginView.
        let keychain = SpyKeychainStore()
        keychain.clearError = NSError(domain: "KeychainTest", code: -1)
        let coordinator = AppCoordinator(keychain: keychain)
        coordinator.handleSignIn(makeSession())

        coordinator.signOut()

        XCTAssertNil(coordinator.session,
                     "signOut must clear `session` even if the keychain clear fails \u2014 otherwise the user is trapped.")
        XCTAssertEqual(keychain.clearCallCount, 1)
    }
}
