import Foundation

/// The four ID-token claims this app reads, decoded out of the JWT
/// payload that Okta returns alongside the access + refresh tokens.
///
/// Names match the OIDC claim spelling on the wire (`sub`, `name`,
/// `email`, `auth_time`) so the synthesised `Codable` conformance maps
/// straight onto a real Okta payload with no `CodingKeys` boilerplate.
struct IDTokenClaims: Codable, Equatable {
    let sub: String
    let name: String?
    let email: String?
    /// Seconds since the Unix epoch \u2014 OIDC `auth_time` is numeric, not
    /// an ISO-8601 string. Optional because some Okta authorisation
    /// servers omit it when `max_age` was not requested.
    let auth_time: TimeInterval?

    /// Errors thrown by `decode(idToken:)` when the input is not a
    /// well-formed JWT we can read claims out of. These are programmer
    /// errors / corrupted-input errors \u2014 the caller (auth layer) should
    /// surface them as a typed "couldn't read server response" failure
    /// rather than letting them collapse to a generic network error.
    enum DecodeError: Error, Equatable {
        case malformedJWT
        case base64DecodeFailed
        case jsonDecodeFailed
    }

    /// Parse a compact JWS (header.payload.signature) and return the
    /// claims encoded in the middle segment. The signature is NOT
    /// verified here \u2014 Okta's SDK already validated the token before it
    /// reached us; we only need the user-identifying claims to build a
    /// `UserSession`.
    static func decode(idToken: String) throws -> IDTokenClaims {
        let segments = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else {
            throw DecodeError.malformedJWT
        }
        let payloadSegment = String(segments[1])
        guard let payloadData = base64URLDecode(payloadSegment) else {
            throw DecodeError.base64DecodeFailed
        }
        do {
            return try JSONDecoder().decode(IDTokenClaims.self, from: payloadData)
        } catch {
            throw DecodeError.jsonDecodeFailed
        }
    }

    // MARK: - base64URL helper

    /// Decode the base64URL alphabet used by JWT (RFC 7515): `-` and `_`
    /// substitute for `+` and `/`, and trailing `=` padding is stripped.
    /// We restore the standard alphabet + pad to a multiple of 4 before
    /// handing to `Data(base64Encoded:)`.
    private static func base64URLDecode(_ input: String) -> Data? {
        var s = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder > 0 {
            s.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: s)
    }
}
