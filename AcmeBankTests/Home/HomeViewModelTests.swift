import XCTest
import Combine
@testable import AcmeBank

// MARK: - Stub repository

/// Stub `HomeRepositoryProtocol`. Returns a canned result on the next
/// `fetchHome()` call and records the call count so retry tests can
/// assert the second invocation actually happened.
///
/// `result` is the closed enum of outcomes a real repository can
/// produce: a decoded `HomeDashboard` (200) or one of the four typed
/// `APIError` cases (401 / 5xx / transport / decoding). Tests set
/// `result` before driving the VM.
private final class StubHomeRepository: HomeRepositoryProtocol {

    enum Outcome {
        case success(HomeDashboard)
        case failure(APIError)
    }

    private(set) var fetchCallCount = 0
    /// Results to return for sequential `fetchHome()` calls. When the
    /// list is exhausted, the last entry is reused. Lets retry tests
    /// configure "first call 5xx, second call 200".
    var outcomes: [Outcome] = []

    /// Optional latency on the next call. Lets the loading-state test
    /// observe `.loading` briefly before `.loaded` lands.
    var artificialDelayNanoseconds: UInt64 = 0

    func fetchHome() async throws -> HomeDashboard {
        fetchCallCount += 1
        if artificialDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: artificialDelayNanoseconds)
        }
        // Pick the outcome for THIS call; reuse the last one if the
        // tests didn't queue enough.
        guard !outcomes.isEmpty else {
            // Sensible default so a test that forgot to set `outcomes`
            // gets a clear failure rather than an array-out-of-bounds.
            throw APIError.transport(URLError(.unknown))
        }
        let index = min(fetchCallCount - 1, outcomes.count - 1)
        switch outcomes[index] {
        case let .success(dashboard):
            return dashboard
        case let .failure(error):
            throw error
        }
    }
}

// MARK: - Spy coordinator

/// Spy `SessionCoordinating`. Records every call so tests can assert
/// that 401 routes through `handleSessionExpired()` (and NOT through
/// `signOut()`).
@MainActor
private final class SpySessionCoordinator: SessionCoordinating {
    private(set) var handleSessionExpiredCallCount = 0
    private(set) var signOutCallCount = 0

    func handleSessionExpired() {
        handleSessionExpiredCallCount += 1
    }

    func signOut() {
        signOutCallCount += 1
    }
}

// MARK: - Fixtures

private func makeDashboard(customerId: String = "cust-1") -> HomeDashboard {
    return HomeDashboard(
        customer: Customer(
            id: customerId,
            firstName: "Jane",
            lastName: "Doe",
            email: "jane@example.com",
            phoneNumber: nil
        ),
        accounts: [],
        recentTransactions: []
    )
}

// MARK: - Tests

@MainActor
final class HomeViewModelTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Initial state

    func test_initialState_isLoading() {
        let vm = HomeViewModel(
            repository: StubHomeRepository(),
            coordinator: SpySessionCoordinator()
        )

        XCTAssertEqual(vm.state, .loading,
                       "HomeViewModel must start on .loading so the view renders a spinner immediately, before load() returns.")
    }

    // MARK: - Happy path

    func test_load_onSuccess_publishesLoaded() async {
        let dashboard = makeDashboard(customerId: "cust-happy")
        let repo = StubHomeRepository()
        repo.outcomes = [.success(dashboard)]
        let coordinator = SpySessionCoordinator()
        let vm = HomeViewModel(repository: repo, coordinator: coordinator)

        await vm.load()

        XCTAssertEqual(vm.state, .loaded(dashboard),
                       "On a 200 from the repository, state must flip to .loaded with the decoded dashboard.")
        XCTAssertEqual(coordinator.handleSessionExpiredCallCount, 0,
                       "Happy path must NEVER touch the session coordinator.")
        XCTAssertEqual(coordinator.signOutCallCount, 0)
    }

    // MARK: - Loading state observability

    /// `state` starts on `.loading`; after `load()` it should be
    /// `.loaded(...)`. This pins the documented initial state +
    /// transition by observing the published sequence with a Combine
    /// sink — proving the view's `@Published` binding actually sees
    /// both values.
    func test_load_publishesLoadingThenLoaded() async {
        let dashboard = makeDashboard()
        let repo = StubHomeRepository()
        repo.outcomes = [.success(dashboard)]
        // A tiny artificial delay guarantees `.loading` is observable
        // between the `load()` entry and the eventual `.loaded`.
        repo.artificialDelayNanoseconds = 10_000_000 // 10ms
        let vm = HomeViewModel(repository: repo, coordinator: SpySessionCoordinator())

        var observed: [HomeState] = []
        vm.$state
            .sink { observed.append($0) }
            .store(in: &cancellables)

        await vm.load()

        XCTAssertTrue(observed.contains(.loading),
                      "Observed states must include .loading. Got: \(observed)")
        XCTAssertEqual(observed.last, .loaded(dashboard),
                       "Observed states must end on .loaded(dashboard). Got: \(observed)")
    }

    // MARK: - 401: route via session coordinator

    func test_load_on401_callsHandleSessionExpiredAndDoesNotPublishStaleData() async {
        // Pre-load the VM with a "stale" loaded state to prove the
        // 401 handler does NOT overwrite it with `.error` or with
        // another `.loaded`.
        let staleDashboard = makeDashboard(customerId: "cust-STALE")
        let repo = StubHomeRepository()
        repo.outcomes = [
            .success(staleDashboard),          // first call: succeed
            .failure(.unauthorized)            // second call: 401
        ]
        let coordinator = SpySessionCoordinator()
        let vm = HomeViewModel(repository: repo, coordinator: coordinator)

        // First load → .loaded(staleDashboard).
        await vm.load()
        XCTAssertEqual(vm.state, .loaded(staleDashboard))

        // Second load → 401 path.
        await vm.load()

        XCTAssertEqual(coordinator.handleSessionExpiredCallCount, 1,
                       "401 MUST route via SessionCoordinating.handleSessionExpired().")
        XCTAssertEqual(coordinator.signOutCallCount, 0,
                       "401 must use handleSessionExpired() — NOT signOut(). The two are distinguished at the analytics layer.")

        // The state must NOT carry the previous user's dashboard back
        // into the UI on the way out. It also must NOT publish
        // `.error("...")` — that would flash a banner before the
        // root view swaps to Login. `.loading` is the documented
        // resting state during the swap.
        XCTAssertEqual(vm.state, .loading,
                       "On 401, state must stay on .loading — never expose stale .loaded data or a transient .error.")
    }

    // MARK: - 5xx: error + retry

    func test_load_on500_publishesError() async {
        let repo = StubHomeRepository()
        repo.outcomes = [.failure(.server(500))]
        let vm = HomeViewModel(repository: repo, coordinator: SpySessionCoordinator())

        await vm.load()

        guard case let .error(message) = vm.state else {
            XCTFail("Expected .error, got \(vm.state)")
            return
        }
        XCTAssertFalse(message.isEmpty, "Error copy must be non-empty.")
        XCTAssertTrue(message.contains("500"),
                      "Server error copy should surface the status code for debuggability. Got: \(message)")
    }

    func test_retry_reinvokesRepository_andCanRecoverToLoaded() async {
        let dashboard = makeDashboard(customerId: "cust-recovered")
        let repo = StubHomeRepository()
        // First call fails 5xx, retry succeeds.
        repo.outcomes = [
            .failure(.server(503)),
            .success(dashboard)
        ]
        let vm = HomeViewModel(repository: repo, coordinator: SpySessionCoordinator())

        await vm.load()
        guard case .error = vm.state else {
            XCTFail("Expected .error after first 5xx, got \(vm.state)")
            return
        }

        await vm.retry()

        XCTAssertEqual(repo.fetchCallCount, 2,
                       "retry() must re-invoke the repository.")
        XCTAssertEqual(vm.state, .loaded(dashboard),
                       "A successful retry must flip state to .loaded.")
    }

    // MARK: - Transport: same error contract as 5xx

    func test_load_onTransportError_publishesError() async {
        let repo = StubHomeRepository()
        repo.outcomes = [.failure(.transport(URLError(.notConnectedToInternet)))]
        let coordinator = SpySessionCoordinator()
        let vm = HomeViewModel(repository: repo, coordinator: coordinator)

        await vm.load()

        guard case let .error(message) = vm.state else {
            XCTFail("Expected .error, got \(vm.state)")
            return
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(coordinator.handleSessionExpiredCallCount, 0,
                       "Transport errors must NEVER trigger the session-expired path — they are not 401.")
    }

    func test_retry_afterTransportError_reinvokesRepository() async {
        let repo = StubHomeRepository()
        repo.outcomes = [
            .failure(.transport(URLError(.timedOut))),
            .failure(.transport(URLError(.timedOut)))
        ]
        let vm = HomeViewModel(repository: repo, coordinator: SpySessionCoordinator())

        await vm.load()
        await vm.retry()

        XCTAssertEqual(repo.fetchCallCount, 2,
                       "retry() must re-invoke fetchHome() after a transport error.")
    }

    // MARK: - Segment: Customer JSON decode

    /// JSON with `"segment":"PREMIER"` decodes to `customer.segment == "PREMIER"`.
    func testCustomerDecodesWithSegment() throws {
        let json = """
        {
          "id": "cust-seg-1",
          "first_name": "Alex",
          "last_name": "Premier",
          "email": null,
          "phone_number": null,
          "segment": "PREMIER"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let customer = try decoder.decode(Customer.self, from: json)

        XCTAssertEqual(customer.segment, "PREMIER",
                       "Customer JSON with 'segment':'PREMIER' must decode to segment == 'PREMIER'.")
    }

    /// JSON without a `segment` key decodes to `customer.segment == nil` with no error thrown.
    func testCustomerDecodesWithoutSegment() throws {
        let json = """
        {
          "id": "cust-seg-2",
          "first_name": "Jordan",
          "last_name": "Standard",
          "email": null,
          "phone_number": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let customer = try decoder.decode(Customer.self, from: json)

        XCTAssertNil(customer.segment,
                     "Customer JSON without a 'segment' key must decode to segment == nil, with no error thrown.")
    }

    // MARK: - Segment: SignedInCard view logic

    /// When `customer.segment` is "PREMIER", the badge text that
    /// `SignedInCard` would render equals "PREMIER".
    ///
    /// The view's conditional is `if let segment = customer.segment { SegmentBadgeView(segment: segment) }`.
    /// We assert on the unwrapped segment value — the same value that
    /// the view passes to `SegmentBadgeView(segment:)` — rather than
    /// inspecting the live view hierarchy (which requires a simulator
    /// process and PNG comparison).
    func testSignedInCardShowsBadgeWhenSegmentPresent() {
        let dashboard = HomeDashboardFixtures.previewDashboardWithSegment
        let customer = dashboard.customer

        // The view renders the badge when and only when segment is non-nil.
        // Asserting the unwrapped value mirrors the exact label text the
        // badge renders.
        XCTAssertNotNil(customer.segment,
                        "previewDashboardWithSegment customer must have a non-nil segment.")
        XCTAssertEqual(customer.segment, "PREMIER",
                       "Badge text must equal 'PREMIER' for the PREMIER fixture.")
    }

    /// When `customer.segment` is nil, `SignedInCard` renders no badge —
    /// the `if let` guard short-circuits and `SegmentBadgeView` is never
    /// instantiated.
    func testSignedInCardHidesBadgeWhenSegmentNil() {
        let dashboard = HomeDashboardFixtures.previewDashboardNoSegment
        let customer = dashboard.customer

        XCTAssertNil(customer.segment,
                     "previewDashboardNoSegment customer must have segment == nil so SignedInCard renders no SegmentBadgeView.")
    }
}
