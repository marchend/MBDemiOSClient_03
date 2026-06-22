import XCTest
@testable import AcmeBank

/// `LandingView` tests.
///
/// The test target does not ship ViewInspector, so we exercise the
/// view's copy via its `static` string builders (`greeting(for:)` /
/// `subhead(for:)`) which the body uses verbatim. Asserting on these
/// helpers proves two things at once:
///
///   1. The strings are derived from the injected `UserSession`, not
///      hardcoded \u2014 swapping the session changes the output.
///   2. The greeting renders the display name and the subhead renders
///      the email, in the shape the design calls for.
///
/// We also instantiate the SwiftUI view itself so a future refactor
/// that breaks the initializer is caught at compile time by the test
/// target, not only on a real device.
final class LandingViewTests: XCTestCase {

    private func makeSession(name: String, email: String) -> UserSession {
        return UserSession(
            userId: "00u-test",
            displayName: name,
            email: email,
            accessToken: "access-abc",
            authTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Test iPhone"
        )
    }

    // MARK: - Greeting

    func testGreetingRendersDisplayName() {
        let session = makeSession(name: "Jane Doe", email: "jane@example.com")

        let greeting = LandingView.greeting(for: session)

        XCTAssertEqual(greeting, "Welcome, Jane Doe",
                       "Greeting must read 'Welcome, {displayName}' using the session's name verbatim.")
        XCTAssertTrue(greeting.contains(session.displayName),
                      "Greeting must include the session's displayName.")
    }

    func test_greeting_changesWhenDisplayNameChanges() {
        // Proves the greeting is NOT hardcoded \u2014 two different
        // sessions must produce two different greetings.
        let sessionA = makeSession(name: "Alice", email: "a@example.com")
        let sessionB = makeSession(name: "Bob", email: "b@example.com")

        XCTAssertNotEqual(
            LandingView.greeting(for: sessionA),
            LandingView.greeting(for: sessionB),
            "Greeting must vary with the injected session \u2014 a constant value would mean the displayName isn't really being read."
        )
    }

    // MARK: - Subhead (email)

    func testEmailRendersBelowGreeting() {
        let session = makeSession(name: "Jane Doe", email: "jane@example.com")

        let subhead = LandingView.subhead(for: session)

        XCTAssertEqual(subhead, "jane@example.com",
                       "Subhead must render the session's email verbatim.")
    }

    func test_subhead_changesWhenEmailChanges() {
        let sessionA = makeSession(name: "Jane", email: "jane@example.com")
        let sessionB = makeSession(name: "Jane", email: "jane.doe@acme.test")

        XCTAssertNotEqual(
            LandingView.subhead(for: sessionA),
            LandingView.subhead(for: sessionB),
            "Subhead must vary with the injected session's email."
        )
    }

    // MARK: - No-hardcoded-string contract

    func testNoHardcodedUITestUserString() {
        // The bootstrap placeholder said \"Welcome, UITest User\" \u2014 PR 3
        // removes it. Build the greeting from a session whose name is
        // explicitly NOT that placeholder and assert the rendered copy
        // doesn't sneak the old string back in.
        let session = makeSession(name: "Real Customer", email: "customer@acme.test")

        let greeting = LandingView.greeting(for: session)
        let subhead = LandingView.subhead(for: session)

        XCTAssertFalse(greeting.contains("UITest User"),
                       "Greeting must not contain the removed bootstrap placeholder.")
        XCTAssertFalse(subhead.contains("UITest User"),
                       "Subhead must not contain the removed bootstrap placeholder.")
        XCTAssertTrue(greeting.contains("Real Customer"),
                      "Greeting must reflect the injected session's displayName.")
    }

    // MARK: - View instantiation smoke test

    func test_landingView_initializerSmokeTest() {
        // Compile-time guard: if a later refactor breaks the
        // `init(session:)` signature, this fails the test target build
        // rather than only being caught on-device.
        let session = makeSession(name: "Jane Doe", email: "jane@example.com")
        _ = LandingView(session: session)
    }
}
