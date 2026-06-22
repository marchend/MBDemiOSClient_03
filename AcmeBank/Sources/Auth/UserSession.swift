import Foundation

/// Authenticated user value type passed forward through coordinators
/// after a successful Okta sign-in.
///
/// Six fields, intentionally: the four ID-token claims that identify the
/// user (`userId` = `sub`, `displayName` = `name`, `email`, `authTimestamp`
/// = `auth_time`), the bearer access token used for BFF calls, and a
/// device label for the "active sessions" UI shown later.
///
/// `UserSession` deliberately does NOT carry the refresh token. The
/// refresh token is a long-lived secret persisted to the
/// data-protection Keychain by `KeychainStore`; it must never travel
/// through view models, coordinators, or notification user-info dicts.
struct UserSession: Codable, Equatable {
    /// `sub` claim from the ID token.
    let userId: String
    /// `name` claim from the ID token.
    let displayName: String
    /// `email` claim from the ID token.
    let email: String
    /// Bearer access token issued by Okta.
    let accessToken: String
    /// `auth_time` claim from the ID token (UTC moment auth happened).
    let authTimestamp: Date
    /// `UIDevice.current.name` snapshot at sign-in time.
    let deviceName: String
}
