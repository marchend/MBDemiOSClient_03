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
/// `phoneNumber` is nullable in the BFF contract — payroll-only or
/// privacy-restricted profiles may omit it — so it must stay optional
/// here. `email` is always present.
struct Customer: Codable, Equatable {
    let id: String
    let firstName: String
    let lastName: String
    let email: String
    let phoneNumber: String?
}
