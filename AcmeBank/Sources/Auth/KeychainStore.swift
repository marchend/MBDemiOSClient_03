import Foundation
import Security

/// Abstraction over the secure token storage used by `AuthCoordinator`.
///
/// **Why a protocol.** On the CI simulator with `CODE_SIGNING_ALLOWED=NO`
/// the `AcmeBank.entitlements` file is not embedded in the binary
/// (there is no code-signing pass to apply it). Without an
/// `application-identifier` entitlement, every `SecItemAdd` /
/// `SecItemCopyMatching` / `SecItemDelete` call returns
/// `errSecMissingEntitlement` (-34018) — EVEN with
/// `kSecUseDataProtectionKeychain: true` set on the query (that flag
/// only chooses between the legacy file-based and modern data-
/// protection keychains; it does NOT bypass the entitlement check).
///
/// Production code uses the concrete `KeychainStore`. Tests that need
/// to exercise `AuthCoordinator`'s persistence branches inject an
/// `InMemoryKeychainStore` (in the test target) so they don't depend on
/// SecItem being callable on the simulator.
protocol KeychainStoring: AnyObject {
    func storeTokens(accessToken: String, refreshToken: String?) throws
    func loadRefreshToken() throws -> String?
    func clear() throws
}

/// Persists Okta token material to the data-protection Keychain.
///
/// **Why data-protection keychain.** On a `CODE_SIGNING_ALLOWED=NO`
/// simulator (CI's configuration) the legacy file-based keychain is
/// unavailable and any `SecItem*` call without
/// `kSecUseDataProtectionKeychain: true` returns `errSecMissingEntitlement`
/// (-34018). Every query dictionary we construct sets that flag.
///
/// **Per-token accounts.** A single service (`com.acmebank.auth`) holds
/// up to two accounts: `accessToken`, `refreshToken`. We use
/// `SecItemUpdate` semantics by deleting + adding so a re-sign-in
/// always overwrites stale material cleanly.
///
/// **Why no `idToken` slot.** `AuthCoordinator` only ever sees the
/// already-decoded `UserSession` claims, not the raw ID-token JWT, so
/// it has nothing meaningful to persist under an `idToken` account.
/// Carrying an empty `idToken` slot just to keep the symmetry would
/// leave a dead Keychain item that future `loadIdToken()` callers or
/// `Account.allCases` iterations would have to special-case as
/// "always empty". Cleaner to remove the slot now \u2014 if a future
/// PR genuinely needs the raw ID token (e.g. for `id_token_hint` on
/// logout), it can re-add the account at the same time the raw token
/// becomes available at the call site.
///
/// Tests inject a unique service name via the initializer so a parallel
/// test run never collides on the shared default service.
final class KeychainStore: KeychainStoring {
    /// `kSecAttrAccount` values stored under the shared service.
    enum Account: String, CaseIterable {
        case accessToken
        case refreshToken
    }

    /// Errors surfaced by failed `SecItem*` operations. The auth layer
    /// treats these as cache failures (re-login next launch) \u2014 NEVER
    /// as a reason to fail a sign-in that the IdP already accepted.
    enum KeychainError: Error, Equatable {
        case unhandled(OSStatus)
        case dataEncodingFailed
    }

    /// Service identifier (`kSecAttrService`). Default is the
    /// production value used by the live `AuthCoordinator`. Tests pass
    /// a per-test UUID-suffixed string so they don't collide.
    private let service: String

    init(service: String = "com.acmebank.auth") {
        self.service = service
    }

    // MARK: - Public API

    /// Persist the access token and (optionally) the refresh token.
    /// `refreshToken` is nil when the user did NOT tick "keep me
    /// signed in" \u2014 in that case any previously stored refresh
    /// token is also deleted so we cannot accidentally resume the
    /// session from stale state.
    func storeTokens(accessToken: String, refreshToken: String?) throws {
        try save(accessToken, for: .accessToken)
        if let refreshToken = refreshToken {
            try save(refreshToken, for: .refreshToken)
        } else {
            // Best-effort delete; a missing item is not an error.
            try? delete(.refreshToken)
        }
    }

    /// Read the persisted refresh token, or `nil` if none is stored.
    /// Used by silent-resume on app launch.
    func loadRefreshToken() throws -> String? {
        return try load(.refreshToken)
    }

    /// Remove every keychain item under this service. Called on sign-out
    /// and on a hard refresh failure.
    func clear() throws {
        for account in Account.allCases {
            try? delete(account)
        }
    }

    // MARK: - Internal building blocks

    /// Build the base query dictionary used by every operation. Always
    /// includes `kSecUseDataProtectionKeychain: true` \u2014 see file header.
    func baseQuery(for account: Account) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func save(_ value: String, for account: Account) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataEncodingFailed
        }
        // Delete any existing item so SecItemAdd never collides with a
        // previous sign-in's value. Ignore the "not found" status.
        try? delete(account)

        var query = baseQuery(for: account)
        query[kSecValueData as String] = data
        // Available after first unlock; matches the rest of the app's
        // background-friendly assumptions and works on the simulator.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    private func load(_ account: Account) throws -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                return nil
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status)
        }
    }

    private func delete(_ account: Account) throws {
        let query = baseQuery(for: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}
