import Foundation

/// Preview and test fixtures for `HomeDashboard` and its constituent types.
///
/// These fixtures are consumed by:
///   - `#Preview` blocks in `SignedInCard.swift` to render both the
///     with-badge and without-badge states on the Xcode canvas.
///   - Unit tests in `AcmeBankTests` (via `@testable import AcmeBank`)
///     that assert segment-badge rendering logic.
///
/// All fixture data is invented — no real customer PII.
enum HomeDashboardFixtures {

    /// A dashboard whose customer has `segment: "PREMIER"`.
    /// Used to verify that `SignedInCard` renders the `SegmentBadgeView`
    /// when a segment is present.
    static let previewDashboardWithSegment = HomeDashboard(
        customer: Customer(
            id: "cust-preview-1",
            firstName: "Alex",
            lastName: "Premier",
            email: "alex.premier@example.com",
            phoneNumber: "+1-604-555-0100",
            segment: "PREMIER"
        ),
        accounts: [],
        recentTransactions: []
    )

    /// A dashboard whose customer has `segment: nil`.
    /// Used to verify that `SignedInCard` renders no badge (no extra
    /// spacing, no empty pill) when segment is absent.
    static let previewDashboardNoSegment = HomeDashboard(
        customer: Customer(
            id: "cust-preview-2",
            firstName: "Jordan",
            lastName: "Standard",
            email: "jordan.standard@example.com",
            phoneNumber: nil,
            segment: nil
        ),
        accounts: [],
        recentTransactions: []
    )
}
