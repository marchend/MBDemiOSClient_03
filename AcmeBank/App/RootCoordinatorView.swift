import SwiftUI

/// The composition-root post-login surface.
///
/// Observes the shared `AppCoordinator` and renders either
/// `LoginView` (no session) or the production `HomeView` (signed in).
/// This is the single site that wires the REAL `BFFHomeRepository`
/// into `HomeViewModel` - the same `AppCoordinator` instance is then
/// passed in as both the `SessionCoordinating` for the view model
/// AND the `coordinator` for the `LogOutButton`, so `signOut()` /
/// `handleSessionExpired()` both route to the one source of truth
/// (`AppCoordinator.@Published session`).
///
/// **Why a dedicated `RootCoordinatorView` instead of inlining the
/// routing in `AcmeBankApp.swift`.** `App.body` is a `Scene`, and
/// `@ViewBuilder` inside `WindowGroup` re-evaluates the
/// `if let session = coordinator.session` ladder on every coordinator
/// publish. Lifting the routing into a real `View` lets us re-key the
/// `HomeView` on the access token so signing out and back in with a
/// different user always rebuilds the view model with the new
/// bearer instead of reusing a stale one held by `@StateObject`.
///
/// **REAL `BFFHomeRepository` ONLY.** No stub conformance ships in
/// the app target. If `API_BASE_URL` is missing from `Info.plist`,
/// `BFFHomeRepository?` returns `nil` and we fall back to
/// `UnreachableHomeRepository` which throws a transport error - the
/// user sees the inline "couldn't reach Acme Bank \u2014 try again"
/// state instead of a silent loading spinner. A misconfigured plist
/// is a CI bug, not a runtime user experience.
struct RootCoordinatorView: View {

    @EnvironmentObject private var coordinator: AppCoordinator

    /// The shared `AuthCoordinating` built at the app composition
    /// root. Passed in by `AcmeBankApp` rather than re-resolved here
    /// so the `LoginView` instance gets the same auth coordinator
    /// the rest of the app uses (single Keychain, single Okta
    /// service).
    let auth: AuthCoordinating

    var body: some View {
        if let session = coordinator.session {
            HomeView(
                viewModel: makeHomeViewModel(for: session),
                coordinator: coordinator
            )
            // Re-key on the bearer so a fresh sign-in (different
            // access token) always rebuilds the view model with the
            // new credentials.
            .id(session.accessToken)
        } else {
            LoginView(auth: auth)
        }
    }

    /// Construct the production `HomeViewModel`:
    ///   - `BFFHomeRepository` reads `API_BASE_URL` from `Info.plist`
    ///     and uses `session.accessToken` as the bearer,
    ///   - the shared `AppCoordinator` plays the
    ///     `SessionCoordinating` role (it conforms via
    ///     `RootCoordinator+SignOut.swift`).
    ///
    /// The `accessTokenProvider` closure captures `session` by value
    /// so a later mutation of the coordinator's `@Published session`
    /// does NOT leak a stale token into in-flight requests.
    private func makeHomeViewModel(for session: UserSession) -> HomeViewModel {
        let repo: HomeRepositoryProtocol = BFFHomeRepository(
            accessTokenProvider: { session.accessToken }
        ) ?? UnreachableHomeRepository()

        return HomeViewModel(repository: repo, coordinator: coordinator)
    }
}

/// Sentinel repository used only when `API_BASE_URL` is missing from
/// `Info.plist`. Throws a transport error on every call so the user
/// sees the inline error state with a Retry button rather than a
/// blank loading spinner.
private struct UnreachableHomeRepository: HomeRepositoryProtocol {
    func fetchHome() async throws -> HomeDashboard {
        throw APIError.transport(URLError(.badURL))
    }
}
