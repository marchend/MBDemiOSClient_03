import XCTest

/// End-to-end XCUITest that proves the Log out → Login round-trip works
/// and that signing back in as a DIFFERENT user re-fetches a different
/// Home dashboard.
///
/// **Flow under test**
/// 1. Launch the app with valid Okta credentials for user A; wait for
///    the `home.screen` identifier to appear.
/// 2. Tap `home.logout`; assert the Login screen reappears (the existing
///    `signInButton` identifier is present again).
/// 3. Type user B's credentials, tap Sign In, wait for `home.screen` to
///    appear again; assert the number of rows under `home.accounts.list`
///    differs from user A's row count — proving the Home fetch ran
///    against a different identity rather than re-showing cached data.
///
/// **Skip guard.** Like `SignInToLandingUITests`, this test is
/// `XCTSkipUnless`-skipped when `OKTA_ISSUER` is absent or empty so the
/// default CI build (no Okta tenant wired up) stays green. It also
/// skips when either user's credentials are missing — without two
/// distinct test users there is no second-user assertion to make.
///
/// **Env-var contract.** Set in the shell that launches `xcodebuild`:
///   - `OKTA_ISSUER`              — gates the test running at all.
///   - `OKTA_TEST_USERNAME`       — user A's username.
///   - `OKTA_TEST_PASSWORD`       — user A's password.
///   - `OKTA_TEST_USERNAME_B`     — user B's username (different real user).
///   - `OKTA_TEST_PASSWORD_B`     — user B's password.
/// Optional:
///   - `OKTA_CLIENT_ID`, `OKTA_REDIRECT_URI`, `OKTA_SCOPES` are
///     forwarded to the app process when present, matching
///     `SignInToLandingUITests`.
///
/// **Why we don't call `OktaConfig.load()` from here.** The UI-test
/// runner is a separate process; its `Bundle.main` is the test runner
/// bundle, not the app bundle. The injected `Info.plist` values live in
/// the app bundle and are not visible to this process. Probing
/// `ProcessInfo.processInfo.environment` directly is the correct seam
/// (see AGENT.md > Auth layer notes).
final class HomeLogoutUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            env["OKTA_ISSUER"]?.isEmpty == false,
            "Okta not configured on this build — skipping Home logout flow."
        )
        try XCTSkipUnless(
            env["OKTA_TEST_USERNAME"]?.isEmpty == false &&
            env["OKTA_TEST_PASSWORD"]?.isEmpty == false,
            "OKTA_TEST_USERNAME / OKTA_TEST_PASSWORD must be set for HomeLogoutUITests."
        )

        app = XCUIApplication()
        // Forward the OKTA_* env vars to the app process so the app's
        // `OktaConfig` sees the same tenant values the test relies on.
        // See SignInToLandingUITests for the rationale.
        for key in ["OKTA_ISSUER", "OKTA_CLIENT_ID", "OKTA_REDIRECT_URI", "OKTA_SCOPES"] {
            if let value = env[key] {
                app.launchEnvironment[key] = value
            }
        }
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Test 1 — Log out returns to Login

    /// Sign in as user A → assert `home.screen` appears → tap
    /// `home.logout` → assert the Login screen is shown again (the
    /// `signInButton` identifier comes back).
    func testLogOutReturnsToLogin() throws {
        let env = ProcessInfo.processInfo.environment
        let username = try XCTUnwrap(env["OKTA_TEST_USERNAME"])
        let password = try XCTUnwrap(env["OKTA_TEST_PASSWORD"])

        // ── Sign in as user A ──────────────────────────────────────
        try signIn(username: username, password: password)

        // ── Wait for Home ──────────────────────────────────────────
        let homeScreen = app.otherElements["home.screen"]
        XCTAssertTrue(
            homeScreen.waitForExistence(timeout: 15),
            "Home screen must appear within 15 s of a successful sign-in."
        )

        // ── Tap Log out ────────────────────────────────────────────
        let logoutButton = app.buttons["home.logout"]
        XCTAssertTrue(
            logoutButton.waitForExistence(timeout: 5),
            "home.logout button must be present on the Home screen."
        )
        logoutButton.tap()

        // ── Assert we're back on the Login screen ──────────────────
        // The Login screen identifier we rely on is the `signInButton`
        // accessibility identifier (also used by LoginViewUITests and
        // SignInToLandingUITests). Its reappearance is the closed-loop
        // proof that the app flipped back to the unauthenticated root.
        let signInButton = app.buttons["signInButton"]
        XCTAssertTrue(
            signInButton.waitForExistence(timeout: 10),
            "Login screen must reappear (signInButton visible) after tapping Log out."
        )
    }

    // MARK: - Test 2 — Second user sees different data

    /// Sign in as user A → log out → sign in as user B → assert the
    /// number of `home.account.row.*` elements under `home.accounts.list`
    /// differs from user A's count. A different row count is the
    /// strongest XCUITest-visible signal that the BFF call was actually
    /// re-issued under user B's identity rather than re-rendering
    /// cached state.
    func testSecondUserSeesDifferentData() throws {
        let env = ProcessInfo.processInfo.environment
        let usernameA = try XCTUnwrap(env["OKTA_TEST_USERNAME"])
        let passwordA = try XCTUnwrap(env["OKTA_TEST_PASSWORD"])

        try XCTSkipUnless(
            env["OKTA_TEST_USERNAME_B"]?.isEmpty == false &&
            env["OKTA_TEST_PASSWORD_B"]?.isEmpty == false,
            "OKTA_TEST_USERNAME_B / OKTA_TEST_PASSWORD_B must be set for the second-user assertion."
        )
        let usernameB = try XCTUnwrap(env["OKTA_TEST_USERNAME_B"])
        let passwordB = try XCTUnwrap(env["OKTA_TEST_PASSWORD_B"])

        // ── User A: sign in, capture account-row count ────────────
        try signIn(username: usernameA, password: passwordA)
        let countA = try waitForHomeAccountRowCount()

        // ── Log out ───────────────────────────────────────────────
        let logoutButton = app.buttons["home.logout"]
        XCTAssertTrue(logoutButton.waitForExistence(timeout: 5))
        logoutButton.tap()

        // ── Wait for Login to re-appear ───────────────────────────
        let signInButton = app.buttons["signInButton"]
        XCTAssertTrue(
            signInButton.waitForExistence(timeout: 10),
            "Login screen must reappear before signing in as user B."
        )

        // ── User B: sign in, capture account-row count ────────────
        try signIn(username: usernameB, password: passwordB)
        let countB = try waitForHomeAccountRowCount()

        // ── Assert different ──────────────────────────────────────
        XCTAssertNotEqual(
            countA, countB,
            "User B's account-row count (\(countB)) must differ from user A's (\(countA)) — same count suggests the Home fetch did not re-run under user B's identity."
        )
    }

    // MARK: - Helpers

    /// Type credentials into the Login form and tap Sign In. Assumes
    /// the form is on screen.
    private func signIn(username: String, password: String) throws {
        let usernameField = app.textFields["usernameField"]
        XCTAssertTrue(
            usernameField.waitForExistence(timeout: 10),
            "Username field must exist on the Login screen."
        )
        usernameField.tap()
        usernameField.typeText(username)

        let passwordField = app.secureTextFields["passwordFieldSecure"]
        XCTAssertTrue(
            passwordField.waitForExistence(timeout: 5),
            "Password field must exist on the Login screen."
        )
        passwordField.tap()
        passwordField.typeText(password)

        let signInButton = app.buttons["signInButton"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5))
        XCTAssertTrue(
            signInButton.isEnabled,
            "Sign In must be enabled once both fields are populated."
        )
        signInButton.tap()
    }

    /// Wait for `home.screen` to appear, then count descendant elements
    /// whose accessibility identifier matches `home.account.row.<n>`
    /// under `home.accounts.list`. Returns the row count.
    private func waitForHomeAccountRowCount() throws -> Int {
        let homeScreen = app.otherElements["home.screen"]
        XCTAssertTrue(
            homeScreen.waitForExistence(timeout: 15),
            "Home screen must appear within 15 s of a successful sign-in."
        )

        let accountsList = app.otherElements["home.accounts.list"]
        XCTAssertTrue(
            accountsList.waitForExistence(timeout: 10),
            "home.accounts.list container must exist on the Home screen."
        )

        // `home.account.row.<index>` identifiers are emitted per row by
        // `AccountRow`. We count via a BEGINSWITH predicate so we don't
        // hard-code an upper bound on row indices.
        let rowPredicate = NSPredicate(format: "identifier BEGINSWITH 'home.account.row.'")
        let rows = accountsList.descendants(matching: .any).matching(rowPredicate)
        return rows.count
    }
}
