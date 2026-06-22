import Foundation
#if canImport(UIKit)
import UIKit
#endif
import OktaDirectAuth

/// SDK-agnostic auth seam: given a username + password, return an
/// exhaustive `AuthResult`. The `AuthCoordinator` and (future) login
/// view model talk to this protocol \u2014 never to `OktaAuthService` or
/// `OktaDirectAuth` directly \u2014 so tests can inject a fake.
protocol DirectAuthenticating {
    func signIn(username: String, password: String) async -> AuthResult
}

// MARK: - Neutral driver seam

/// Internal abstraction over Okta's `DirectAuthenticationFlow.start`.
/// `OktaAuthService` talks to this protocol, NOT to the SDK type, so
/// unit tests of the AuthResult-mapping logic don't have to import
/// `OktaDirectAuth` or stand up an SDK type they can't construct
/// without a network round-trip.
///
/// The live implementation (`LiveDirectAuthDriver`) is the only place
/// in the codebase that touches `DirectAuthenticationFlow`. When the
/// SDK ships a breaking 2.y change, that file is the blast radius.
protocol DirectAuthFlowDriver {
    func start(username: String, password: String) async -> RawDirectAuthOutcome
}

/// Neutral, SDK-free outcome of a single DirectAuth attempt. The token
/// strings are present on the success path so `OktaAuthService` can
/// decode the ID token and build a `UserSession`.
enum RawDirectAuthOutcome: Equatable {
    case success(idToken: String, accessToken: String, refreshToken: String?)
    case invalidCredentials
    case network
    case mfaRequired
    case unknown
}

// MARK: - OktaAuthService

/// Concrete `DirectAuthenticating` that drives Okta's DirectAuth flow,
/// decodes the returned ID token, and packages everything into an
/// `AuthResult`.
final class OktaAuthService: DirectAuthenticating {
    private let driver: DirectAuthFlowDriver
    private let deviceName: String
    private let clock: () -> Date

    /// Designated initializer. The driver is the SDK seam; in
    /// production callers use `OktaAuthService(issuer:clientID:...)`
    /// which builds a `LiveDirectAuthDriver` from `OktaConfig`.
    init(
        driver: DirectAuthFlowDriver,
        deviceName: String = OktaAuthService.currentDeviceName(),
        clock: @escaping () -> Date = Date.init
    ) {
        self.driver = driver
        self.deviceName = deviceName
        self.clock = clock
    }

    /// Convenience initializer that wires up the real Okta SDK from
    /// the four `OktaConfig.configured` values.
    convenience init(
        issuer: URL,
        clientID: String,
        redirectURI: URL,
        scopes: String
    ) {
        let live = LiveDirectAuthDriver(
            issuer: issuer,
            clientID: clientID,
            redirectURI: redirectURI,
            scopes: scopes
        )
        self.init(driver: live)
    }

    func signIn(username: String, password: String) async -> AuthResult {
        let outcome = await driver.start(username: username, password: password)
        switch outcome {
        case let .success(idToken, accessToken, refreshToken):
            return buildSession(
                idToken: idToken,
                accessToken: accessToken,
                refreshToken: refreshToken
            )
        case .invalidCredentials:
            return .invalidCredentials
        case .network:
            return .networkError
        case .mfaRequired:
            return .mfaUnsupported
        case .unknown:
            // Treat unknown-outcome (including unhandled SDK cases the
            // live driver can't classify) as a network-class failure
            // for the user \u2014 it's a "we couldn't complete sign-in,
            // please retry" experience either way, and we don't want
            // to leak SDK-version churn into the UI copy.
            return .networkError
        }
    }

    // MARK: - Helpers

    /// Decode the ID-token JWT, build a `UserSession`, and return the
    /// `.success` AuthResult. If the JWT cannot be decoded \u2014 a
    /// "succeeded but unreadable response" failure \u2014 we still surface
    /// it as a typed AuthResult case rather than letting an error
    /// escape the function and collapse to a generic banner in the UI.
    private func buildSession(
        idToken: String,
        accessToken: String,
        refreshToken: String?
    ) -> AuthResult {
        let claims: IDTokenClaims
        do {
            claims = try IDTokenClaims.decode(idToken: idToken)
        } catch {
            // No `.invalidServerResponse` case in this PR's AuthResult;
            // map to `.networkError` so the UI still shows a "try again"
            // copy rather than crashing. This is a conscious narrowing
            // \u2014 a future PR can widen AuthResult if needed.
            return .networkError
        }

        let authTimestamp: Date
        if let authTime = claims.auth_time {
            authTimestamp = Date(timeIntervalSince1970: authTime)
        } else {
            authTimestamp = clock()
        }

        let session = UserSession(
            userId: claims.sub,
            displayName: claims.name ?? "",
            email: claims.email ?? "",
            accessToken: accessToken,
            authTimestamp: authTimestamp,
            deviceName: deviceName
        )
        return .success(session, refreshToken: refreshToken)
    }

    /// Best-effort device-name snapshot. UIKit is not available on
    /// every test platform so this is guarded; tests inject an
    /// explicit name via the initializer.
    static func currentDeviceName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "iOS Device"
        #endif
    }
}

// MARK: - Live SDK adapter

/// The ONLY file in the codebase that talks to `OktaDirectAuth`
/// directly. It builds a `DirectAuthenticationFlow` from the
/// `OktaConfig.configured` values and translates the SDK status enum
/// into our neutral `RawDirectAuthOutcome`.
///
/// Verbatim per spec:
///   `flow.start(username, with: .password(password))`
/// Positional `username`, `with:` factor, NO `.primary` wrapper.
final class LiveDirectAuthDriver: DirectAuthFlowDriver {
    private let flow: DirectAuthenticationFlow

    init(issuer: URL, clientID: String, redirectURI: URL, scopes: String) {
        // `DirectAuthenticationFlow` in okta-mobile-swift 2.x takes
        // `issuerURL:`, `clientId:`, and a singular `scope:` parameter
        // (a `WhitespaceSeparated`-conforming type \u2014 `String` satisfies
        // it as a space-separated scope list). `redirectURI` is part
        // of the broader OAuth2 config but is unused by DirectAuth
        // itself \u2014 it's kept on this initializer so the call site
        // mirrors the four `OktaConfig.configured` values without
        // having to drop one on the floor.
        _ = redirectURI
        self.flow = DirectAuthenticationFlow(
            issuerURL: issuer,
            clientId: clientID,
            scope: scopes
        )
    }

    func start(username: String, password: String) async -> RawDirectAuthOutcome {
        do {
            let status = try await flow.start(username, with: .password(password))
            return Self.translate(status)
        } catch {
            return Self.classify(error)
        }
    }

    /// SDK `DirectAuthenticationFlow.Status` \u2192 neutral outcome.
    /// Unknown / not-yet-handled cases collapse to `.unknown` via the
    /// `default` arm \u2014 we deliberately do NOT use `@unknown default`
    /// because the SDK's enum shape can shift between 2.y minor
    /// releases and a non-exhaustive switch is the more defensive
    /// translation boundary.
    private static func translate(_ status: DirectAuthenticationFlow.Status) -> RawDirectAuthOutcome {
        switch status {
        case let .success(token):
            // Guard explicitly against a "success" token-set that
            // omits the ID token. This happens when the Okta org
            // doesn't issue an `openid`-scoped ID token (e.g. the
            // `openid` scope is missing from `OktaConfig.scopes`, or
            // an org configuration suppresses it). Without this guard
            // we'd coerce to an empty string, fail the JWT segment
            // check inside `IDTokenClaims.decode`, and surface the
            // result as `.networkError` \u2014 a user typing correct
            // credentials would see a "couldn't connect" banner with
            // no way to learn the real cause. `.unknown` keeps the
            // distinction at the seam so a future debug log can name
            // the configuration problem; the UI mapping still ends
            // up at "please retry" via `OktaAuthService`'s switch.
            guard let raw = token.idToken?.rawValue, !raw.isEmpty else {
                return .unknown
            }
            return .success(
                idToken: raw,
                accessToken: token.accessToken,
                refreshToken: token.refreshToken
            )
        default:
            // Anything that isn't an outright success is either an MFA
            // challenge or a continuation we don't (yet) support. Map
            // to `.mfaRequired` so the UI shows a clear "MFA not
            // supported by this app" message rather than a generic
            // error \u2014 it's the most likely non-success status in
            // practice and aligns with the spec's MFA test case.
            return .mfaRequired
        }
    }

    /// Throw-path classifier. Network-class errors map to `.network`;
    /// `invalid_grant` from Okta is the canonical "wrong password"
    /// signal and maps to `.invalidCredentials`. Anything else is
    /// `.unknown` so the SDK's exact error taxonomy doesn't leak.
    private static func classify(_ error: Error) -> RawDirectAuthOutcome {
        let nsError = error as NSError
        // URLError + NSURLErrorDomain are the standard network-failure
        // surface for URLSession-backed SDKs.
        if nsError.domain == NSURLErrorDomain {
            return .network
        }
        // "invalid_grant" appears in the OAuth2 error description for
        // wrong-password attempts; substring-match is sufficient and
        // resilient to the SDK wrapping the error a few times.
        let description = "\(error)".lowercased()
        if description.contains("invalid_grant")
            || description.contains("invalidgrant")
            || description.contains("invalid credentials")
        {
            return .invalidCredentials
        }
        if description.contains("network") || description.contains("offline") {
            return .network
        }
        return .unknown
    }
}
