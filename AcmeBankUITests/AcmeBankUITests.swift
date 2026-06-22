import XCTest

final class AcmeBankUITests: XCTestCase {
    /// Bootstrap proof-of-life: UI test target compiles and links.
    /// Real critical-flow UI tests (Login, Transfer, Sign-out) belong in
    /// feature stories that also set up accessibility identifiers and mock
    /// launch arguments.
    func test_appLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }
}
