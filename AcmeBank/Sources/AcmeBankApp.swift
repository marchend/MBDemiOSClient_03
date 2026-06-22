import SwiftUI

/// SwiftUI entry point.
///
/// Composition root for the app: owns the single `AppCoordinator`
/// `@StateObject` and renders either `LoginView` (no session) or
/// `LandingView` (session present). The coordinator is also injected
/// into the SwiftUI environment via `.environmentObject(_:)` so that
/// `LoginView` (wired in a later PR) can pull it with
/// `@EnvironmentObject` to call `handleSignIn` \u2014 wiring the success
/// callback in this file again would force a re-edit of the
/// composition root every time the login flow grows.
///
/// **Why this file owns the @main and not `AcmeBank/App/AcmeBankApp.swift`.**
/// PR 3 collapses the original bootstrap entry point into this single
/// file. Shipping two `@main` `App` structs is a compile error
/// (\"'main' attribute can only apply to one type in a module\"), so
/// the original `AcmeBank/App/AcmeBankApp.swift` is removed in the same
/// PR.
@main
struct AcmeBankApp: App {

    /// Single source of truth for auth state across the app. Owned by
    /// the `App` struct as a `@StateObject` so its lifetime matches the
    /// process and the same instance survives every SwiftUI re-render
    /// of the root scene.
    @StateObject private var coordinator = AppCoordinator()

    /// Production Keychain used by the launch-time silent-refresh
    /// probe. Held here (and not inside `AppCoordinator`) because the
    /// probe path \u2014 loadRefreshToken \u2014 is a read-only concern that
    /// does not belong on the coordinator's API surface.
    private let keychain: KeychainStoring = KeychainStore()

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(coordinator)
                .task {
                    await attemptSilentRefreshOnLaunch()
                }
        }
    }

    /// Pick the screen based on the coordinator's session state. Using
    /// `@ViewBuilder` here keeps both branches as concrete `View`
    /// types without an `AnyView` wrapper.
    @ViewBuilder
    private var rootView: some View {
        if let session = coordinator.session {
            LandingView(session: session)
        } else {
            // PR 4 will replace the no-op closure with a real wiring
            // that calls `coordinator.handleSignIn(session)` from the
            // `@EnvironmentObject`-injected coordinator. This PR only
            // ships the composition root.
            LoginView(onSignIn: { _, _ in })
        }
    }

    /// Best-effort silent-refresh probe on launch.
    ///
    /// Today this only checks whether a refresh token is persisted; a
    /// future PR will swap in a real `AuthService.refreshTokenIfNeeded`
    /// that mints a fresh `UserSession` from it and feeds it into
    /// `coordinator.handleSignIn(_:)`. Failures \u2014 missing token,
    /// keychain error, network error \u2014 are SWALLOWED here: they
    /// simply leave `coordinator.session == nil`, which renders
    /// `LoginView`. We must never crash on a launch-time read.
    private func attemptSilentRefreshOnLaunch() async {
        do {
            guard let _ = try keychain.loadRefreshToken() else {
                return
            }
            // Hook point for the future refresh flow. Intentionally
            // a no-op today \u2014 see the doc comment above.
        } catch {
            #if DEBUG
            print("AcmeBankApp: silent-refresh probe failed: \(error)")
            #endif
        }
    }
}
