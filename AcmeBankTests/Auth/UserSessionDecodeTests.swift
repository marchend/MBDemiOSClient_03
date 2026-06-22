import XCTest
@testable import AcmeBank

/// Verifies the JWT-payload decode path:
///   1. A well-formed ID token populates every `UserSession` field.
///   2. A token missing `auth_time` falls back to `Date()` (clock).
///   3. A malformed JWT produces a typed `IDTokenClaims.DecodeError`.
final class UserSessionDecodeTests: XCTestCase {

    // MARK: - Helpers

    /// Build a base64URL-encoded JWT segment from a JSON dictionary.
    private func base64URLSegment(from json: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        var s = data.base64EncodedString()
        s = s.replacingOccurrences(of: "+", with: "-")
             .replacingOccurrences(of: "/", with: "_")
             .replacingOccurrences(of: "=", with: "")
        return s
    }

    /// Assemble a fake JWT: header is a fixed stub; payload encodes
    /// the supplied claims dictionary; signature is a fixed stub.
    private func makeJWT(claims: [String: Any]) throws -> String {
        let header = try base64URLSegment(from: ["alg": "RS256", "typ": "JWT"])
        let payload = try base64URLSegment(from: claims)
        return "\(header).\(payload).sig-not-verified"
    }

    // MARK: - decode happy path

    func testDecodeProducesAllClaims() throws {
        let jwt = try makeJWT(claims: [
            "sub": "00u123",
            "name": "Jane Doe",
            "email": "jane@example.com",
            "auth_time": 1_700_000_000,
        ])

        let claims = try IDTokenClaims.decode(idToken: jwt)

        XCTAssertEqual(claims.sub, "00u123")
        XCTAssertEqual(claims.name, "Jane Doe")
        XCTAssertEqual(claims.email, "jane@example.com")
        XCTAssertEqual(claims.auth_time, 1_700_000_000)
    }

    // MARK: - UserSession build via the service

    func testServiceBuildsUserSessionFromIDToken() async throws {
        let jwt = try makeJWT(claims: [
            "sub": "00u-jane",
            "name": "Jane Doe",
            "email": "jane@example.com",
            "auth_time": 1_700_000_000,
        ])

        let driver = StubDirectAuthDriver(outcome: .success(
            idToken: jwt,
            accessToken: "access-abc",
            refreshToken: "refresh-xyz"
        ))
        let service = OktaAuthService(
            driver: driver,
            deviceName: "Test iPhone",
            clock: { Date(timeIntervalSince1970: 9_999) }
        )

        let result = await service.signIn(username: "jane", password: "pw")
        guard case let .success(session, refreshToken) = result else {
            XCTFail("Expected .success, got \(result)")
            return
        }
        XCTAssertEqual(session.userId, "00u-jane")
        XCTAssertEqual(session.displayName, "Jane Doe")
        XCTAssertEqual(session.email, "jane@example.com")
        XCTAssertEqual(session.accessToken, "access-abc")
        XCTAssertEqual(session.authTimestamp, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(session.deviceName, "Test iPhone")
        XCTAssertEqual(refreshToken, "refresh-xyz")
    }

    // MARK: - auth_time fallback

    func testAuthTimeFallsBackToClockWhenClaimMissing() async throws {
        let jwt = try makeJWT(claims: [
            "sub": "00u-noauthtime",
            "name": "Anon",
            "email": "a@example.com",
            // no auth_time
        ])
        let fixedNow = Date(timeIntervalSince1970: 42)
        let driver = StubDirectAuthDriver(outcome: .success(
            idToken: jwt,
            accessToken: "access",
            refreshToken: nil
        ))
        let service = OktaAuthService(
            driver: driver,
            deviceName: "Sim",
            clock: { fixedNow }
        )

        let result = await service.signIn(username: "x", password: "y")
        guard case let .success(session, _) = result else {
            XCTFail("Expected .success, got \(result)")
            return
        }
        XCTAssertEqual(session.authTimestamp, fixedNow,
                       "missing auth_time should fall back to the injected clock")
    }

    // MARK: - malformed JWT

    func testMalformedJWTThrowsDecodeError() {
        XCTAssertThrowsError(try IDTokenClaims.decode(idToken: "not-a-jwt")) { error in
            XCTAssertEqual(error as? IDTokenClaims.DecodeError, .malformedJWT)
        }
    }

    func testNonBase64PayloadFailsDecode() {
        // Three segments separated by dots, but the middle isn't base64.
        let jwt = "aGVhZA.@@@not-base64@@@.sig"
        XCTAssertThrowsError(try IDTokenClaims.decode(idToken: jwt)) { error in
            // Either base64 decode or json decode failure is acceptable
            // \u2014 both indicate a corrupt payload, which is the contract.
            guard let e = error as? IDTokenClaims.DecodeError else {
                XCTFail("Expected IDTokenClaims.DecodeError, got \(error)")
                return
            }
            XCTAssertTrue(e == .base64DecodeFailed || e == .jsonDecodeFailed,
                          "got \(e)")
        }
    }
}
