import XCTest
import Combine
@testable import AcmeBank

/// Mock `AuthCoordinating` driven by a stubbed `AuthResult`. Records
/// the credentials it was called with so the VM tests can assert
/// `keepSignedIn` (and the rest) reach the auth seam verbatim.
private final class MockAuthCoordinator: AuthCoordinating {
    private(set) var signInCallCount = 0
    private(set) var capturedUsername: String?
    private(set) var capturedPassword: String?
    private(set) var capturedKeepSignedIn: Bool?

    /// `AuthResult` returned by the next `signIn` call. Defaulted to
    /// `.invalidCredentials` so tests that only care about the error
    /// path don't have to spell it out.
    var stubbedResult: AuthResult = .invalidCredentials

    /// Optional artificial latency. When set, the mock awaits this
    /// many nanoseconds before returning so the `isSigningIn`
    /// mid-flight assertion has a window to observe `true`.
    var artificialDelayNanoseconds: UInt64 = 0

    func signIn(username: String, password: String, keepSignedIn: Bool) async -> AuthResult {
        signInCallCount += 1
        capturedUsername = username
        capturedPassword = password
        capturedKeepSignedIn = keepSignedIn
        if artificialDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: artificialDelayNanoseconds)
        }
        return stubbedResult
    }
}

/// Build a deterministic `UserSession` for the `.success` arm.
private func makeSession(
    name: String = "Jane Doe",
    email: String = "jane@example.com"
) -> UserSession {
    return UserSession(
        userId: "00u-jane",
        displayName: name,
        email: email,
        accessToken: "access-123",
        authTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
        deviceName: "Test iPhone"
    )
}

@MainActor
final class LoginViewModelTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Initial state

    func test_initialState_isSigningInFalseAndErrorNil() {
        let vm = LoginViewModel(auth: MockAuthCoordinator())
        XCTAssertFalse(vm.isSigningIn, "isSigningIn must start false.")
        XCTAssertNil(vm.errorMessage, "errorMessage must start nil.")
    }

    func test_isSignInEnabled_falseWhenFieldsEmpty() {
        let vm = LoginViewModel(auth: MockAuthCoordinator())
        XCTAssertFalse(vm.isSignInEnabled, "Both fields empty → disabled.")
    }

    func test_isSignInEnabled_trueWhenBothFieldsFilled() {
        let vm = LoginViewModel(auth: MockAuthCoordinator())
        vm.username = "u@x.com"
        vm.password = "p"
        XCTAssertTrue(vm.isSignInEnabled)
    }

    // MARK: - signIn forwards credentials

    func test_signIn_forwardsCredentialsAndKeepSignedInToAuthCoordinator() async {
        let auth = MockAuthCoordinator()
        let vm = LoginViewModel(auth: auth)

        _ = await vm.signIn(username: "alice@acmebank.com", password: "p@ss", keepSignedIn: true)

        XCTAssertEqual(auth.signInCallCount, 1)
        XCTAssertEqual(auth.capturedUsername, "alice@acmebank.com")
        XCTAssertEqual(auth.capturedPassword, "p@ss")
        XCTAssertEqual(auth.capturedKeepSignedIn, true,
                       "keepSignedIn MUST reach AuthCoordinating — that's the AC-mandated seam.")
    }

    // MARK: - AuthResult → return value / error copy mapping

    func test_signIn_onSuccess_returnsDecodedUserSession() async {
        let auth = MockAuthCoordinator()
        let session = makeSession()
        auth.stubbedResult = .success(session, refreshToken: "rt-xyz")
        let vm = LoginViewModel(auth: auth)

        let returned = await vm.signIn(username: "u", password: "p", keepSignedIn: false)

        XCTAssertEqual(returned, session,
                       "On .success the VM must return the decoded UserSession so the View can hand it to AppCoordinator.handleSignIn.")
        XCTAssertNil(vm.errorMessage, "Successful sign-in must NOT publish an error message.")
    }

    func test_signIn_onInvalidCredentials_publishesExactErrorCopy() async {
        let auth = MockAuthCoordinator()
        auth.stubbedResult = .invalidCredentials
        let vm = LoginViewModel(auth: auth)

        let returned = await vm.signIn(username: "u", password: "p", keepSignedIn: false)

        XCTAssertNil(returned, "On failure the VM must return nil.")
        XCTAssertEqual(vm.errorMessage, "Incorrect username or password. Please try again.",
                       "Exact error copy is part of the AC.")
    }

    func test_signIn_onNetworkError_publishesExactErrorCopy() async {
        let auth = MockAuthCoordinator()
        auth.stubbedResult = .networkError
        let vm = LoginViewModel(auth: auth)

        let returned = await vm.signIn(username: "u", password: "p", keepSignedIn: false)

        XCTAssertNil(returned)
        XCTAssertEqual(vm.errorMessage, "Couldn't reach Okta — check your connection and try again.",
                       "Exact error copy is part of the AC.")
    }

    func test_signIn_onMfaUnsupported_publishesExactErrorCopy() async {
        let auth = MockAuthCoordinator()
        auth.stubbedResult = .mfaUnsupported
        let vm = LoginViewModel(auth: auth)

        let returned = await vm.signIn(username: "u", password: "p", keepSignedIn: false)

        XCTAssertNil(returned)
        XCTAssertEqual(vm.errorMessage, "MFA is required but not supported in this build.",
                       "Exact error copy is part of the AC.")
    }

    func test_signIn_onNotConfigured_publishesExactErrorCopy() async {
        let auth = MockAuthCoordinator()
        auth.stubbedResult = .notConfigured("missing OKTA_ISSUER")
        let vm = LoginViewModel(auth: auth)

        let returned = await vm.signIn(username: "u", password: "p", keepSignedIn: false)

        XCTAssertNil(returned)
        XCTAssertEqual(vm.errorMessage, "Okta is not configured on this build — see README.",
                       "Exact error copy is part of the AC. The notConfigured reason is intentionally NOT shown to the user.")
    }

    // MARK: - isSigningIn toggles

    func test_signIn_togglesIsSigningInFromFalseToTrueToFalse_onSuccess() async {
        let auth = MockAuthCoordinator()
        auth.stubbedResult = .success(makeSession(), refreshToken: nil)
        // Insert a small delay so the mid-flight observation is reliable.
        auth.artificialDelayNanoseconds = 50_000_000 // 50 ms
        let vm = LoginViewModel(auth: auth)

        XCTAssertFalse(vm.isSigningIn, "Pre-condition: not signing in yet.")

        // Observe every isSigningIn value the publisher emits.
        var observed: [Bool] = []
        vm.$isSigningIn
            .sink { observed.append($0) }
            .store(in: &cancellables)

        _ = await vm.signIn(username: "u", password: "p", keepSignedIn: false)

        XCTAssertFalse(vm.isSigningIn, "After return, isSigningIn must be false.")
        XCTAssertTrue(observed.contains(true),
                      "isSigningIn must transition to true at some point during the call.")
        XCTAssertEqual(observed.last, false,
                       "Final isSigningIn value must be false on success.")
    }

    func test_signIn_togglesIsSigningInFromFalseToTrueToFalse_onFailure() async {
        let auth = MockAuthCoordinator()
        auth.stubbedResult = .invalidCredentials
        auth.artificialDelayNanoseconds = 50_000_000
        let vm = LoginViewModel(auth: auth)

        var observed: [Bool] = []
        vm.$isSigningIn
            .sink { observed.append($0) }
            .store(in: &cancellables)

        _ = await vm.signIn(username: "u", password: "p", keepSignedIn: false)

        XCTAssertFalse(vm.isSigningIn, "Even on failure, isSigningIn must be cleared on return.")
        XCTAssertTrue(observed.contains(true),
                      "isSigningIn must still flip to true mid-flight on the failure path.")
        XCTAssertEqual(observed.last, false)
    }

    // MARK: - onFieldEdit clears the error banner

    func test_onFieldEdit_clearsErrorMessage() {
        let vm = LoginViewModel(auth: MockAuthCoordinator())
        vm.errorMessage = "Incorrect username or password. Please try again."

        vm.onFieldEdit()

        XCTAssertNil(vm.errorMessage,
                     "Editing either credential field must dismiss the inline error banner.")
    }

    func test_onFieldEdit_isNoOpWhenErrorAlreadyNil() {
        let vm = LoginViewModel(auth: MockAuthCoordinator())
        XCTAssertNil(vm.errorMessage)

        // Should simply not throw / not assign — just confirm idempotence.
        vm.onFieldEdit()
        vm.onFieldEdit()

        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - errorMessage cleared before a new attempt

    func test_signIn_clearsPreviousErrorMessageBeforeNewAttempt() async {
        let auth = MockAuthCoordinator()
        auth.stubbedResult = .success(makeSession(), refreshToken: nil)
        let vm = LoginViewModel(auth: auth)
        vm.errorMessage = "Stale error from a previous attempt"

        _ = await vm.signIn(username: "u", password: "p", keepSignedIn: false)

        XCTAssertNil(vm.errorMessage,
                     "A successful retry must not leave a stale error banner visible.")
    }

    // MARK: - Password zeroing (security regression coverage)
    //
    // The pre-async-refactor LoginViewModel explicitly cleared
    // `self.password = ""` on every signIn() exit path. That test
    // (`test_signIn_clearsPasswordAfterCall`) was lost in the deletion
    // of `AcmeBank/Features/Login/LoginViewModelTests.swift`. PR-7
    // review flagged this: without coverage the regression — cleartext
    // password living on the @StateObject-owned ViewModel for the
    // lifetime of LoginView — is invisible to the test suite.
    //
    // We assert the zeroing on BOTH the success and failure paths,
    // because the failure path is where the window is widest: the view
    // stays mounted and the credential would otherwise linger until
    // the user types into the field again.

    func test_signIn_clearsPasswordAfterCall_onSuccess() async {
        let auth = MockAuthCoordinator()
        auth.stubbedResult = .success(makeSession(), refreshToken: nil)
        let vm = LoginViewModel(auth: auth)
        vm.password = "hunter2"

        _ = await vm.signIn(username: "u", password: "hunter2", keepSignedIn: false)

        XCTAssertEqual(vm.password, "",
                       "password must be zeroed after signIn on the success path — auth layer owns the token from here on.")
    }

    func test_signIn_clearsPasswordAfterCall_onInvalidCredentials() async {
        let auth = MockAuthCoordinator()
        auth.stubbedResult = .invalidCredentials
        let vm = LoginViewModel(auth: auth)
        vm.password = "hunter2"

        _ = await vm.signIn(username: "u", password: "hunter2", keepSignedIn: false)

        XCTAssertEqual(vm.password, "",
                       "password must be zeroed even on the failure path; LoginView stays mounted indefinitely until retry.")
    }

    func test_signIn_clearsPasswordAfterCall_onNetworkError() async {
        let auth = MockAuthCoordinator()
        auth.stubbedResult = .networkError
        let vm = LoginViewModel(auth: auth)
        vm.password = "hunter2"

        _ = await vm.signIn(username: "u", password: "hunter2", keepSignedIn: false)

        XCTAssertEqual(vm.password, "",
                       "password must be zeroed on the network-error path as well.")
    }
}
