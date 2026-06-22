import XCTest

/// End-to-end XCUITest: tap through the login form with real Okta
/// credentials and assert the Landing screen appears.
///
/// **Skip guard.** The test is `XCTSkipUnless`-skipped when the
/// `OKTA_ISSUER` env var is absent or empty so the default CI build
/// (which has no Okta tenant wired up) stays green. On a real-config
/// build (developer laptop, demo runner) the test runs end-to-end.
///
/// **Env-var contract.** Three env vars must be set in the shell that
/// launches `xcodebuild`:
///   - `OKTA_ISSUER`        — gates the test running at all.
///   - `OKTA_TEST_USERNAME` — typed into the username field.
///   - `OKTA_TEST_PASSWORD` — typed into the password field.
/// Optional:
///   - `OKTA_TEST_DISPLAY_NAME` — when set, asserts the Landing
///     greeting contains it. When absent we just assert the
///     "Welcome, " prefix appears.
///
/// **Why we don't call `OktaConfig.load()` from here.** The UI-test
/// runner is a separate process; its `Bundle.main` is the test runner
/// bundle, not the app bundle. The injected `Info.plist` values live
/// in the app bundle and are not visible to this process. Probing
/// `ProcessInfo.processInfo.environment` directly is the correct seam
/// (see AGENT.md > Auth layer notes).
final class SignInToLandingUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        // Skip the entire test method early when the build has no
        // Okta tenant wired up. Reading from ProcessInfo (NOT
        // OktaConfig) — see file header for why.
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            env["OKTA_ISSUER"]?.isEmpty == false,
            "Okta not configured on this build — skipping end-to-end sign-in flow."
        )

        app = XCUIApplication()
        // Forward the OKTA_* env vars to the app process so the app's
        // `OktaConfig` sees the same tenant values the test relies on.
        // Without this, `xcodebuild`-spawned simulator processes would
        // start with an empty environment and the app would surface
        // `.notConfigured` regardless of what the test runner sees.
        if let issuer = env["OKTA_ISSUER"] {
            app.launchEnvironment["OKTA_ISSUER"] = issuer
        }
        if let clientID = env["OKTA_CLIENT_ID"] {
            app.launchEnvironment["OKTA_CLIENT_ID"] = clientID
        }
        if let redirectURI = env["OKTA_REDIRECT_URI"] {
            app.launchEnvironment["OKTA_REDIRECT_URI"] = redirectURI
        }
        if let scopes = env["OKTA_SCOPES"] {
            app.launchEnvironment["OKTA_SCOPES"] = scopes
        }
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func test_signIn_withValidCredentials_navigatesToLandingScreen() throws {
        let env = ProcessInfo.processInfo.environment
        let username = try XCTUnwrap(
            env["OKTA_TEST_USERNAME"],
            "OKTA_TEST_USERNAME must be set when OKTA_ISSUER is set."
        )
        let password = try XCTUnwrap(
            env["OKTA_TEST_PASSWORD"],
            "OKTA_TEST_PASSWORD must be set when OKTA_ISSUER is set."
        )

        // ── Find and fill the username field ────────────────────────
        let usernameField = app.textFields["usernameField"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 5),
                      "Username field must exist on launch.")
        usernameField.tap()
        usernameField.typeText(username)

        // ── Find and fill the password field ────────────────────────
        let passwordField = app.secureTextFields["passwordFieldSecure"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5),
                      "Password field must exist on launch.")
        passwordField.tap()
        passwordField.typeText(password)

        // ── Tap Sign In ─────────────────────────────────────────────
        let signInButton = app.buttons["signInButton"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5))
        XCTAssertTrue(signInButton.isEnabled,
                      "Sign In must be enabled once both fields are populated.")
        signInButton.tap()

        // ── Assert the Landing screen appears ───────────────────────
        // The `landingGreeting` element renders "Welcome, <displayName>".
        // Wait up to 5 s to absorb the Okta round-trip + SwiftUI swap.
        let greeting = app.staticTexts["landingGreeting"]
        XCTAssertTrue(
            greeting.waitForExistence(timeout: 5),
            "Landing screen's greeting must appear within 5 s of a successful sign-in."
        )

        let greetingText = greeting.label
        XCTAssertTrue(
            greetingText.hasPrefix("Welcome, "),
            "Landing greeting must start with 'Welcome, ' — got: \(greetingText)"
        )

        // When the test runner knows the expected display name, assert
        // it appears in the greeting. This proves the value came from
        // the real Okta ID-token claims and not a hardcoded string.
        if let expected = env["OKTA_TEST_DISPLAY_NAME"], !expected.isEmpty {
            XCTAssertTrue(
                greetingText.contains(expected),
                "Landing greeting must contain the Okta display name '\(expected)' — got: \(greetingText)"
            )
        }
    }
}
