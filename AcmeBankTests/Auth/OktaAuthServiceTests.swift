import XCTest
@testable import AcmeBank

/// In-memory stub for the internal SDK seam. Returns a canned
/// `RawDirectAuthOutcome` so we can verify the
/// `RawDirectAuthOutcome \u2192 AuthResult` mapping inside
/// `OktaAuthService` WITHOUT importing `OktaDirectAuth` into the test
/// target.
final class StubDirectAuthDriver: DirectAuthFlowDriver {
    var outcome: RawDirectAuthOutcome
    private(set) var capturedUsername: String?
    private(set) var capturedPassword: String?

    init(outcome: RawDirectAuthOutcome) {
        self.outcome = outcome
    }

    func start(username: String, password: String) async -> RawDirectAuthOutcome {
        capturedUsername = username
        capturedPassword = password
        return outcome
    }
}

/// Builds a syntactically-valid JWT with the supplied claim dict for
/// the `.success` test cases.
private func makeJWT(claims: [String: Any]) -> String {
    func segment(_ obj: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        var s = data.base64EncodedString()
        s = s.replacingOccurrences(of: "+", with: "-")
             .replacingOccurrences(of: "/", with: "_")
             .replacingOccurrences(of: "=", with: "")
        return s
    }
    let header = segment(["alg": "none", "typ": "JWT"])
    let payload = segment(claims)
    return "\(header).\(payload).sig"
}

final class OktaAuthServiceTests: XCTestCase {

    // MARK: - .success mapping

    func testSuccessDecodesIntoUserSessionAndPropagatesRefreshToken() async {
        let jwt = makeJWT(claims: [
            "sub": "00u-1",
            "name": "Alice",
            "email": "alice@example.com",
            "auth_time": 1_700_000_000,
        ])
        let driver = StubDirectAuthDriver(outcome: .success(
            idToken: jwt,
            accessToken: "access-1",
            refreshToken: "refresh-1"
        ))
        let svc = OktaAuthService(driver: driver, deviceName: "Sim", clock: Date.init)

        let result = await svc.signIn(username: "alice", password: "pw")

        guard case let .success(session, refresh) = result else {
            return XCTFail("Expected .success, got \(result)")
        }
        XCTAssertEqual(session.userId, "00u-1")
        XCTAssertEqual(session.displayName, "Alice")
        XCTAssertEqual(session.email, "alice@example.com")
        XCTAssertEqual(session.accessToken, "access-1")
        XCTAssertEqual(refresh, "refresh-1")
        XCTAssertEqual(driver.capturedUsername, "alice")
        XCTAssertEqual(driver.capturedPassword, "pw")
    }

    // MARK: - .invalidCredentials mapping

    func testInvalidCredentialsMapsToAuthResult() async {
        let driver = StubDirectAuthDriver(outcome: .invalidCredentials)
        let svc = OktaAuthService(driver: driver)

        let result = await svc.signIn(username: "x", password: "y")
        XCTAssertEqual(result, .invalidCredentials)
    }

    // MARK: - .network mapping

    func testNetworkOutcomeMapsToNetworkError() async {
        let driver = StubDirectAuthDriver(outcome: .network)
        let svc = OktaAuthService(driver: driver)

        let result = await svc.signIn(username: "x", password: "y")
        XCTAssertEqual(result, .networkError)
    }

    // MARK: - .mfaRequired mapping

    func testMFARequiredMapsToMFAUnsupported() async {
        let driver = StubDirectAuthDriver(outcome: .mfaRequired)
        let svc = OktaAuthService(driver: driver)

        let result = await svc.signIn(username: "x", password: "y")
        XCTAssertEqual(result, .mfaUnsupported)
    }

    // MARK: - unknown outcome

    func testUnknownOutcomeMapsToNetworkError() async {
        // Unknown SDK cases collapse to a "please retry" experience in
        // the UI \u2014 same surface as a network blip.
        let driver = StubDirectAuthDriver(outcome: .unknown)
        let svc = OktaAuthService(driver: driver)

        let result = await svc.signIn(username: "x", password: "y")
        XCTAssertEqual(result, .networkError)
    }

    // MARK: - corrupt ID token on success path

    func testCorruptIDTokenOnSuccessDoesNotCrash() async {
        // The IdP "succeeded" but returned an unreadable token. The
        // service must NOT crash and must NOT let an Error escape
        // \u2014 it surfaces a typed AuthResult case instead.
        let driver = StubDirectAuthDriver(outcome: .success(
            idToken: "not.a.jwt-payload-not-base64-@@@",
            accessToken: "access",
            refreshToken: nil
        ))
        let svc = OktaAuthService(driver: driver)

        let result = await svc.signIn(username: "x", password: "y")
        // Per OktaAuthService.buildSession, an undecodable ID token
        // narrows to .networkError. The important assertion is that
        // we got a typed result back, not a thrown error.
        if case .success = result {
            XCTFail("Expected non-success result for corrupt JWT, got .success")
        }
    }

    // MARK: - empty ID token on success path

    func testEmptyIDTokenOnSuccessPathIsNotMistakenForSuccess() async {
        // Belt-and-braces for the IdP misconfiguration case: if a
        // future driver were to surface an empty idToken in the
        // `.success` outcome (e.g. the `openid` scope is missing from
        // `OktaConfig.scopes`), `OktaAuthService.buildSession` must NOT
        // return `.success` with a `UserSession` built from junk claims.
        // It must surface a non-success AuthResult instead.
        //
        // The `LiveDirectAuthDriver.translate` guard already collapses
        // an empty-rawValue ID token to `.unknown` upstream of this
        // service, so in practice this branch is reached only via a
        // misbehaving custom driver \u2014 but the test pins down the
        // contract regardless.
        let driver = StubDirectAuthDriver(outcome: .success(
            idToken: "",
            accessToken: "access",
            refreshToken: nil
        ))
        let svc = OktaAuthService(driver: driver)

        let result = await svc.signIn(username: "x", password: "y")
        if case .success = result {
            XCTFail("Empty ID token must not produce .success, got \(result)")
        }
    }
}
