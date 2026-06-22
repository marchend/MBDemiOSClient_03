import Foundation

/// Runtime view of the Okta tenant configuration injected into `Info.plist`
/// at build time by `Scripts/inject_okta_config.sh`.
///
/// The build script writes one `__<NAME>_UNSET__` sentinel per missing
/// env var rather than failing the build, so a fresh clone with no Okta
/// secrets still produces a green `xcodebuild`. `OktaConfig.load()`
/// detects those sentinels here and returns `.notConfigured(reason:)`,
/// which the auth layer uses to gate sign-in attempts.
///
/// This type intentionally contains NO `fatalError` / `preconditionFailure`
/// / force-unwrap: a missing secret must never crash the app.
enum OktaConfig: Equatable {
    case configured(issuer: URL, clientID: String, redirectURI: URL, scopes: String)
    case notConfigured(reason: String)

    /// The four Info.plist keys written by the Run Script phase.
    enum InfoPlistKey: String, CaseIterable {
        case issuer = "OktaIssuer"
        case clientID = "OktaClientID"
        case redirectURI = "OktaRedirectURI"
        case scopes = "OktaScopes"

        /// The env-var name a developer or CI job sets so the build
        /// script can pick it up. Used in `.notConfigured` reason text.
        var envVarName: String {
            switch self {
            case .issuer:      return "OKTA_ISSUER"
            case .clientID:    return "OKTA_CLIENT_ID"
            case .redirectURI: return "OKTA_REDIRECT_URI"
            case .scopes:      return "OKTA_SCOPES"
            }
        }
    }

    /// Load from the main app bundle's Info.plist. Provided as a static
    /// entry point so tests can inject a synthetic dictionary.
    static func load(from infoDictionary: [String: Any]? = Bundle.main.infoDictionary) -> OktaConfig {
        let info = infoDictionary ?? [:]

        // Collect per-key string values + missing-key list in one pass.
        var values: [InfoPlistKey: String] = [:]
        var missingEnvVars: [String] = []

        for key in InfoPlistKey.allCases {
            let raw = (info[key.rawValue] as? String) ?? ""
            if raw.isEmpty || isUnsetSentinel(raw) {
                missingEnvVars.append(key.envVarName)
            } else {
                values[key] = raw
            }
        }

        if !missingEnvVars.isEmpty {
            let list = missingEnvVars.joined(separator: ", ")
            let reason = "Missing \(list) on this build — see README \"Okta build configuration\"."
            return .notConfigured(reason: reason)
        }

        // All four present. Parse URLs; if either URL is malformed,
        // surface that as `.notConfigured` rather than crashing.
        guard
            let issuerString = values[.issuer],
            let issuerURL = URL(string: issuerString)
        else {
            return .notConfigured(reason: "Invalid OKTA_ISSUER URL in Info.plist — see README.")
        }
        guard
            let redirectString = values[.redirectURI],
            let redirectURL = URL(string: redirectString)
        else {
            return .notConfigured(reason: "Invalid OKTA_REDIRECT_URI URL in Info.plist — see README.")
        }

        // Mirror the URL guards for the string-typed keys. The validation
        // loop above already guarantees these are present and non-empty,
        // so this branch is defensive: an explicit `guard` makes the
        // invariant unambiguous and prevents a future refactor of the
        // loop from silently producing a `.configured` value with empty
        // strings that would later fail at the Okta SDK call site with
        // an opaque error.
        guard
            let clientID = values[.clientID], !clientID.isEmpty,
            let scopes = values[.scopes], !scopes.isEmpty
        else {
            return .notConfigured(
                reason: "clientID or scopes empty after validation pass — this is a bug in OktaConfig.load()."
            )
        }

        return .configured(
            issuer: issuerURL,
            clientID: clientID,
            redirectURI: redirectURL,
            scopes: scopes
        )
    }

    /// Convenience for tests + auth gating: true only when every key has
    /// a real value (no sentinels, no parse failures).
    static var isConfigured: Bool {
        if case .configured = load() { return true }
        return false
    }

    // MARK: - Helpers

    /// A value written by `inject_okta_config.sh` when its source env var
    /// is unset: literal `__<NAME>_UNSET__`. Matched structurally (prefix
    /// + suffix) so adding a new key never requires editing this check.
    private static func isUnsetSentinel(_ value: String) -> Bool {
        value.hasPrefix("__") && value.hasSuffix("_UNSET__")
    }
}
