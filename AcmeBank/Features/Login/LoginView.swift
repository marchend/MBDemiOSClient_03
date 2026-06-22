import SwiftUI

struct LoginView: View {
    @StateObject private var viewModel: LoginViewModel
    @State private var isPasswordVisible: Bool = false

    private let navyColor = Color(red: 0x1B / 255.0, green: 0x2A / 255.0, blue: 0x4A / 255.0)

    /// The 3-arg `onSignIn` signature is mandated by the ticket's
    /// acceptance criteria: `keepSignedIn` must be threaded down to
    /// `AuthCoordinator.signIn(username:password:keepSignedIn:)`,
    /// otherwise the refresh-token persistence branch is unreachable
    /// from the UI.
    init(onSignIn: @escaping (String, String, Bool) -> Void) {
        let vm = LoginViewModel()
        vm.onSignIn = onSignIn          // wire once, here — avoids .onAppear timing dependency
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Top strip ─────────────────────────────────────────────────────────────
            topStrip

            // ── Scrollable body ───────────────────────────────────────────────────────
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
                    keepSignedInToggle

                    ErrorBannerView(message: viewModel.errorMessage)

                    signInButton
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .frame(maxHeight: .infinity)

            // ── Footer ────────────────────────────────────────────────────────────────
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
        }
    }

    /// "Keep me signed in" toggle. Bound to `viewModel.keepSignedIn`,
    /// which is forwarded to `onSignIn` so the value reaches
    /// `AuthCoordinator.signIn(username:password:keepSignedIn:)`.
    private var keepSignedInToggle: some View {
        Toggle(isOn: $viewModel.keepSignedIn) {
            Text("Keep me signed in")
                .font(.footnote)
                .foregroundStyle(Color(.label))
        }
        .accessibilityIdentifier("keepSignedInToggle")
    }

    private var signInButton: some View {
        Button {
            viewModel.signIn()
        } label: {
            Text("Sign in")
                .fontWeight(.semibold)
                .foregroundStyle(.white)
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

#Preview {
    LoginView(onSignIn: { _, _, _ in })
}
