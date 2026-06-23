import Foundation

/// `HomeView`'s `ObservableObject` backing store.
///
/// Owns one piece of state: the closed-enum `HomeState` that drives
/// the three render modes (loading / loaded / error). Delegates the
/// network call to an injected `HomeRepositoryProtocol` and the
/// auth-state flip on a 401 to an injected `SessionCoordinating`, so
/// the view model is unit-testable without a live `URLSession` and
/// without a real `AppCoordinator`.
///
/// **No SwiftUI imports.** This file imports only `Foundation` —
/// keeping the view model headless lets the tests construct it
/// directly without standing up a SwiftUI host. If a future change
/// genuinely needs a SwiftUI type here, that is a code smell worth
/// surfacing in code review (move the offending logic into the view
/// instead).
///
/// **`@MainActor`.** `state` drives SwiftUI; every write must happen
/// on the main actor. Marking the whole class `@MainActor` makes that
/// guarantee structural rather than something every async call site
/// has to remember with `await MainActor.run { ... }`.
///
/// **401 routing.** `load()` checks for `APIError.unauthorized` BEFORE
/// it ever publishes `.loaded` or `.error`. On 401 it calls
/// `coordinator.handleSessionExpired()` (NOT `signOut()` — see
/// `SessionCoordinating` for why the two are distinct) and leaves
/// `state` on `.loading`. Publishing `.error("...")` on a 401 would
/// race the root-view swap: the user would briefly see a Home error
/// banner before Login appears. Worse, publishing the previous
/// `.loaded(dashboard)` would expose stale or another user's data on
/// the way out.
@MainActor
final class HomeViewModel: ObservableObject {

    // MARK: - Published state

    /// Single source of truth for the Home screen. Starts on
    /// `.loading` so the view renders a spinner immediately on first
    /// appearance, before `load()` has even returned.
    @Published private(set) var state: HomeState = .loading

    // MARK: - Dependencies

    private let repository: HomeRepositoryProtocol
    private let coordinator: SessionCoordinating

    // MARK: - Init

    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - repository: The seam to whatever produces a
    ///     `HomeDashboard`. Production passes `BFFHomeRepository`;
    ///     tests pass a stub that returns canned results / errors.
    ///   - coordinator: The auth-state-flip seam. Production passes
    ///     the shared `AppCoordinator`; tests pass a spy that
    ///     records which `SessionCoordinating` method was called.
    init(repository: HomeRepositoryProtocol, coordinator: SessionCoordinating) {
        self.repository = repository
        self.coordinator = coordinator
    }

    // MARK: - Intent

    /// Fetch the dashboard and publish the result.
    ///
    /// Resets `state` to `.loading` on every invocation so a `retry()`
    /// from `.error` shows the spinner again. On 401 — the typed
    /// `APIError.unauthorized` — routes via
    /// `coordinator.handleSessionExpired()` and DOES NOT publish
    /// `.loaded` or `.error`: the user is logging out, not seeing
    /// Home. On any other failure (5xx, transport, decoding) publishes
    /// `.error(<copy>)` so the view shows the inline banner + Retry.
    func load() async {
        state = .loading

        do {
            let dashboard = try await repository.fetchHome()
            state = .loaded(dashboard)
        } catch APIError.unauthorized {
            // The bearer token is gone or rejected. Hand control to
            // the session coordinator — it owns the wipe + route to
            // Login. DO NOT publish anything else into `state`:
            // anything we publish here would flash on screen for one
            // frame before the root-view swap.
            coordinator.handleSessionExpired()
        } catch let APIError.server(code) {
            state = .error(Self.serverErrorCopy(code: code))
        } catch APIError.transport {
            state = .error(Self.transportErrorCopy)
        } catch APIError.decoding {
            state = .error(Self.decodingErrorCopy)
        } catch {
            // Defensive — `HomeRepositoryProtocol`'s documented errors
            // are exactly the four `APIError` cases above, but we
            // don't want an unknown error to crash the app.
            state = .error(Self.transportErrorCopy)
        }
    }

    /// Re-run `load()`. Bound to the inline error banner's Retry
    /// button. Provided as a distinct method (rather than asking the
    /// view to call `load()` directly) so the view stays declarative
    /// and a future PR can hook retry analytics here without touching
    /// the view.
    func retry() async {
        await load()
    }

    // MARK: - Error copy

    /// 5xx — the BFF was reachable but blew up. The user can retry.
    private static func serverErrorCopy(code: Int) -> String {
        return "Something went wrong on our end (\(code)). Please try again."
    }

    /// Network failure before any HTTP response — offline, DNS, TLS,
    /// timeout.
    private static let transportErrorCopy =
        "Couldn't reach Acme Bank — check your connection and try again."

    /// The HTTP call succeeded but the body did not match the
    /// contract. Surfaced to the user as a generic "try again later"
    /// rather than the decoding details; the underlying error is the
    /// engineering team's problem, not the customer's.
    private static let decodingErrorCopy =
        "We couldn't read the response from Acme Bank. Please try again later."
}
