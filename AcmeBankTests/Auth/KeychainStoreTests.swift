import XCTest
@testable import AcmeBank

/// Round-trip + flag-presence tests for `KeychainStore`.
///
/// Every test uses a UNIQUE service name (UUID-suffixed) so a parallel
/// or repeated run cannot collide on the shared `com.acmebank.auth`
/// service that the production code uses.
///
/// **CI keychain availability.** CI runs the simulator with
/// `CODE_SIGNING_ALLOWED=NO`, which means `AcmeBank.entitlements` is
/// not embedded in the binary (no code-signing pass to apply it).
/// Without an `application-identifier` entitlement, every `SecItem*`
/// call returns -34018 (`errSecMissingEntitlement`). The
/// `kSecUseDataProtectionKeychain: true` flag does NOT bypass that
/// check — it only chooses between the legacy file-based and modern
/// data-protection keychains.
///
/// On a developer Mac (signed app, real entitlements) the SecItem
/// calls succeed and these round-trip tests exercise the production
/// `KeychainStore` end to end. On CI they hit -34018 in `setUp`'s
/// probe and call `XCTSkip` — the behavior is covered there by
/// `AuthCoordinatorTests` against `InMemoryKeychainStore`, which
/// exercises the same persistence branches without depending on the
/// simulator's keychain.
///
/// The two non-SecItem tests (`testEveryQueryIncludesDataProtectionFlag`,
/// `testAccountEnumDoesNotCarryDeadIDTokenSlot`) do NOT touch the
/// keychain and run unconditionally.
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
                          "kSecUseDataProtectionKeychain must be true on every keychain query — required for CI's CODE_SIGNING_ALLOWED=NO simulator")
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
        try skipIfKeychainUnavailable()

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
        try skipIfKeychainUnavailable()

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
        try skipIfKeychainUnavailable()

        try store.storeTokens(accessToken: "a-1", refreshToken: "r-1")
        try store.storeTokens(accessToken: "a-2", refreshToken: "r-2")
        XCTAssertEqual(try store.loadRefreshToken(), "r-2",
                       "second storeTokens should overwrite the first")
    }

    // MARK: - Probe

    /// Attempts a throwaway `SecItemAdd` under a probe-specific account
    /// to detect the unsigned-simulator -34018 failure mode. If the
    /// keychain is unavailable, throw `XCTSkip` so the round-trip test
    /// is marked skipped (not failed) — its behavior is covered by
    /// `AuthCoordinatorTests` against `InMemoryKeychainStore`.
    ///
    /// We use a probe service name (separate from the test's own
    /// `serviceName`) so the probe never leaves residue in the
    /// per-test namespace, and clean it up immediately on success.
    private func skipIfKeychainUnavailable() throws {
        let probeService = "com.acmebank.auth.probe.\(UUID().uuidString)"
        let probeAccount = "probe"
        let probeValue = Data("probe".utf8)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: probeService,
            kSecAttrAccount as String: probeAccount,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: probeValue,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        if addStatus == errSecMissingEntitlement {
            throw XCTSkip("""
                Simulator keychain unavailable without code-signing \
                (SecItemAdd returned errSecMissingEntitlement / -34018). \
                Behavior is covered by InMemoryKeychainStore tests in \
                AuthCoordinatorTests.
                """)
        }

        // Best-effort cleanup of the probe item if the add succeeded.
        if addStatus == errSecSuccess {
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: probeService,
                kSecAttrAccount as String: probeAccount,
                kSecUseDataProtectionKeychain as String: true,
            ]
            _ = SecItemDelete(deleteQuery as CFDictionary)
        }

        // Any other status (e.g. duplicate item) is fine — we just want
        // to know whether the entitlement gate fires. Let the real
        // test exercise the failure path naturally if something else
        // is wrong.
    }
}
