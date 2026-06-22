import SwiftUI

/// Root content view for AcmeBank.
///
/// Presents `LoginView` as the initial screen. This type is a
/// Hello-World placeholder retained only so the bootstrap link-test
/// (`AcmeBankTests.test_contentView_initializes`) keeps a trivial
/// SwiftUI symbol to instantiate. The real composition root is
/// `AcmeBankApp` (see `AcmeBank/Sources/AcmeBankApp.swift`), which
/// owns the shared `AuthCoordinator` and renders `LoginView` /
/// `LandingView` itself. `ContentView` is never rendered at runtime.
///
/// PR 4 reshaped `LoginView` from `init(onSignIn:)` to `init(auth:)`,
/// so this file constructs a throw-away `AuthCoordinator` inline using
/// the same placeholder-`OktaAuthService` pattern as
/// `AcmeBankApp.makeOktaService()`'s `.notConfigured` branch. The
/// coordinator is never invoked because `ContentView.body` is never
/// drawn outside of the link-test, which only checks that the view
/// initializes.
struct ContentView: View {
    var body: some View {
        LoginView(auth: ContentView.makePlaceholderAuth())
    }

    /// Build a throw-away `AuthCoordinating` suitable for the
    /// placeholder `LoginView` instantiation. Mirrors the
    /// `.notConfigured` placeholder pattern in
    /// `AcmeBankApp.makeOktaService()` — the `!`s are safe because the
    /// string literals are valid URLs, and the service is never called
    /// because `ContentView` is never rendered at runtime.
    private static func makePlaceholderAuth() -> AuthCoordinating {
        let service = OktaAuthService(
            issuer: URL(string: "https://unconfigured.example.com")!,
            clientID: "unconfigured",
            redirectURI: URL(string: "https://unconfigured.example.com/callback")!,
            scopes: "openid"
        )
        return AuthCoordinator(service: service, keychain: KeychainStore())
    }
}

#Preview {
    ContentView()
}
