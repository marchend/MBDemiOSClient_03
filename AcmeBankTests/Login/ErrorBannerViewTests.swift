import XCTest
import SwiftUI
@testable import AcmeBank

/// Render-time tests for `ErrorBannerView`.
///
/// We use `UIHostingController` rather than swift-snapshot-testing so
/// the tests run on a fresh CI checkout without any committed reference
/// PNGs. The assertions are STRUCTURAL: when `message == nil`, the
/// banner contributes zero height; when set, the controller's view has
/// a non-empty intrinsic size. The exact pixel layout is owned by the
/// SwiftUI runtime — we only verify the conditional-render branch.
@MainActor
final class ErrorBannerViewTests: XCTestCase {

    private let frameSize = CGSize(width: 360, height: 200)

    // MARK: - Hidden when message is nil

    func test_banner_isHiddenWhenMessageIsNil() {
        let host = UIHostingController(rootView: ErrorBannerView(message: nil))
        host.view.frame = CGRect(origin: .zero, size: frameSize)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // With message == nil the SwiftUI body returns nothing, so the
        // hosted view's content size collapses to zero.
        let fitted = host.sizeThatFits(in: frameSize)
        XCTAssertEqual(fitted.height, 0,
                       "ErrorBannerView must render zero height when message is nil.")
    }

    func test_banner_isHiddenWhenMessageIsEmptyString() {
        // The implementation also treats an empty string as "no banner"
        // to avoid a flash during state transitions.
        let host = UIHostingController(rootView: ErrorBannerView(message: ""))
        host.view.frame = CGRect(origin: .zero, size: frameSize)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let fitted = host.sizeThatFits(in: frameSize)
        XCTAssertEqual(fitted.height, 0,
                       "ErrorBannerView must render zero height when message is the empty string.")
    }

    // MARK: - Visible when message is set

    func test_banner_isVisibleWhenMessageIsSet() {
        let host = UIHostingController(
            rootView: ErrorBannerView(message: "Incorrect username or password. Please try again.")
        )
        host.view.frame = CGRect(origin: .zero, size: frameSize)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let fitted = host.sizeThatFits(in: frameSize)
        XCTAssertGreaterThan(fitted.height, 0,
                             "ErrorBannerView must render a visible row when message is non-empty.")
        XCTAssertGreaterThan(fitted.width, 0)
    }

    func test_banner_rendersWithoutCrashingForEachCanonicalMessage() {
        // Smoke test all four AC-mandated copy strings render without
        // any layout assertion failures.
        let messages = [
            "Incorrect username or password. Please try again.",
            "Couldn't reach Okta — check your connection and try again.",
            "MFA is required but not supported in this build.",
            "Okta is not configured on this build — see README.",
        ]

        for message in messages {
            let host = UIHostingController(rootView: ErrorBannerView(message: message))
            host.view.frame = CGRect(origin: .zero, size: frameSize)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let fitted = host.sizeThatFits(in: frameSize)
            XCTAssertGreaterThan(
                fitted.height, 0,
                "ErrorBannerView must render a visible row for copy: \(message)"
            )
        }
    }
}
