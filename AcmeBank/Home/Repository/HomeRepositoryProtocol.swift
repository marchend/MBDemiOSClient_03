import Foundation

/// Repository seam between `HomeViewModel` and whatever actually
/// produces a `HomeDashboard` — `BFFHomeRepository` in the shipping
/// app, a fixture-backed stub in tests/previews.
///
/// `HomeViewModel` depends ONLY on this protocol so it stays
/// unit-testable without `URLSession` or a stub server. The production
/// composition root (the coordinator / root view) MUST inject the real
/// `BFFHomeRepository` — never a fixture repo on the happy path.
protocol HomeRepositoryProtocol {
    /// Fetch the authenticated user's Home dashboard.
    ///
    /// Errors are mapped to `APIError` by the concrete implementation:
    /// `.unauthorized` on HTTP 401 (signals "route to Login"),
    /// `.server(Int)` on 5xx, `.transport` on URLError, `.decoding` on
    /// a malformed payload.
    func fetchHome() async throws -> HomeDashboard
}
