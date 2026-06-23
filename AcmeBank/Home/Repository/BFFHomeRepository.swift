import Foundation

/// Production `HomeRepositoryProtocol` implementation that talks to the
/// BFF over HTTPS using the signed-in user's Okta access token.
///
/// Wire contract: `GET {API_BASE_URL}/v1/home` with headers
/// `Authorization: Bearer <accessToken>` and `Accept: application/json`.
/// The BFF resolves the user's identity from the validated JWT — the
/// client NEVER sends a customerId or CIF in the path or query.
///
/// `API_BASE_URL` is read from `Info.plist` (injected by CI / a build
/// script — never hardcoded in source). The repo is constructed once at
/// composition time and reused; `URLSession` is injected so unit tests
/// can swap in a `URLProtocol`-stubbed session.
final class BFFHomeRepository: HomeRepositoryProtocol {

    // MARK: - Dependencies

    private let session: URLSession
    private let baseURL: URL
    private let accessTokenProvider: () -> String?

    // MARK: - Init

    /// Designated initializer. All collaborators are explicit so the
    /// type stays testable without pulling in `Bundle.main` or a global
    /// session.
    ///
    /// - Parameters:
    ///   - baseURL: e.g. `https://bff.example.com` — the `/v1/home`
    ///     path is appended internally.
    ///   - accessTokenProvider: closure returning the current Okta
    ///     access token, or `nil` if there is no live session. Kept as
    ///     a closure (not a stored `String`) so it picks up token
    ///     refreshes without re-constructing the repository.
    ///   - session: defaults to `.shared`; tests inject a stubbed
    ///     `URLSession` configured with a custom `URLProtocol`.
    init(
        baseURL: URL,
        accessTokenProvider: @escaping () -> String?,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.accessTokenProvider = accessTokenProvider
        self.session = session
    }

    /// Convenience init that pulls `API_BASE_URL` from the main bundle's
    /// `Info.plist`. Used by the production composition root. Returns
    /// `nil` (rather than crashing) when the plist key is missing or
    /// malformed — the coordinator can then surface a configuration
    /// error instead of force-unwrapping.
    convenience init?(
        accessTokenProvider: @escaping () -> String?,
        bundle: Bundle = .main,
        session: URLSession = .shared
    ) {
        guard
            let raw = bundle.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
            !raw.isEmpty,
            // Reject the build-script sentinel (``__API_BASE_URL_UNSET__``,
            // written when the API_BASE_URL env var is unset at build time) and
            // any value without a URL scheme. Either would otherwise produce a
            // scheme-less ``URL`` that fails every request as an opaque transport
            // error; returning nil routes to UnreachableHomeRepository instead,
            // which is the explicit "not configured" path.
            raw != "__API_BASE_URL_UNSET__",
            let url = URL(string: raw),
            url.scheme != nil
        else {
            return nil
        }
        self.init(baseURL: url, accessTokenProvider: accessTokenProvider, session: session)
    }

    // MARK: - HomeRepositoryProtocol

    func fetchHome() async throws -> HomeDashboard {
        // Fail fast when there is no live session. We refuse to put a
        // bearer-less request on the wire even if the BFF would happen
        // to accept it (staging misconfiguration, etc.) — the JWT is
        // what scopes the response to *this* user, so a missing token
        // is a security-relevant local error, not a network error.
        guard let token = accessTokenProvider(), !token.isEmpty else {
            throw APIError.unauthorized
        }

        let request = buildRequest(token: token)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // `URLSession` failure (DNS, TLS, offline, timeout) — no
            // HTTP response was produced.
            throw APIError.transport(error)
        }

        // The BFF is HTTPS — every successful round-trip yields an
        // `HTTPURLResponse`. If we somehow get back a non-HTTP response,
        // treat it as a transport-level failure rather than crashing.
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(
                URLError(.badServerResponse)
            )
        }

        switch http.statusCode {
        case 200..<300:
            do {
                return try Self.decoder.decode(HomeDashboard.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.server(http.statusCode)
        }
    }

    // MARK: - Request building

    private func buildRequest(token: String) -> URLRequest {
        // `URL.appending(path:)` (iOS 16+) is the non-deprecated
        // replacement for `appendingPathComponent`. It preserves any
        // sub-path the `API_BASE_URL` already carries (some
        // environments host the BFF under e.g. `/bff`), then tacks on
        // `v1/home` without percent-encoding the embedded slash.
        let url = baseURL.appending(path: "v1/home")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - Decoder

    /// Single shared decoder configured to match the BFF wire shape:
    /// snake_case keys and full ISO-8601 date-time strings.
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
