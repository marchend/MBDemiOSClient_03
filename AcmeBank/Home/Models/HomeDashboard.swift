import Foundation

/// Top-level response from the BFF `GET /v1/home` endpoint.
///
/// Wire shape is snake_case JSON; this struct is decoded with
/// `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` so the
/// Swift property names stay camelCase. See `BFFHomeRepository` for the
/// configured decoder.
///
/// The contract is fixed by the BFF's OpenAPI spec — any field
/// rename here must be matched by a server-side change.
struct HomeDashboard: Codable, Equatable {
    let customer: Customer
    let accounts: [Account]
    let recentTransactions: [Transaction]
}

/// The signed-in bank customer.
///
/// Both `email` and `phoneNumber` are nullable in the BFF contract —
/// the orchestrator's customer projection omits them, and payroll-only
/// or privacy-restricted profiles may too — so they MUST stay optional.
/// A non-optional `email` makes the whole `/v1/home` decode throw
/// `valueNotFound` on a `null`, blanking the Home screen with
/// "couldn't read the response" even though every account + transaction
/// decoded fine. Neither field is rendered on Home today; keep them
/// optional regardless.
///
/// `segment` is an optional CRM tier label (e.g. "PREMIER", "STANDARD").
/// The BFF omits the key entirely for customers without a segment, so
/// the field must be optional. `.convertFromSnakeCase` handles the
/// JSON key automatically; no `CodingKeys` update is needed.
struct Customer: Codable, Equatable {
    let id: String
    let firstName: String
    let lastName: String
    let email: String?
    let phoneNumber: String?
    let segment: String?
}
