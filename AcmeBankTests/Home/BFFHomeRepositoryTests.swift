import XCTest
@testable import AcmeBank

/// Unit tests for `BFFHomeRepository` using a `URLProtocol`-stubbed
/// `URLSession`. The stub captures the outbound `URLRequest` so we can
/// assert URL + headers, and returns a canned `(Data, HTTPURLResponse)`
/// to drive the status-code branches.
final class BFFHomeRepositoryTests: XCTestCase {

    // MARK: - Setup / teardown

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeRepository(
        baseURL: String = "https://bff.example.com",
        token: String? = "test-access-token"
    ) -> BFFHomeRepository {
        return BFFHomeRepository(
            baseURL: URL(string: baseURL)!,
            accessTokenProvider: { token },
            session: makeSession()
        )
    }

    private func loadFixtureData(named name: String) throws -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            XCTFail("Missing fixture \(name).json in test bundle")
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    // MARK: - 200: returns a decoded dashboard

    func test_fetchHome_200_returnsDecodedDashboard() async throws {
        let body = try loadFixtureData(named: "home_bankuser_one")
        StubURLProtocol.stub = StubURLProtocol.Stub(
            statusCode: 200,
            body: body,
            headers: ["Content-Type": "application/json"]
        )

        let repo = makeRepository()
        let dashboard = try await repo.fetchHome()

        XCTAssertEqual(dashboard.customer.id, "cust-1002")
        XCTAssertEqual(dashboard.accounts.count, 4)
        XCTAssertEqual(dashboard.recentTransactions.count, 3)
    }

    // MARK: - URL + headers on the wire

    func test_fetchHome_sendsCorrectUrlAndHeaders() async throws {
        let body = try loadFixtureData(named: "home_bankuser_one")
        StubURLProtocol.stub = StubURLProtocol.Stub(statusCode: 200, body: body)

        let repo = makeRepository(
            baseURL: "https://bff.example.com",
            token: "abc.def.ghi"
        )
        _ = try await repo.fetchHome()

        guard let captured = StubURLProtocol.lastRequest else {
            XCTFail("Expected at least one captured request")
            return
        }
        XCTAssertEqual(captured.url?.absoluteString, "https://bff.example.com/v1/home")
        XCTAssertEqual(captured.httpMethod, "GET")
        XCTAssertEqual(
            captured.value(forHTTPHeaderField: "Authorization"),
            "Bearer abc.def.ghi"
        )
        XCTAssertEqual(
            captured.value(forHTTPHeaderField: "Accept"),
            "application/json"
        )
    }

    // MARK: - Base URL with an existing sub-path is preserved

    /// Pins the documented behaviour that `BFFHomeRepository` preserves
    /// any path segment already present on `API_BASE_URL` (some
    /// environments host the BFF under e.g. `/bff`) and only appends
    /// `v1/home`. Guards against future refactors of the URL-building
    /// helper from regressing this case.
    func test_fetchHome_baseUrlWithSubPath_preservesSubPath() async throws {
        let body = try loadFixtureData(named: "home_bankuser_one")
        StubURLProtocol.stub = StubURLProtocol.Stub(statusCode: 200, body: body)

        let repo = makeRepository(baseURL: "https://api.example.com/bff")
        _ = try await repo.fetchHome()

        guard let captured = StubURLProtocol.lastRequest else {
            XCTFail("Expected at least one captured request")
            return
        }
        XCTAssertEqual(
            captured.url?.absoluteString,
            "https://api.example.com/bff/v1/home"
        )
    }

    // MARK: - Nil / empty token: fail-fast, no network call

    /// Security: when there is no live session (`accessTokenProvider`
    /// returns `nil`), `fetchHome()` must throw `.unauthorized` BEFORE
    /// any network activity. We assert both the typed error AND that
    /// the stub never saw a request — proving no bearer-less call hit
    /// the wire.
    func test_fetchHome_nilToken_throwsUnauthorized() async {
        StubURLProtocol.stub = StubURLProtocol.Stub(statusCode: 200, body: Data())
        let repo = makeRepository(token: nil)

        do {
            _ = try await repo.fetchHome()
            XCTFail("Expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected APIError.unauthorized, got \(error)")
        }

        XCTAssertNil(
            StubURLProtocol.lastRequest,
            "fetchHome() must not issue a network request when the access token is nil"
        )
    }

    /// Same fail-fast contract for an empty-string token — an empty
    /// `Authorization: Bearer ` header would be semantically identical
    /// to no header at all, so we treat it the same way.
    func test_fetchHome_emptyToken_throwsUnauthorized() async {
        StubURLProtocol.stub = StubURLProtocol.Stub(statusCode: 200, body: Data())
        let repo = makeRepository(token: "")

        do {
            _ = try await repo.fetchHome()
            XCTFail("Expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected APIError.unauthorized, got \(error)")
        }

        XCTAssertNil(
            StubURLProtocol.lastRequest,
            "fetchHome() must not issue a network request when the access token is empty"
        )
    }

    // MARK: - 401: typed .unauthorized

    func test_fetchHome_401_throwsUnauthorized() async {
        StubURLProtocol.stub = StubURLProtocol.Stub(statusCode: 401, body: Data())
        let repo = makeRepository()

        do {
            _ = try await repo.fetchHome()
            XCTFail("Expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected APIError.unauthorized, got \(error)")
        }
    }

    // MARK: - 500: typed .server(500)

    func test_fetchHome_500_throwsServerWithCode() async {
        StubURLProtocol.stub = StubURLProtocol.Stub(statusCode: 500, body: Data())
        let repo = makeRepository()

        do {
            _ = try await repo.fetchHome()
            XCTFail("Expected APIError.server(500)")
        } catch let APIError.server(code) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("Expected APIError.server(500), got \(error)")
        }
    }
}

// MARK: - URLProtocol stub

/// In-process `URLProtocol` that intercepts every request issued by a
/// `URLSession` configured with `protocolClasses = [StubURLProtocol.self]`.
/// Hands back the canned `Stub` and records the outbound `URLRequest`
/// for header / URL assertions.
///
/// State is stored in plain `static var`s — Swift 5.10 with strict
/// concurrency NOT enabled at this project's language level treats
/// this as a warning at most, and these tests run serially on the
/// XCTest main queue, so cross-test races are impossible by
/// construction (each test calls `StubURLProtocol.reset()` in
/// `setUp`).
final class StubURLProtocol: URLProtocol {

    struct Stub {
        let statusCode: Int
        let body: Data
        let headers: [String: String]

        init(statusCode: Int, body: Data, headers: [String: String] = [:]) {
            self.statusCode = statusCode
            self.body = body
            self.headers = headers
        }
    }

    static var stub: Stub?
    static var lastRequest: URLRequest?

    static func reset() {
        stub = nil
        lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lastRequest = request

        guard let stub = StubURLProtocol.stub else {
            let error = URLError(.badServerResponse)
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://stub.invalid")!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        // No-op — synchronous stub.
    }
}
