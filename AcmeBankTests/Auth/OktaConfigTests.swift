import XCTest
@testable import AcmeBank

final class OktaConfigTests: XCTestCase {

    // MARK: - Fixtures

    private func realInfo(
        issuer: String = "https://acme.okta.com/oauth2/default",
        clientID: String = "0oaTESTCLIENT",
        redirectURI: String = "com.acmebank.mobile:/callback",
        scopes: String = "openid profile offline_access"
    ) -> [String: Any] {
        return [
            "OktaIssuer": issuer,
            "OktaClientID": clientID,
            "OktaRedirectURI": redirectURI,
            "OktaScopes": scopes,
        ]
    }

    // MARK: - .configured happy path

    func testConfiguredWhenAllKeysPresent() {
        let config = OktaConfig.load(from: realInfo())
        guard case let .configured(issuer, clientID, redirectURI, scopes) = config else {
            XCTFail("Expected .configured but got \(config)")
            return
        }
        XCTAssertEqual(issuer.absoluteString, "https://acme.okta.com/oauth2/default")
        XCTAssertEqual(clientID, "0oaTESTCLIENT")
        XCTAssertEqual(redirectURI.absoluteString, "com.acmebank.mobile:/callback")
        XCTAssertEqual(scopes, "openid profile offline_access")
    }

    // MARK: - .notConfigured when sentinel present

    func testNotConfiguredWhenIssuerSentinel() {
        var info = realInfo()
        info["OktaIssuer"] = "__OKTA_ISSUER_UNSET__"

        let config = OktaConfig.load(from: info)
        guard case .notConfigured = config else {
            XCTFail("Expected .notConfigured but got \(config)")
            return
        }
    }

    // MARK: - reason names missing keys

    func testNotConfiguredReasonNamesMissingKeys() {
        var info = realInfo()
        info["OktaIssuer"] = "__OKTA_ISSUER_UNSET__"
        info["OktaClientID"] = "__OKTA_CLIENT_ID_UNSET__"

        let config = OktaConfig.load(from: info)
        guard case let .notConfigured(reason) = config else {
            XCTFail("Expected .notConfigured but got \(config)")
            return
        }
        XCTAssertTrue(
            reason.contains("OKTA_ISSUER"),
            "reason should name the missing OKTA_ISSUER var — got: \(reason)"
        )
        XCTAssertTrue(
            reason.contains("OKTA_CLIENT_ID"),
            "reason should name the missing OKTA_CLIENT_ID var — got: \(reason)"
        )
    }

    // MARK: - isConfigured-style aggregate check via load()

    func testIsConfiguredFalseWhenAnySentinel() {
        // Probe each key in turn — replacing any one with its sentinel
        // must flip the aggregate result to `.notConfigured`.
        let keysAndSentinels: [(String, String)] = [
            ("OktaIssuer",      "__OKTA_ISSUER_UNSET__"),
            ("OktaClientID",    "__OKTA_CLIENT_ID_UNSET__"),
            ("OktaRedirectURI", "__OKTA_REDIRECT_URI_UNSET__"),
            ("OktaScopes",      "__OKTA_SCOPES_UNSET__"),
        ]

        for (key, sentinel) in keysAndSentinels {
            var info = realInfo()
            info[key] = sentinel
            let config = OktaConfig.load(from: info)
            if case .configured = config {
                XCTFail("Expected .notConfigured when \(key) is a sentinel, got \(config)")
            }
        }
    }
}
