import XCTest
@testable import AcmeBank

/// Pins down the `accessToken` redaction contract on `UserSession`.
///
/// `accessToken` is a bearer credential. A stray `print(session)`, a
/// `dump(session)`, or a crash reporter that captures
/// `CustomStringConvertible` output must NEVER emit the raw token in
/// cleartext. These tests fail loudly if a future refactor regresses
/// to default struct mirroring.
final class UserSessionRedactionTests: XCTestCase {

    private func makeSession(accessToken: String) -> UserSession {
        return UserSession(
            userId: "00u-jane",
            displayName: "Jane Doe",
            email: "jane@example.com",
            accessToken: accessToken,
            authTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Sim"
        )
    }

    func testStringInterpolationDoesNotLeakAccessToken() {
        let sensitive = "eyJ-bearer-token-must-never-show-up-in-logs"
        let session = makeSession(accessToken: sensitive)

        let interpolated = "\(session)"
        XCTAssertFalse(interpolated.contains(sensitive),
                       "String interpolation of UserSession leaked the access token: \(interpolated)")
        XCTAssertTrue(interpolated.contains("[REDACTED]"),
                      "Expected [REDACTED] placeholder in string interpolation, got: \(interpolated)")
    }

    func testStringDescribingDoesNotLeakAccessToken() {
        let sensitive = "eyJ-bearer-token-must-never-show-up-in-logs"
        let session = makeSession(accessToken: sensitive)

        let described = String(describing: session)
        XCTAssertFalse(described.contains(sensitive),
                       "String(describing:) leaked the access token: \(described)")
    }

    func testDebugDescriptionDoesNotLeakAccessToken() {
        // Crash reporter SDKs frequently capture
        // `CustomDebugStringConvertible.debugDescription` or fall back
        // to `String(reflecting:)`. Both must be redacted.
        let sensitive = "eyJ-bearer-token-must-never-show-up-in-logs"
        let session = makeSession(accessToken: sensitive)

        let debug = String(reflecting: session)
        XCTAssertFalse(debug.contains(sensitive),
                       "String(reflecting:) leaked the access token: \(debug)")
    }

    func testRedactionPreservesOtherFieldsForDebuggability() {
        // The redaction must not be so aggressive that it hides the
        // user identity \u2014 those fields are useful in logs and are
        // not credentials.
        let session = makeSession(accessToken: "secret")

        let s = "\(session)"
        XCTAssertTrue(s.contains("00u-jane"), "userId should remain visible: \(s)")
        XCTAssertTrue(s.contains("Jane Doe"), "displayName should remain visible: \(s)")
        XCTAssertTrue(s.contains("jane@example.com"), "email should remain visible: \(s)")
        XCTAssertTrue(s.contains("Sim"), "deviceName should remain visible: \(s)")
    }
}
