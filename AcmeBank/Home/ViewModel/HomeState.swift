import Foundation

/// View-driven state of the Home dashboard.
///
/// The Home screen has exactly three render modes — a skeleton/spinner
/// while the BFF call is in flight, the fully-loaded dashboard, or an
/// inline error with a Retry affordance. Modelling these as a closed
/// enum (rather than a bag of `isLoading`, `dashboard?`, `error?`
/// flags) makes invalid combinations unrepresentable: the view can
/// `switch` exhaustively and the compiler enforces that every new
/// case is handled.
///
/// `loaded` carries the decoded `HomeDashboard` so the view binds
/// directly to a non-optional value — no `if let dashboard = ...`
/// ladder, no force-unwrap.
///
/// `error` carries a user-facing copy string already mapped by the
/// view model. The underlying `APIError` is logged at the boundary
/// and intentionally NOT surfaced to the view — the view layer must
/// not pattern-match on transport vs. server vs. decoding errors
/// (they all render the same inline banner + Retry button per the
/// AC).
enum HomeState: Equatable {
    /// The initial state and the state during a `retry()`. Drives a
    /// spinner / skeleton in the view.
    case loading
    /// Happy path: the BFF returned a `HomeDashboard` that decoded
    /// cleanly. The view renders the customer header, accounts list,
    /// and recent transactions from this value.
    case loaded(HomeDashboard)
    /// 5xx, transport, or decoding failure. The associated string is
    /// the already-localised copy the inline banner renders. 401 does
    /// NOT land here — it routes via `SessionCoordinating
    /// .handleSessionExpired()` and the state stays on `.loading`
    /// while the root view swaps back to Login.
    case error(String)
}
