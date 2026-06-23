import SwiftUI

/// Top-level Home screen.
///
/// Switches on `HomeState`:
///   - `.loading`  -> centred progress indicator,
///   - `.loaded`   -> brand bar + greeting + signed-in card +
///                    accounts section + transactions section,
///   - `.error`    -> inline error label + Retry button bound to
///                    `viewModel.retry()`.
///
/// The Log out button is pinned at the BOTTOM of the screen as a
/// fixed footer; the content above scrolls. We achieve that with a
/// root `VStack` whose top child is a `ScrollView` and whose bottom
/// child is `LogOutButton`. The `Spacer` lives INSIDE the ScrollView
/// content for the loading / error states so those states' content
/// is vertically centred above the pinned footer.
///
/// Accessibility identifiers required by PR 4's XCUITest:
///   - `"home.screen"`            on the root container,
///   - `"home.logout"`            on the Log out button,
///   - `"home.accounts.list"`     on the accounts list container,
///   - `"home.account.row.<i>"`   on each account row.
///
/// IMPORTANT: per the SwiftUI accessibility-tree rule, a container
/// that owns an accessibility identifier flattens its children's
/// elements. So `"home.screen"` is applied to the OUTERMOST root only;
/// the inner accounts list manages its own subtree with
/// `accessibilityElement(children: .contain)` so PR 4's queries for
/// `home.account.row.<index>` keep working.
struct HomeView: View {
    @StateObject var viewModel: HomeViewModel

    /// The coordinator powering the Log out button. Separate from
    /// the view model's `coordinator` only so the button's call site
    /// reads explicitly (`coordinator.signOut()`). In practice this
    /// is the same reference - both are the app's `AppCoordinator`.
    let coordinator: SessionCoordinating

    init(viewModel: HomeViewModel, coordinator: SessionCoordinating) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.coordinator = coordinator
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .padding(.bottom, 24)
            }

            LogOutButton(coordinator: coordinator)
                .accessibilityIdentifier("home.logout")
        }
        .background(BankPalette.background.ignoresSafeArea())
        .task {
            await viewModel.load()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.screen")
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            loadingView
        case let .loaded(dashboard):
            loadedView(dashboard: dashboard)
        case let .error(message):
            errorView(message: message)
        }
    }

    // MARK: - Loading state

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading your accounts\u{2026}")
                .font(.subheadline)
                .foregroundStyle(BankPalette.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .center)
        .padding(.top, 80)
    }

    // MARK: - Loaded state

    private func loadedView(dashboard: HomeDashboard) -> some View {
        // The transactions section needs a currency code; we use the
        // first account's currency. If the dashboard somehow has no
        // accounts we fall back to "USD" rather than crashing - the
        // transactions section will only render its empty-state in
        // that case anyway.
        let currencyCode = dashboard.accounts.first?.currencyCode ?? "USD"

        return VStack(alignment: .leading, spacing: 16) {
            BrandBar()
            GreetingHeader(firstName: dashboard.customer.firstName)
            SignedInCard(customer: dashboard.customer)
            AccountsSection(accounts: dashboard.accounts)
            TransactionsSection(
                transactions: dashboard.recentTransactions,
                currencyCode: currencyCode
            )
        }
    }

    // MARK: - Error state

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(BankPalette.primaryText)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(BankPalette.primaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                Task { await viewModel.retry() }
            } label: {
                Text("Retry")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BankPalette.onNavy)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(BankPalette.navy)
                    )
            }
            .accessibilityIdentifier("home.error.retry")
        }
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .center)
        .padding(.top, 80)
    }
}
