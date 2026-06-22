import Foundation
@testable import AcmeBank

/// Test double for `KeychainStoring` that holds tokens in a plain
/// in-memory dictionary.
///
/// **Why this exists.** The CI simulator runs with
/// `CODE_SIGNING_ALLOWED=NO`, which means `AcmeBank.entitlements` is
/// NOT embedded in the binary (no code-signing pass to apply it).
/// Without an `application-identifier` entitlement, every `SecItemAdd` /
/// `SecItemCopyMatching` / `SecItemDelete` call returns
/// `errSecMissingEntitlement` (-34018) — even with
/// `kSecUseDataProtectionKeychain: true` set on the query. That flag
/// only selects between the legacy and modern keychains; it does NOT
/// bypass the entitlement check.
///
/// `AuthCoordinatorTests` exercises the persistence branches by
/// asserting on `loadRefreshToken()` directly, so it cannot tolerate
/// a real `KeychainStore` throwing -34018 on every call. Injecting
/// this in-memory conformer lets the coordinator tests run cleanly
/// on the unsigned simulator while still exercising the real
/// `AuthCoordinator` code paths.
final class InMemoryKeychainStore: KeychainStoring {
    private var accessToken: String?
    private var refreshToken: String?

    func storeTokens(accessToken: String, refreshToken: String?) throws {
        self.accessToken = accessToken
        // Mirrors `KeychainStore.storeTokens`: nil means "delete any
        // previously stored refresh token", not "leave it as-is".
        self.refreshToken = refreshToken
    }

    func loadRefreshToken() throws -> String? {
        return refreshToken
    }

    func clear() throws {
        accessToken = nil
        refreshToken = nil
    }
}
