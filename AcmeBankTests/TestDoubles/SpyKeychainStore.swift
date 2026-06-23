import Foundation
@testable import AcmeBank

/// Shared spy `KeychainStoring` for tests that need to assert on the
/// orchestration of token writes / clears (call counts, error
/// injection) rather than just on the resulting stored value.
///
/// **Why this is shared and not per-file.** Two test files
/// (`AppCoordinatorTests` and `RootCoordinatorSignOutTests`) need the
/// same spy surface — record `clear()` / `storeTokens(...)` call
/// counts, inject a throw from `clear()`, and otherwise behave like a
/// tiny in-memory keychain. Keeping the spy in one place means a
/// future change to `KeychainStoring` (e.g. adding a
/// `loadAccessToken()` requirement) only has to be reflected once;
/// the previous arrangement of two `private` verbatim copies invited
/// silent drift where one copy would stop compiling while the other
/// continued to.
///
/// **Why we do NOT use a real `KeychainStore` here.** The CI
/// simulator runs with `CODE_SIGNING_ALLOWED=NO`, which strips the
/// `application-identifier` entitlement and causes every `SecItem*`
/// call to return -34018 (`errSecMissingEntitlement`). Injecting a
/// `KeychainStoring` spy lets us assert on the coordinator's
/// orchestration directly without depending on the real keychain.
///
/// See also `InMemoryKeychainStore` in the `Auth/` test folder for
/// the simpler value-recording variant used by `AuthCoordinatorTests`
/// — that one does not record call counts because those tests
/// exercise persistence branches by asserting on `loadRefreshToken()`
/// directly.
final class SpyKeychainStore: KeychainStoring {
    private(set) var clearCallCount = 0
    private(set) var storeCallCount = 0

    /// When non-nil, `clear()` throws this error instead of resetting
    /// state. Lets tests pin the policy "a keychain clear failure
    /// must NOT strand the user on the post-login UI" by asserting
    /// the coordinator still drops the in-memory session.
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
