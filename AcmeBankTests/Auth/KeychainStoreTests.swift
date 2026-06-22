import XCTest
@testable import AcmeBank

/// Round-trip + flag-presence tests for `KeychainStore`.
///
/// Every test uses a UNIQUE service name (UUID-suffixed) so a parallel
/// or repeated run cannot collide on the shared `com.acmebank.auth`
/// service that the production code uses.
///
/// CI runs the simulator with `CODE_SIGNING_ALLOWED=NO`. Without
/// `kSecUseDataProtectionKeychain: true` on every query the SecItem
/// calls return -34018 (errSecMissingEntitlement) and these tests
/// would all fail \u2014 so the flag-presence assertion below is load-
/// bearing.
final class KeychainStoreTests: XCTestCase {

    private var serviceName: String!
    private var store: KeychainStore!

    override func setUp() {
        super.setUp()
        serviceName = "com.acmebank.auth.tests.\(UUID().uuidString)"
        store = KeychainStore(service: serviceName)
        // Defensive: ensure no leftovers from a previous test process.
        try? store.clear()
    }

    override func tearDown() {
        try? store.clear()
        store = nil
        serviceName = nil
        super.tearDown()
    }

    // MARK: - Flag presence

    func testEveryQueryIncludesDataProtectionFlag() {
        // The `baseQuery` building block is reused by every SecItem
        // call, so asserting on it covers add/copy/delete in one shot.
        for account in KeychainStore.Account.allCases {
            let query = store.baseQuery(for: account)
            guard let flag = query[kSecUseDataProtectionKeychain as String] as? Bool else {
                XCTFail("baseQuery for \(account) is missing kSecUseDataProtectionKeychain")
                continue
            }
            XCTAssertTrue(flag,
                          "kSecUseDataProtectionKeychain must be true on every keychain query \u2014 required for CI's CODE_SIGNING_ALLOWED=NO simulator")
        }
    }

    // MARK: - Account shape

    func testAccountEnumDoesNotCarryDeadIDTokenSlot() {
        // The architecture never persists the raw ID-token JWT, so the
        // enum was trimmed to two slots. Guard against a future regression
        // that re-introduces a dead `idToken` account.
        XCTAssertEqual(Set(KeychainStore.Account.allCases.map(\.rawValue)),
                       ["accessToken", "refreshToken"],
                       "KeychainStore.Account must contain only the slots the architecture actually reads")
    }

    // MARK: - Round-trip

    func testStoreLoadClearRoundTrip() throws {
        try store.storeTokens(
            accessToken: "access-1",
            refreshToken: "refresh-1"
        )
        XCTAssertEqual(try store.loadRefreshToken(), "refresh-1")

        try store.clear()
        XCTAssertNil(try store.loadRefreshToken(),
                     "clear() should remove the refresh token")
    }

    // MARK: - keepSignedIn=false removes prior refresh token

    func testStoreWithNilRefreshTokenClearsPreviousRefreshToken() throws {
        // First call seeds a refresh token.
        try store.storeTokens(accessToken: "a", refreshToken: "old-refresh")
        XCTAssertEqual(try store.loadRefreshToken(), "old-refresh")

        // Second call (keepSignedIn=false) must wipe it.
        try store.storeTokens(accessToken: "a", refreshToken: nil)
        XCTAssertNil(try store.loadRefreshToken(),
                     "storeTokens(refreshToken: nil) must delete a previously-saved refresh token")
    }

    // MARK: - overwrite semantics

    func testRepeatedStoreOverwritesExistingValues() throws {
        try store.storeTokens(accessToken: "a-1", refreshToken: "r-1")
        try store.storeTokens(accessToken: "a-2", refreshToken: "r-2")
        XCTAssertEqual(try store.loadRefreshToken(), "r-2",
                       "second storeTokens should overwrite the first")
    }
}
