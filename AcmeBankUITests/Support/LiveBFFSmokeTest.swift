import XCTest

/// Developer-only smoke test that performs a REAL `GET /v1/home`
/// against the configured BFF using a real Okta access token, and
/// asserts the JSON response decodes into the `HomeDashboard` shape
/// the app expects, with at least one account.
///
/// **Why this exists.** The unit tests cover decoding from fixtures;
/// the XCUITest covers end-to-end UI flow against a real Okta tenant.
/// Neither one actually verifies that the BFF the app will hit in
/// production still returns the shape this app expects. Before calling
/// the story done, a developer runs THIS test against the deployed BFF
/// to close that gap. (See the parent story note: "verify a REAL GET
/// /v1/home returns the expected shape".)
///
/// **Gating.** The test is `XCTSkipUnless`-skipped unless
/// `RUN_LIVE_BFF_SMOKE=1` is set on the test runner. CI never sets
/// this var, so the live-network call never happens in CI. The
/// developer opts in explicitly:
///
/// ```bash
/// RUN_LIVE_BFF_SMOKE=1 \
/// API_BASE_URL="https://bff.example.com" \
/// OKTA_ACCESS_TOKEN="$(./scripts/get-test-token.sh)" \
/// xcodebuild test \
///   -scheme AcmeBank \
///   -destination 'platform=iOS Simulator,name=iPhone 16' \
///   -only-testing:AcmeBankUITests/LiveBFFSmokeTest \
///   CODE_SIGNING_ALLOWED=NO
/// ```
///
/// **Why the access token is read from env rather than driven via the
/// XCUITest sign-in flow.** This test is intentionally *not* a UI test
/// despite living in the UITests bundle — it stays here only because
/// the UITests bundle is the existing place that already executes
/// against a real Okta tenant in the developer's shell. Driving the
/// real Okta sign-in here would tie a network smoke test to UI timing
/// and would silently re-cover ground that `SignInToLandingUITests`
/// already covers. The token can be obtained out-of-band (Okta CLI,
/// curl against `/v1/token`, or by running the app once and reading
/// the Keychain) and pasted into the env var for one invocation.
///
/// **Why we re-declare the response types locally.** The XCUITest
/// bundle does NOT link the `AcmeBank` app module — UI-testing
/// targets cannot use `@testable import` of the host app the way unit
/// tests can. We mirror the BFF wire contract verbatim here so the
/// shape check is independent of the in-app types. If the app's
/// `HomeDashboard` or `Account` ever diverge from this mirror, the
/// matching unit-test fixture decode would still pass while THIS
/// smoke check would fail — which is the early warning we want.
///
/// **What the test asserts.**
///   - The configured `API_BASE_URL` is reachable over HTTPS.
///   - The response is HTTP 200.
///   - The body decodes via `.convertFromSnakeCase` + `.iso8601`
///     (matching `BFFHomeRepository`'s decoder) into the mirror
///     `HomeDashboard` shape declared below.
///   - `dashboard.accounts.count >= 1` — the test user must have at
///     least one account; without that the shape check would tolerate
///     a server-side regression that emptied the list.
final class LiveBFFSmokeTest: XCTestCase {

    // MARK: - Gating

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            env["RUN_LIVE_BFF_SMOKE"] == "1",
            "Set RUN_LIVE_BFF_SMOKE=1 to run the live-BFF smoke test. Skipped by default — CI must never hit the live BFF."
        )
    }

    // MARK: - Tests

    /// Hit `GET {API_BASE_URL}/v1/home` with a real Okta bearer token
    /// and assert the response decodes into `HomeDashboard` with at
    /// least one account.
    func testLiveHomeEndpointReturnsValidShape() async throws {
        let env = ProcessInfo.processInfo.environment

        let baseURLString = try XCTUnwrap(
            env["API_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            "API_BASE_URL env var must be set, e.g. https://bff.example.com"
        )
        XCTAssertFalse(baseURLString.isEmpty, "API_BASE_URL must not be empty.")
        let baseURL = try XCTUnwrap(
            URL(string: baseURLString),
            "API_BASE_URL must be a valid URL — got: \(baseURLString)"
        )

        let token = try XCTUnwrap(
            env["OKTA_ACCESS_TOKEN"],
            "OKTA_ACCESS_TOKEN env var must be set to a live Okta access token. Obtain one via the Okta CLI or by signing into the app once and reading the Keychain."
        )
        XCTAssertFalse(token.isEmpty, "OKTA_ACCESS_TOKEN must not be empty.")

        // Build the same request shape `BFFHomeRepository` builds in
        // production: `URL.appending(path:)` preserves any sub-path
        // the base URL carries, and the headers match exactly.
        let endpoint = baseURL.appending(path: "v1/home")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // 20 s is generous for a real BFF round-trip; we'd rather fail
        // loudly than block the developer indefinitely on a stuck call.
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)

        let http = try XCTUnwrap(
            response as? HTTPURLResponse,
            "Expected an HTTP response from \(endpoint.absoluteString)."
        )
        XCTAssertEqual(
            http.statusCode, 200,
            "Expected HTTP 200 from GET /v1/home, got \(http.statusCode). Body: \(String(data: data, encoding: .utf8) ?? "<non-UTF8>")"
        )

        // Match `BFFHomeRepository`'s decoder so a shape match here
        // means the production code path will also succeed.
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let dashboard: HomeDashboardMirror
        do {
            dashboard = try decoder.decode(HomeDashboardMirror.self, from: data)
        } catch {
            XCTFail(
                "Live /v1/home response did not decode into HomeDashboard: \(error). Body: \(String(data: data, encoding: .utf8) ?? "<non-UTF8>")"
            )
            return
        }

        XCTAssertGreaterThanOrEqual(
            dashboard.accounts.count, 1,
            "Live /v1/home response must return at least one account for the test user. The test user's profile likely needs at least one seeded account before this smoke check is meaningful."
        )
    }
}

// MARK: - Wire-contract mirror

/// Local mirror of `HomeDashboard` from the app target.
///
/// The XCUITest bundle does not link the `AcmeBank` module, so the
/// in-app `HomeDashboard` is not visible here. We re-declare just
/// enough of the wire contract to decode a live response and assert
/// the high-level shape. Field names and types track
/// `AcmeBank/Home/Models/HomeDashboard.swift`,
/// `AcmeBank/Home/Models/Account.swift`, and
/// `AcmeBank/Home/Models/Transaction.swift` — keep them aligned when
/// the BFF contract changes.
private struct HomeDashboardMirror: Decodable {
    let customer: CustomerMirror
    let accounts: [AccountMirror]
    let recentTransactions: [TransactionMirror]
}

private struct CustomerMirror: Decodable {
    let id: String
    let firstName: String
    let lastName: String
    let email: String
    let phoneNumber: String?
}

private struct AccountMirror: Decodable {
    let id: String
    let name: String
    let maskedNumber: String
    let balance: Decimal
    let availableBalance: Decimal
    /// Decoded as `String` (not the app's `AccountType` enum) so a
    /// server-side addition of a new account type does not fail the
    /// smoke decode and obscure the real shape check.
    let type: String
    let currencyCode: String
}

/// We don't pin every transaction field here — the BFF contract may
/// add fields over time and we don't want this smoke test to become a
/// brittle full-schema lock. We assert only that the field exists and
/// decodes; specific field types are covered by the app's unit-test
/// fixture decode.
private struct TransactionMirror: Decodable {}
