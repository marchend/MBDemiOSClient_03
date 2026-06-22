import SwiftUI

/// SwiftUI entry point.
///
/// Composition root for the app: owns the single `AppCoordinator`
/// `@StateObject` and renders either `LoginView` (no session) or
/// `LandingView` (session present). The coordinator is also injected
/// into the SwiftUI environment via `.environmentObject(_:)` so that
/// `LoginView` can pull it with `@EnvironmentObject` to call
/// `handleSignIn(_:)` on a successful sign-in — wiring the success
/// callback in this file again would force a re-edit of the
/// composition root every time the login flow grows.
///
/// **Why this file owns the @main and not `AcmeBank/App/AcmeBankApp.swift`.**
/// PR 3 collapses the original bootstrap entry point into this single
/// file. Shipping two `@main` `App` structs is a compile error
/// ("'main' attribute can only apply to one type in a module"), so
/// the original `AcmeBank/App/AcmeBankApp.swift` is removed in the same
/// PR.
///
/// **Single Keychain instance.** A previous revision allocated one
/// `KeychainStore` here (for the silent-refresh probe) and a second one
/// inside `AppCoordinator.init`'s default argument. Both hit the same
/// `kSecAttrAccount`, which is benign today but a footgun once real
/// token writes land. We now construct ONE `KeychainStore` at the
/// composition root and inject that single reference into both the
/// probe and the coordinator (and through the coordinator into
/// `AuthCoordinator`), so the entire process operates on one store.
@main
struct AcmeBankApp: App {

    /// Single Keychain reference shared by every consumer below. Built
    /// as a static so the same instance feeds both the `@StateObject`
    /// initializer and the launch-time silent-refresh probe — SwiftUI's
    /// `@StateObject` autoclosure runs once per `App` lifetime, and we
    /// need the same object visible to `attemptSilentRefreshOnLaunch`.
    private static let sharedKeychain: KeychainStoring = KeychainStore()

    /// Single `AuthCoordinator` shared by `AppCoordinator` AND
    /// `LoginView`'s ViewModel. Built at the composition root so the
    /// navigation coordinator, the login form, and any future caller
    /// that needs to invoke the Okta exchange resolve to the same
    /// instance (and therefore the same `KeychainStoring`).
    ///
    /// The underlying `OktaAuthService` is built from `OktaConfig.load()`:
    /// when the four `OKTA_*` env vars are not present, `AuthCoordinator`
    /// short-circuits to `.notConfigured` BEFORE calling the service, so
    /// the service instance is never invoked in that case. We still
    /// need a concrete `DirectAuthenticating` to construct the
    /// coordinator, so we build one against the live config when
    /// available and a placeholder otherwise.
    private static let sharedAuth: AuthCoordinating = AuthCoordinator(
        service: makeOktaService(),
        keychain: sharedKeychain
    )

    /// Build a production `OktaAuthService` from the live `OktaConfig`.
    /// In the `.notConfigured` case we still need a concrete service to
    /// satisfy `AuthCoordinator.init`'s `DirectAuthenticating` parameter,
    /// so we fall back to a placeholder URL. This service will never be
    /// invoked because `AuthCoordinator` checks `OktaConfig.load()` on
    /// every `signIn` call and returns `.notConfigured` before reaching
    /// the service.
    private static func makeOktaService() -> OktaAuthService {
        switch OktaConfig.load() {
        case let .configured(issuer, clientID, redirectURI, scopes):
            return OktaAuthService(
                issuer: issuer,
                clientID: clientID,
                redirectURI: redirectURI,
                scopes: scopes
            )
        case .notConfigured:
            // Placeholder values — `AuthCoordinator` short-circuits on
            // `.notConfigured` before the service is called, so these
            // URLs are never actually used. The `!`s are safe because
            // the string literals are valid URLs.
            return OktaAuthService(
                issuer: URL(string: "https://unconfigured.example.com")!,
                clientID: "unconfigured",
                redirectURI: URL(string: "https://unconfigured.example.com/callback")!,
                scopes: "openid"
            )
        }
    }

    /// Single source of truth for auth state across the app. Owned by
    /// the `App` struct as a `@StateObject` so its lifetime matches the
    /// process and the same instance survives every SwiftUI re-render
    /// of the root scene.
    ///
    /// `AppCoordinator` receives the shared keychain reference AND the
    /// shared `AuthCoordinating`. The sign-in path is:
    /// `LoginView.signIn → LoginViewModel.signIn → AuthCoordinator.signIn`,
    /// then on success the View calls `AppCoordinator.handleSignIn`
    /// (pulled from `@EnvironmentObject`) to flip the root view to
    /// `LandingView`.
    @StateObject private var coordinator = AppCoordinator(
        keychain: AcmeBankApp.sharedKeychain,
        auth: AcmeBankApp.sharedAuth
    )

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
            // PR 4 wires the production sign-in path: the View pulls
            // `AppCoordinator` via `@EnvironmentObject` and calls
            // `viewModel.signIn(...) → appCoordinator.handleSignIn(...)`
            // inside its Sign In button action. The composition root
            // only has to hand the View the shared `AuthCoordinating`.
            LoginView(auth: AcmeBankApp.sharedAuth)
        }
    }

    /// Best-effort silent-refresh probe on launch.
    ///
    /// Today this only checks whether a refresh token is persisted; a
    /// future PR will swap in a real `AuthService.refreshTokenIfNeeded`
    /// that mints a fresh `UserSession` from it and feeds it into
    /// `coordinator.handleSignIn(_:)`. Failures — missing token,
    /// keychain error, network error — are SWALLOWED here: they
    /// simply leave `coordinator.session == nil`, which renders
    /// `LoginView`. We must never crash on a launch-time read.
    ///
    /// Uses `sharedKeychain` directly so the probe and the coordinator
    /// look at the same `KeychainStoring`.
    private func attemptSilentRefreshOnLaunch() async {
        do {
            guard let _ = try Self.sharedKeychain.loadRefreshToken() else {
                return
            }
            // Hook point for the future refresh flow. Intentionally
            // a no-op today — see the doc comment above.
        } catch {
            #if DEBUG
            print("AcmeBankApp: silent-refresh probe failed: \(error)")
            #endif
        }
    }
}
