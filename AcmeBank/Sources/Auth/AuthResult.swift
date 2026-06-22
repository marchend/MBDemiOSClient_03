import Foundation

/// Closed, exhaustive outcome of a single sign-in attempt.
///
/// This is the SDK-agnostic value the auth layer hands back to the
/// (future) login view model. No `Error` is thrown out of the auth
/// service: every failure mode is one of the cases below, so the UI
/// can switch on the result without a `do { ... } catch { ... }` and
/// without leaking SDK error types into the view layer.
enum AuthResult: Equatable {
    /// Sign-in succeeded. The `UserSession` carries the access token and
    /// the decoded ID-token claims. `refreshToken` is delivered
    /// separately so the coordinator can decide whether to persist it
    /// based on the user's "keep me signed in" choice \u2014 it must NEVER
    /// be stored inside `UserSession`.
    case success(UserSession, refreshToken: String?)
    /// Wrong username or password.
    case invalidCredentials
    /// Couldn't reach Okta (offline, DNS, timeout, TLS error).
    case networkError
    /// Okta returned an MFA challenge. This release of the app does not
    /// implement step-up MFA; the UI shows "MFA required \u2014 contact your
    /// administrator".
    case mfaUnsupported
    /// `OktaConfig.load()` was `.notConfigured` \u2014 the build was shipped
    /// without one or more `OKTA_*` env vars. The associated string is
    /// the human-readable reason from `OktaConfig`.
    case notConfigured(String)
}
