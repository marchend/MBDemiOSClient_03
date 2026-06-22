import XCTest

final class LoginViewUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "YES"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Sign-in button state

    func test_signInButton_isDisabledWithEmptyFields() {
        let signInButton = app.buttons["signInButton"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5),
                      "Sign In button must exist on launch")
        XCTAssertFalse(signInButton.isEnabled,
                       "Sign In button must be disabled when both fields are empty")
    }

    func test_signInButton_isDisabledWithOnlyUsernameFilledIn() {
        let signInButton = app.buttons["signInButton"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5))

        let usernameField = app.textFields["usernameField"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 5))
        usernameField.tap()
        usernameField.typeText("user@acmebank.com")

        XCTAssertFalse(signInButton.isEnabled,
                       "Sign In button must remain disabled when only username is filled")
    }

    func test_signInButton_isEnabledWhenBothFieldsArePopulated() {
        let signInButton = app.buttons["signInButton"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5))

        // Fill username
        let usernameField = app.textFields["usernameField"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 5))
        usernameField.tap()
        usernameField.typeText("user@acmebank.com")

        // Fill password via the secure field
        let passwordField = app.secureTextFields["passwordFieldSecure"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.tap()
        passwordField.typeText("secret123")

        XCTAssertTrue(signInButton.isEnabled,
                      "Sign In button must be enabled when both fields are populated")
    }

    // MARK: - Password visibility toggle

    func test_passwordToggle_switchesFieldBetweenSecureAndPlain() {
        // Initially the secure field should be visible
        let secureField = app.secureTextFields["passwordFieldSecure"]
        XCTAssertTrue(secureField.waitForExistence(timeout: 5),
                      "SecureField must be shown before toggle")

        // Tap the toggle button
        let toggleButton = app.buttons["passwordToggleButton"]
        XCTAssertTrue(toggleButton.waitForExistence(timeout: 5))
        toggleButton.tap()

        // After toggle the plain TextField should appear
        let visibleField = app.textFields["passwordFieldVisible"]
        XCTAssertTrue(visibleField.waitForExistence(timeout: 3),
                      "Plain TextField must appear after tapping the eye icon")
        XCTAssertFalse(secureField.exists,
                       "SecureField must disappear after tapping the eye icon")
    }

    func test_passwordToggle_switchesBackToSecureOnSecondTap() {
        // Toggle to visible
        let toggleButton = app.buttons["passwordToggleButton"]
        XCTAssertTrue(toggleButton.waitForExistence(timeout: 5))
        toggleButton.tap()

        // Toggle back to secure
        toggleButton.tap()

        let secureField = app.secureTextFields["passwordFieldSecure"]
        XCTAssertTrue(secureField.waitForExistence(timeout: 3),
                      "SecureField must reappear after second toggle tap")
    }
}
