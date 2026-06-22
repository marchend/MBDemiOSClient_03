import SwiftUI

/// Sign-in screen.
///
/// **Owned by PR 4.** This file is the sole owner of `LoginView`. The UI
/// layout (top strip, logo, two fields, keep-signed-in toggle,
/// Sign In button, footer) was delivered by the earlier UI story and
/// is preserved verbatim — PR 4 only wires the dynamic behaviour
/// (loading state, error banner, end-to-end sign-in) into the existing
/// slots.
///
/// **Composition.** The View pulls `AppCoordinator` from the SwiftUI
/// environment (`@EnvironmentObject`, registered by `AcmeBankApp`) so
/// the success path can call `appCoordinator.handleSignIn(session)`
/// directly — there is exactly ONE navigation mechanism (the
/// coordinator's `@Published session`) and PR 4 must not invent a
/// second one (no `NavigationLink`, no manual root-view swap, no
/// `NotificationCenter` post).
///
/// **AuthCoordinating injection.** The ViewModel is owned by this View
/// (`@StateObject`) and needs an `AuthCoordinating` to call. We accept
/// it via `init(auth:)` so the production composition root injects the
/// shared `AuthCoordinator` built in `AcmeBankApp`, and previews /
/// tests inject a stub. We deliberately do NOT make `AuthCoordinating`
/// an `EnvironmentObject` — it's a protocol, not an ObservableObject,
/// and adding a wrapper just to thread it through the environment
/// would be more machinery than constructor injection.
struct LoginView: View {
    @EnvironmentObject private var appCoordinator: AppCoordinator
    @StateObject private var viewModel: LoginViewModel
    @State private var isPasswordVisible: Bool = false

    private let navyColor = Color(red: 0x1B / 255.0, green: 0x2A / 255.0, blue: 0x4A / 255.0)

    /// Designated initializer.
    ///
    /// - Parameter auth: The auth seam the embedded `LoginViewModel`
    ///   will call. Production callers pass the shared
    ///   `AuthCoordinating` built at the composition root; previews and
    ///   unit/UI tests pass a stub.
    init(auth: AuthCoordinating) {
        _viewModel = StateObject(wrappedValue: LoginViewModel(auth: auth))
    }

    /// Test-only initializer that lets tests inject an already-built
    /// `LoginViewModel` (typically with a mock `AuthCoordinating`
    /// pre-wired). Kept `internal` so the production code path always
    /// goes through `init(auth:)`.
    init(viewModel: LoginViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Top strip ───────────────────────────────────────────
            topStrip

            // ── Scrollable body ─────────────────────────────────────
            ScrollView {
                VStack(spacing: 24) {
                    HexagonLogoView()
                        .padding(.top, 32)

                    VStack(spacing: 4) {
                        Text("Acme Bank")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(Color(.label))

                        Text("Sign in to your account")
                            .font(.subheadline)
                            .foregroundStyle(Color(.secondaryLabel))
                    }

                    usernameField
                    passwordField

                    // Error banner sits directly below the password
                    // field so the user's eye lands on it without
                    // scanning the whole form for the failure copy.
                    ErrorBannerView(message: viewModel.errorMessage)

                    keepSignedInToggle

                    signInButton
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .frame(maxHeight: .infinity)

            // ── Footer ──────────────────────────────────────────────
            footer
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Sub-views

    private var topStrip: some View {
        VStack(spacing: 0) {
            HStack {
                Label("acmebank.okta.com", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                    .accessibilityIdentifier("topStripDomain")

                Spacer()

                Label("okta", systemImage: "dot.radiowaves.right")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                    .accessibilityIdentifier("topStripOkta")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()
        }
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Username")
                .font(.footnote)
                .fontWeight(.bold)
                .foregroundStyle(Color(.label))

            TextField("name@acmebank.com", text: $viewModel.username)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .textContentType(.username)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 1)
                )
                .disabled(viewModel.isSigningIn)
                .onChange(of: viewModel.username) { _, _ in
                    viewModel.onFieldEdit()
                }
                .accessibilityIdentifier("usernameField")
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Password")
                .font(.footnote)
                .fontWeight(.bold)
                .foregroundStyle(Color(.label))

            HStack {
                Group {
                    if isPasswordVisible {
                        TextField("Password", text: $viewModel.password)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("passwordFieldVisible")
                    } else {
                        SecureField("Password", text: $viewModel.password)
                            .textContentType(.password)
                            .accessibilityIdentifier("passwordFieldSecure")
                    }
                }

                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundStyle(Color(.secondaryLabel))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("passwordToggleButton")
            }
            .padding(.leading, 12)
            .frame(minHeight: 44)
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 1)
            )
            .disabled(viewModel.isSigningIn)
            .onChange(of: viewModel.password) { _, _ in
                viewModel.onFieldEdit()
            }
        }
    }

    /// "Keep me signed in" toggle. Bound to `viewModel.keepSignedIn`,
    /// which is forwarded to `AuthCoordinator.signIn(...)` so the
    /// refresh-token persistence branch is reachable.
    private var keepSignedInToggle: some View {
        Toggle(isOn: $viewModel.keepSignedIn) {
            Text("Keep me signed in")
                .font(.footnote)
                .foregroundStyle(Color(.label))
        }
        .disabled(viewModel.isSigningIn)
        .accessibilityIdentifier("keepSignedInToggle")
    }

    private var signInButton: some View {
        Button {
            // Snapshot the credentials BEFORE the async hop. The View
            // does not modify them, but reading them off the @Published
            // properties at the call site keeps the closure explicit
            // about what it sends to the auth layer.
            let u = viewModel.username
            let p = viewModel.password
            let k = viewModel.keepSignedIn
            Task {
                if let session = await viewModel.signIn(
                    username: u,
                    password: p,
                    keepSignedIn: k
                ) {
                    // Single navigation mechanism: hand the session to
                    // AppCoordinator. Its @Published flip causes the
                    // root view to swap from LoginView to LandingView.
                    appCoordinator.handleSignIn(session)
                }
            }
        } label: {
            ZStack {
                // Reserve the button's visual footprint even while the
                // spinner is showing so the layout doesn't jump.
                Text("Sign in")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .opacity(viewModel.isSigningIn ? 0 : 1)

                if viewModel.isSigningIn {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .accessibilityIdentifier("signInSpinner")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(!viewModel.isSignInEnabled)
        .opacity(viewModel.isSignInEnabled ? 1.0 : 0.5)
        .background(navyColor)
        .clipShape(.rect(cornerRadius: 8))          // iOS 17+ safe; hoisted above Button boundary
        .accessibilityIdentifier("signInButton")
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 4) {
                Text("Secured by")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                Image(systemName: "dot.radiowaves.right")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                Text("okta")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            .padding(.vertical, 12)
            .accessibilityIdentifier("footer")
        }
    }
}

// MARK: - Preview

/// Preview stub `AuthCoordinating` so `#Preview` does not need to stand
/// up a real `OktaAuthService` — and so the preview canvas does not
/// hit the network or surface keychain entitlement errors.
private final class PreviewAuthCoordinator: AuthCoordinating {
    func signIn(username: String, password: String, keepSignedIn: Bool) async -> AuthResult {
        return .invalidCredentials
    }
}

#Preview {
    LoginView(auth: PreviewAuthCoordinator())
        .environmentObject(AppCoordinator())
}
