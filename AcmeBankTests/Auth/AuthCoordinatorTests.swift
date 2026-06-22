import XCTest
@testable import AcmeBank

/// Mock `DirectAuthenticating` that returns a canned `AuthResult` so
/// we can exercise `AuthCoordinator`'s persistence + short-circuit
/// branches without touching the real Okta SDK.
private final class MockAuthService: DirectAuthenticating {
    var result: AuthResult
    private(set) var callCount = 0

    init(result: AuthResult) { self.result = result }

    func signIn(username: String, password: String) async -> AuthResult {
        callCount += 1
        return result
    }
}

/// Helper: build a UserSession populated with deterministic values for
/// assertion-friendly tests.
private func makeSession(accessToken: String = "access-123") -> UserSession {
    return UserSession(
        userId: "00u-jane",
        displayName: "Jane Doe",
        email: "jane@example.com",
        accessToken: accessToken,
        authTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
        deviceName: "Test iPhone"
    )
}

final class AuthCoordinatorTests: XCTestCase {

    /// In-memory keychain conforming to `KeychainStoring`.
    ///
    /// We deliberately do NOT use a real `KeychainStore` here: the CI
    /// simulator runs `CODE_SIGNING_ALLOWED=NO`, which means
    /// `AcmeBank.entitlements` is not embedded and every SecItem call
    /// returns -34018 (`errSecMissingEntitlement`). The
    /// `kSecUseDataProtectionKeychain: true` flag does NOT bypass the
    /// entitlement check — it only chooses between legacy and modern
    /// keychains. Injecting `InMemoryKeychainStore` lets us assert on
    /// `loadRefreshToken()` directly without hitting the simulator's
    /// keychain.
    private var keychain: InMemoryKeychainStore!

    override func setUp() {
        super.setUp()
        keychain = InMemoryKeychainStore()
        try? keychain.clear()
    }

    override func tearDown() {
        try? keychain.clear()
        keychain = nil
        super.tearDown()
    }

    // MARK: - notConfigured short-circuit

    func testNotConfiguredShortCircuitsBeforeCallingService() async {
        let service = MockAuthService(result: .success(makeSession(), refreshToken: "r"))
        let coordinator = AuthCoordinator(
            service: service,
            keychain: keychain,
            configLoader: { .notConfigured(reason: "Missing OKTA_ISSUER") }
        )

        let result = await coordinator.signIn(username: "u", password: "p", keepSignedIn: true)

        guard case let .notConfigured(reason) = result else {
            return XCTFail("Expected .notConfigured, got \(result)")
        }
        XCTAssertEqual(reason, "Missing OKTA_ISSUER")
        XCTAssertEqual(service.callCount, 0,
                       "Service must NOT be called when config is missing — secrets aren't loaded")
        XCTAssertNil(try? keychain.loadRefreshToken(),
                     "No tokens should be persisted on the notConfigured path")
    }

    // MARK: - success + keepSignedIn=true persists refresh token

    func testSuccessWithKeepSignedInPersistsRefreshToken() async throws {
        let service = MockAuthService(result: .success(makeSession(), refreshToken: "the-refresh-token"))
        let coordinator = makeCoordinator(service: service)

        let result = await coordinator.signIn(username: "u", password: "p", keepSignedIn: true)

        if case .success = result {} else {
            XCTFail("Expected .success, got \(result)")
        }
        XCTAssertEqual(try keychain.loadRefreshToken(), "the-refresh-token",
                       "keepSignedIn=true must persist the refresh token")
    }

    // MARK: - success + keepSignedIn=false does NOT persist refresh token

    func testSuccessWithoutKeepSignedInDoesNotPersistRefreshToken() async throws {
        let service = MockAuthService(result: .success(makeSession(), refreshToken: "should-not-be-saved"))
        let coordinator = makeCoordinator(service: service)

        _ = await coordinator.signIn(username: "u", password: "p", keepSignedIn: false)

        XCTAssertNil(try keychain.loadRefreshToken(),
                     "keepSignedIn=false must NOT persist the refresh token, even if the IdP returned one")
    }

    // MARK: - success + keepSignedIn=false clears prior refresh token

    func testSuccessWithoutKeepSignedInClearsAnyPriorRefreshToken() async throws {
        // Seed a prior refresh token as if a previous "keep me signed in"
        // session had been recorded.
        try keychain.storeTokens(accessToken: "old-access", refreshToken: "stale-refresh")
        XCTAssertEqual(try keychain.loadRefreshToken(), "stale-refresh")

        let service = MockAuthService(result: .success(makeSession(), refreshToken: "new-refresh"))
        let coordinator = makeCoordinator(service: service)

        _ = await coordinator.signIn(username: "u", password: "p", keepSignedIn: false)

        XCTAssertNil(try keychain.loadRefreshToken(),
                     "A new sign-in with keepSignedIn=false must wipe any previously-stored refresh token")
    }

    // MARK: - invalidCredentials passes through, persists nothing

    func testInvalidCredentialsPassesThroughAndPersistsNothing() async throws {
        let service = MockAuthService(result: .invalidCredentials)
        let coordinator = makeCoordinator(service: service)

        let result = await coordinator.signIn(username: "u", password: "wrong", keepSignedIn: true)

        XCTAssertEqual(result, .invalidCredentials)
        XCTAssertNil(try keychain.loadRefreshToken())
    }

    // MARK: - networkError passes through, persists nothing

    func testNetworkErrorPassesThroughAndPersistsNothing() async throws {
        let service = MockAuthService(result: .networkError)
        let coordinator = makeCoordinator(service: service)

        let result = await coordinator.signIn(username: "u", password: "p", keepSignedIn: true)

        XCTAssertEqual(result, .networkError)
        XCTAssertNil(try keychain.loadRefreshToken())
    }

    // MARK: - mfaUnsupported passes through, persists nothing

    func testMFAUnsupportedPassesThroughAndPersistsNothing() async throws {
        let service = MockAuthService(result: .mfaUnsupported)
        let coordinator = makeCoordinator(service: service)

        let result = await coordinator.signIn(username: "u", password: "p", keepSignedIn: true)

        XCTAssertEqual(result, .mfaUnsupported)
        XCTAssertNil(try keychain.loadRefreshToken())
    }

    // MARK: - success with nil refresh token (IdP didn't return one)

    func testSuccessWithNilRefreshTokenPersistsNothingForRefresh() async throws {
        let service = MockAuthService(result: .success(makeSession(), refreshToken: nil))
        let coordinator = makeCoordinator(service: service)

        let result = await coordinator.signIn(username: "u", password: "p", keepSignedIn: true)

        if case .success = result {} else {
            XCTFail("Expected .success, got \(result)")
        }
        XCTAssertNil(try keychain.loadRefreshToken(),
                     "Nothing to persist when the IdP didn't issue a refresh token, even if keepSignedIn=true")
    }

    // MARK: - Helpers

    private func makeCoordinator(service: DirectAuthenticating) -> AuthCoordinator {
        return AuthCoordinator(
            service: service,
            keychain: keychain,
            // Always-configured stub so we exercise the post-config path.
            configLoader: {
                .configured(
                    issuer: URL(string: "https://example.okta.com/oauth2/default")!,
                    clientID: "test-client",
                    redirectURI: URL(string: "com.acmebank.mobile:/cb")!,
                    scopes: "openid profile offline_access"
                )
            }
        )
    }
}
