import Foundation

/// A single posted transaction returned in
/// `HomeDashboard.recentTransactions`. Newest-first ordering is the
/// BFF's responsibility — clients must not re-sort.
///
/// `description` is ALWAYS present and is the human-readable label the
/// UI must render (e.g. "Payroll — Sisystems"). `merchantName` is
/// NULLABLE — it is `null` for payroll/internal transfers — so it can
/// only be used as a fallback for avatar initials, never as the row
/// label. `category` is also nullable.
///
/// `amount` is `Decimal` for the same lossless-money reasons as
/// `Account.balance`. A negative `amount` is a debit; the UI renders it
/// with a leading U+2212 minus sign in the SAME monochrome colour as
/// positive amounts (never red/green) — see the parent story's visual
/// design contract.
///
/// `postedDate` is a full ISO-8601 date-time (e.g.
/// `"2026-06-08T07:48:00Z"`), so it MUST be decoded with
/// `JSONDecoder.dateDecodingStrategy = .iso8601` — decoding it as a
/// date-only "yyyy-MM-dd" string would throw on the live payload.
struct Transaction: Codable, Equatable {
    let id: String
    let accountId: String
    let description: String
    let amount: Decimal
    let postedDate: Date
    let category: String?
    let merchantName: String?
}
