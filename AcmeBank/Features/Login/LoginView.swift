import SwiftUI

struct LoginView: View {
    @StateObject private var viewModel: LoginViewModel
    @State private var isPasswordVisible: Bool = false

    private let navyColor = Color(red: 0x1B / 255.0, green: 0x2A / 255.0, blue: 0x4A / 255.0)

    /// Closure injected by the caller; invoked on Sign In tap with (username, password).
    /// Stored and forwarded to the ViewModel so that tests can also spy via `viewModel.onSignIn`.
    private let onSignIn: (String, String) -> Void

    init(onSignIn: @escaping (String, String) -> Void) {
        self.onSignIn = onSignIn
        _viewModel = StateObject(wrappedValue: LoginViewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Top strip ────────────────────────────────────────────────
            topStrip

            // ── Scrollable body ──────────────────────────────────────────
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

                    ErrorBannerView(message: viewModel.errorMessage)

                    signInButton
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .frame(maxHeight: .infinity)

            // ── Footer ───────────────────────────────────────────────────
            footer
        }
        .background(Color(.systemBackground))
        .onAppear {
            // Wire the injected closure into the ViewModel so callers
            // and unit-test spies both work via viewModel.onSignIn.
            viewModel.onSignIn = onSignIn
        }
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

    private var signInButton: some View {
        Button {
            viewModel.onSignIn(viewModel.username, viewModel.password)
        } label: {
            Text("Sign in")
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(navyColor)
                .cornerRadius(8)
        }
        .disabled(!viewModel.isSignInEnabled)
        .opacity(viewModel.isSignInEnabled ? 1.0 : 0.5)
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
    LoginView(onSignIn: { _, _ in })
}
