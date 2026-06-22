import XCTest
import Combine
@testable import AcmeBank

final class LoginViewModelTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - isSignInEnabled

    func test_isSignInEnabled_falseWhenBothFieldsEmpty() {
        let vm = LoginViewModel()
        XCTAssertFalse(vm.isSignInEnabled, "Both fields empty → disabled")
    }

    func test_isSignInEnabled_falseWhenUsernameOnlyFilled() {
        let vm = LoginViewModel()
        vm.username = "user@acmebank.com"
        XCTAssertFalse(vm.isSignInEnabled, "Password empty → disabled")
    }

    func test_isSignInEnabled_falseWhenPasswordOnlyFilled() {
        let vm = LoginViewModel()
        vm.password = "secret"
        XCTAssertFalse(vm.isSignInEnabled, "Username empty → disabled")
    }

    func test_isSignInEnabled_trueWhenBothFieldsFilled() {
        let vm = LoginViewModel()
        vm.username = "user@acmebank.com"
        vm.password = "secret"
        XCTAssertTrue(vm.isSignInEnabled, "Both fields filled → enabled")
    }

    func test_isSignInEnabled_falseWhenUsernameBecomesEmpty() {
        let vm = LoginViewModel()
        vm.username = "user@acmebank.com"
        vm.password = "secret"
        XCTAssertTrue(vm.isSignInEnabled)
        vm.username = ""
        XCTAssertFalse(vm.isSignInEnabled, "Clearing username → disabled again")
    }

    // MARK: - errorMessage publishing

    func test_errorMessage_isNilByDefault() {
        let vm = LoginViewModel()
        XCTAssertNil(vm.errorMessage)
    }

    func test_errorMessage_publishesWhenSet() {
        let vm = LoginViewModel()
        let expectation = XCTestExpectation(description: "errorMessage published")
        var received: String? = nil

        vm.$errorMessage
            .dropFirst() // skip initial nil
            .sink { value in
                received = value
                expectation.fulfill()
            }
            .store(in: &cancellables)

        vm.errorMessage = "Incorrect username or password."

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(received, "Incorrect username or password.")
    }

    func test_errorMessage_publishesNilWhenCleared() {
        let vm = LoginViewModel()
        vm.errorMessage = "Some error"

        let expectation = XCTestExpectation(description: "errorMessage cleared")
        var received: String? = "sentinel"

        vm.$errorMessage
            .dropFirst() // skip "Some error"
            .sink { value in
                received = value
                expectation.fulfill()
            }
            .store(in: &cancellables)

        vm.errorMessage = nil

        wait(for: [expectation], timeout: 1.0)
        XCTAssertNil(received)
    }

    // MARK: - onSignIn closure

    func test_onSignIn_calledWithCorrectCredentials() {
        let vm = LoginViewModel()
        vm.username = "alice@acmebank.com"
        vm.password = "p@ssw0rd"

        var capturedUsername: String?
        var capturedPassword: String?
        let expectation = XCTestExpectation(description: "onSignIn called")

        vm.onSignIn = { user, pass in
            capturedUsername = user
            capturedPassword = pass
            expectation.fulfill()
        }

        vm.onSignIn(vm.username, vm.password)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(capturedUsername, "alice@acmebank.com")
        XCTAssertEqual(capturedPassword, "p@ssw0rd")
    }

    func test_onSignIn_defaultClosureDoesNotCrash() {
        // Default no-op closure must not throw or crash
        let vm = LoginViewModel()
        vm.onSignIn("user", "pass") // should be a silent no-op
    }
}
