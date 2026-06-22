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

    func test_isSignInEnabled_falseWhenUsernameIsWhitespaceOnly() {
        let vm = LoginViewModel()
        vm.username = "   "
        vm.password = "secret"
        XCTAssertFalse(vm.isSignInEnabled, "Whitespace-only username → disabled")
    }

    func test_isSignInEnabled_trueWhenPasswordContainsSpaces() {
        // Spaces in passwords are intentional and must not be trimmed.
        let vm = LoginViewModel()
        vm.username = "user@acmebank.com"
        vm.password = "my secret pass"
        XCTAssertTrue(vm.isSignInEnabled, "Password with spaces → enabled")
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

    // MARK: - signIn() method

    func test_signIn_callsOnSignInWithCredentials() {
        let vm = LoginViewModel()
        vm.username = "bob@acmebank.com"
        vm.password = "hunter2"

        var capturedUsername: String?
        var capturedPassword: String?
        let expectation = XCTestExpectation(description: "signIn forwards credentials")

        vm.onSignIn = { user, pass in
            capturedUsername = user
            capturedPassword = pass
            expectation.fulfill()
        }

        vm.signIn()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(capturedUsername, "bob@acmebank.com")
        XCTAssertEqual(capturedPassword, "hunter2")
    }

    func test_signIn_clearsPasswordAfterCall() {
        let vm = LoginViewModel()
        vm.username = "bob@acmebank.com"
        vm.password = "hunter2"

        let expectation = XCTestExpectation(description: "password cleared after signIn")
        vm.onSignIn = { _, _ in }

        vm.$password
            .dropFirst() // skip initial "hunter2"
            .sink { value in
                if value == "" { expectation.fulfill() }
            }
            .store(in: &cancellables)

        vm.signIn()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(vm.password, "", "password must be cleared after signIn()")
    }

    func test_signIn_usernameIsNotCleared() {
        // Username should remain so the user can re-attempt without re-typing.
        let vm = LoginViewModel()
        vm.username = "bob@acmebank.com"
        vm.password = "hunter2"
        vm.onSignIn = { _, _ in }

        vm.signIn()

        XCTAssertEqual(vm.username, "bob@acmebank.com", "username must not be cleared after signIn()")
    }
}
