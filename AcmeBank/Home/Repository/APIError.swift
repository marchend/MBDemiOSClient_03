import Foundation

/// Typed error surface for repository calls. Callers (view models)
/// branch on these cases to drive UI: `.unauthorized` routes back to
/// Login (the session-expired path); `.server` / `.transport` /
/// `.decoding` all surface as the same inline error + Retry state, but
/// the underlying error is kept on the case so it can be logged.
///
/// Deliberately not `Equatable` — the associated `Error` payloads on
/// `.transport` / `.decoding` are not generally equatable, and tests
/// can pattern-match the case directly.
enum APIError: Error {
    /// HTTP 401. The Okta bearer token is missing, expired, or
    /// rejected by the BFF. Callers must clear the in-memory session
    /// and route to Login — they must NOT render stale or another
    /// user's data.
    case unauthorized

    /// Any non-2xx, non-401 HTTP response. The raw status code is kept
    /// for logging; the typical case is 5xx but a 4xx other than 401
    /// also lands here.
    case server(Int)

    /// `URLSession` failed before producing an `HTTPURLResponse`
    /// (DNS, TLS, offline, timeout). The underlying error is
    /// preserved for logging.
    case transport(Error)

    /// The HTTP call succeeded with a 2xx but the body did not match
    /// `HomeDashboard`'s shape. Indicates a client/server contract
    /// drift; the underlying `DecodingError` pinpoints the field.
    case decoding(Error)
}
