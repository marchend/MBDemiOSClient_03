import Foundation

/// A single bank account row returned in `HomeDashboard.accounts`.
///
/// Money fields (`balance`, `availableBalance`) are `Decimal` —
/// `JSONDecoder` decodes JSON numbers losslessly into `Decimal`, which
/// avoids the binary-float rounding artefacts that would otherwise show
/// up in currency formatting (e.g. 0.1 + 0.2). UI code must format these
/// through a `NumberFormatter(.currency)` keyed off `currencyCode`.
struct Account: Codable, Equatable {
    let id: String
    let name: String
    let maskedNumber: String
    let balance: Decimal
    let availableBalance: Decimal
    let type: AccountType
    let currencyCode: String
}

/// Account categorisation. The BFF wire values are UPPERCASE strings
/// (`CHEQUING`, `SAVINGS`, `CREDIT`, `INVESTMENT`) — raw values match
/// the wire exactly so the synthesized `Codable` conformance works for
/// the happy path.
///
/// The custom `init(from:)` below maps any unknown raw value to
/// `.unknown` instead of throwing. Rationale: a future server-side
/// addition of e.g. `MORTGAGE` must NOT fail the entire `/v1/home`
/// decode and blank out the user's Home screen. Unknown accounts can
/// be filtered or rendered with a generic icon in the view layer.
enum AccountType: String, Codable, Equatable {
    case chequing = "CHEQUING"
    case savings = "SAVINGS"
    case credit = "CREDIT"
    case investment = "INVESTMENT"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = AccountType(rawValue: raw) ?? .unknown
    }
}
