import XCTest
@testable import AcmeBank

final class AcmeBankTests: XCTestCase {
    /// Bootstrap proof-of-life: test target compiles + links against the app
    /// module. Real behaviour tests belong in feature stories.
    func test_contentView_initializes() {
        _ = ContentView()
    }
}
