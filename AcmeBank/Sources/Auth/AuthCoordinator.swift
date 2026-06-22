import Foundation

/// SDK-agnostic top-level auth seam used by the (future) login view
/// model. Orchestrates `OktaAuthService` + `KeychainStore` so the UI
/// can stay ignorant of both the IdP and the storage layer.
protocol AuthCoordinating {
    func signIn(username: String, password: String, keepSignedIn: Bool) async -> AuthResult
}

/// Concrete `AuthCoordinating`.
///
/// Responsibilities:
/// 1. Short-circuit to `.notConfigured` when `OktaConfig.load()` returns
///    `.notConfigured` \u2014 a missing `OKTA_*` env var must never reach
///    the SDK, where it would surface as an opaque network error.
/// 2. Delegate the actual sign-in to a `DirectAuthenticating` service.
/// 3. On `.success`, persist tokens to the data-protection Keychain.
///    The refresh token is persisted ONLY when the user ticked
///    "keep me signed in" \u2014 otherwise we clear any prior copy so a
///    later launch cannot silently resume the session.
/// 4. Keychain writes are treated as a CACHE. A failed write is logged
///    and swallowed; the user is still signed in for this session.
///    (See iOS lesson: keychain failures must not invalidate a
///    sign-in the IdP already accepted.)
final class AuthCoordinator: AuthCoordinating {
    private let service: DirectAuthenticating
    private let keychain: KeychainStoring
    private let configLoader: () -> OktaConfig

    /// Designated initializer. Tests inject a mock `service`, an
    /// in-memory `keychain` (via the `KeychainStoring` protocol), and a
    /// stub `configLoader`.
    init(
        service: DirectAuthenticating,
        keychain: KeychainStoring,
        configLoader: @escaping () -> OktaConfig = { OktaConfig.load() }
    ) {
        self.service = service
        self.keychain = keychain
        self.configLoader = configLoader
    }

    func signIn(username: String, password: String, keepSignedIn: Bool) async -> AuthResult {
        // 1. Gate on configuration. Surface the reason verbatim so a
        //    debug build can show it; a release build can choose to
        //    hide it behind a generic copy at the UI layer.
        if case let .notConfigured(reason) = configLoader() {
            return .notConfigured(reason)
        }

        // 2. Delegate to the service.
        let result = await service.signIn(username: username, password: password)

        // 3. On success, persist tokens. Failures are non-fatal.
        guard case let .success(session, refreshToken) = result else {
            return result
        }

        // We do NOT have the raw ID token here \u2014 `UserSession` carries
        // the decoded claims, not the JWT \u2014 so we only persist the
        // access token (used by every BFF call) and the refresh token
        // (long-lived resume material). The `KeychainStore.Account`
        // enum was trimmed to match: it no longer carries an `idToken`
        // slot. The ID token is regenerated on every refresh and not
        // worth caching for this app's needs; if a future PR needs the
        // raw JWT (e.g. for `id_token_hint`), it should re-introduce
        // the slot at the same time it threads the raw token here.
        do {
            try keychain.storeTokens(
                accessToken: session.accessToken,
                refreshToken: keepSignedIn ? refreshToken : nil
            )
        } catch {
            // Cache miss \u2014 user will need to re-login next launch, but
            // this session remains valid. Never collapse this into a
            // sign-in failure.
            #if DEBUG
            print("AuthCoordinator: keychain write failed: \(error)")
            #endif
        }

        return result
    }
}
