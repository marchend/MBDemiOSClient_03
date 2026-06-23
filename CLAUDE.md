# AcmeBank iOS — Project Context

## Overview
AcmeBank is an iOS 17+ banking app (Swift 5.10 / SwiftUI) for Acme Bank customers.
It provides account overview, fund transfers, bill payments, and card management,
secured via Okta OIDC authentication. This repo ships the Hello-World scaffold today;
feature stories layer on the real functionality.

## Tech Stack
| Layer | Choice |
|-------|--------|
| Platform | iOS 17+, Xcode 16+ |
| Language | Swift 5.10 |
| UI Framework | SwiftUI |
| Architecture | MVVM + Coordinator (`NavigationStack`) |
| Auth | Okta OIDC — `okta-mobile-swift` 2.x |
| Networking | `URLSession` + async/await |
| Dependency Injection | Constructor injection (no service locator) |
| Notifications | `NotificationCenter` with typed wrappers |
| Project file | XcodeGen `project.yml` (never hand-edit `.pbxproj`) |
| Test runner | XCTest (unit) + XCUITest (UI) |

## How to Run Locally
```bash
./setup.sh          # installs xcodegen if needed, generates .xcodeproj, opens Xcode
# Manual fallback:
brew install xcodegen && xcodegen generate && open AcmeBank.xcodeproj
```

## How to Run Tests
```bash
xcodebuild test \
  -scheme AcmeBank \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO
```

## Key Directory Structure
```
project.yml                     # XcodeGen spec — source of truth for the Xcode project
setup.sh                        # one-shot post-clone materialisation script
Scripts/
  inject_okta_config.sh         # Run Script build phase: OKTA_* env vars → Info.plist (implemented)
AcmeBank/
  App/                          # @main entry point (implemented)
  ContentView.swift             # Hello World placeholder (implemented)
  Info.plist                    # Committed plist with __*_UNSET__ defaults for Okta keys + API_BASE_URL (implemented)
  Home/                         # Home dashboard feature (implemented)
    Models/                     # HomeDashboard, Customer, Account, Transaction (wire-contract Codables)
    Repository/                 # HomeRepositoryProtocol seam + BFFHomeRepository + APIError
    ViewModel/                  # HomeViewModel, HomeState
    View/                       # HomeView + Components/ (BrandBar, GreetingHeader, AccountsSection, …)
  Sources/
    AcmeBankApp.swift           # @main composition root; injects AppCoordinator into env (implemented)
    Auth/
      OktaConfig.swift          # Runtime view of injected Okta tenant config (implemented)
      UserSession.swift         # Codable value type — six fields, NO refresh token (implemented)
      IDTokenClaims.swift       # JWT-payload base64URL decoder (implemented)
      AuthResult.swift          # Closed enum — success / invalidCredentials / networkError / mfaUnsupported / notConfigured (implemented)
      OktaAuthService.swift     # DirectAuthenticating + LiveDirectAuthDriver (only file importing OktaDirectAuth) (implemented)
      KeychainStore.swift       # SecItem* wrappers, kSecUseDataProtectionKeychain on every query (implemented)
      AuthCoordinator.swift     # Orchestrates OktaAuthService + KeychainStore; keepSignedIn gate (implemented)
    App/
      AppCoordinator.swift      # Owns `@Published session`; handleSignIn / signOut / signIn(AuthCoordinating) (implemented)
    Landing/
      LandingView.swift         # Post-sign-in landing — "Welcome, <displayName>" (implemented)
    Login/
      LoginView.swift           # Sign-in form; pulls AppCoordinator via @EnvironmentObject (implemented PR 4)
      LoginViewModel.swift      # ObservableObject; injected AuthCoordinating; signIn → UserSession? (implemented PR 4)
      ErrorBannerView.swift     # Inline error banner; hidden when message is nil/empty (implemented PR 4)
      HexagonLogoView.swift     # Decorative logo used by LoginView (implemented)
  Core/
    Networking/                 # APIClient, APIRouter, APIError, RequestInterceptor (deferred)
    Notifications/              # AppNotification, NotificationPublisher (deferred)
    Extensions/                 # Decimal+Currency, Date+Greeting, String+Initials (deferred)
  Domain/
    Models/                     # Account, Transaction, Customer, TransferRequest (deferred)
    Repositories/               # Protocol-only interfaces (deferred)
  Data/
    Remote/                     # APIRepository implementations (deferred)
    Mock/                       # MockRepository implementations (deferred)
  Features/
    Accounts/                   # (deferred)
    Transfer/                   # (deferred)
    Cards/                      # (deferred)
  DesignSystem/                 # Colors.swift, Typography.swift (deferred)
  Resources/                    # Assets.xcassets, PrivacyInfo.xcprivacy (stub implemented)
AcmeBankTests/                  # XCTest unit tests
AcmeBankUITests/                # XCUITest critical-flow tests
  SignInToLandingUITests.swift  # End-to-end Okta sign-in → Landing; XCTSkipUnless OKTA_ISSUER (implemented PR 4)
  HomeLogoutUITests.swift       # Login → Home → Log out → Login → second user → Home (implemented)
  Support/
    LiveBFFSmokeTest.swift      # Developer-only live GET /v1/home; gated by RUN_LIVE_BFF_SMOKE=1 (implemented)
```

## Planned Architecture

### MVVM + Coordinator (deferred — future PR)
- **View**: SwiftUI `View` struct; zero business logic; renders ViewModel `@Published` state.
- **ViewModel**: `final class: ObservableObject`; owns `@Published` state; calls repositories; posts `AppNotification`s; imports no SwiftUI types.
- **Coordinator**: `ObservableObject` owning the `NavigationStack` path; creates Views + ViewModels; injects dependencies; drives all navigation declaratively.
- **Repository protocol** in `Domain/`; concrete implementations in `Data/`.

### Coordinator Tree (deferred — future PR)
```
AppCoordinator  ← observed by RootView
  ├── LoginCoordinator    (full-screen when no session)
  └── TabBarCoordinator   (root TabView after login)
        ├── HomeCoordinator
        ├── TransferCoordinator
        ├── CardsCoordinator
        └── MoreCoordinator
```

### Auth layer — Okta plumbing (implemented in PR 1)
- `AcmeBank/Sources/Auth/OktaConfig.swift` is the single runtime entry point for
  Okta tenant values. It reads `Bundle.main.infoDictionary` and returns
  `.configured(issuer:clientID:redirectURI:scopes:)` or
  `.notConfigured(reason:)` — never crashes, never force-unwraps.
- The four values reach the `Info.plist` via `Scripts/inject_okta_config.sh`, a
  Run Script build phase wired in `project.yml` BEFORE `Compile Sources`. The
  script `plutil -replace`s each key with the matching env var, falling back to
  a `__<NAME>_UNSET__` sentinel when the env var is empty so `xcodebuild` still
  succeeds on a fresh clone with no secrets.
- **Env-var contract** (set in the shell that launches Xcode — see README):
  `OKTA_ISSUER`, `OKTA_CLIENT_ID`, `OKTA_REDIRECT_URI`, `OKTA_SCOPES`.
- Reminder for future agents: `PhaseScriptExecution` subshells inherit only the
  env of the process that launched Xcode. Don't add an xcconfig `$(VAR)`
  reference — it would chain build settings, not shell env, and silently ship
  empty values. Keep the Run Script as the single injection point.
- UI-test runners are a separate process and their `Bundle.main` is the test
  runner bundle, not the app bundle. A test that wants to gate on "is Okta
  wired up?" must probe `ProcessInfo.processInfo.environment` directly, not
  call `OktaConfig.load()` from the UI-test target.

### Authentication — Okta OIDC (implemented in PR 2 — headless layer)
- `OktaAuthService` is the only file that imports `OktaDirectAuth`. It exposes
  the SDK-agnostic `DirectAuthenticating` protocol and an internal
  `DirectAuthFlowDriver` seam returning the neutral `RawDirectAuthOutcome`
  enum — so unit tests stub the driver without importing the SDK and SDK
  version churn is contained to one file.
- `OktaAuthService` calls `DirectAuthenticationFlow.start(username, with: .password(password))`
  verbatim — positional username, `with:` factor, NO `.primary` wrapper.
- `UserSession` is a `Codable` value type with exactly six fields
  (`userId`, `displayName`, `email`, `accessToken`, `authTimestamp`,
  `deviceName`) and NO refresh token. The refresh token lives in the
  Keychain and travels separately through `AuthResult.success(_, refreshToken:)`.
- `AuthCoordinator` short-circuits to `.notConfigured` when `OktaConfig.load()`
  is `.notConfigured`, delegates to `OktaAuthService`, and on `.success`
  persists tokens via `KeychainStore`. Keychain writes are CACHE: a failure
  is logged and swallowed and does NOT invalidate the sign-in the IdP just
  accepted.

### Login UI wiring (implemented in PR 4)
- `LoginView` is the only consumer of `LoginViewModel`; both files are owned by
  the Login PR and edited as a unit.
- `LoginViewModel` is constructed with an injected `AuthCoordinating`. Its
  `signIn(username:password:keepSignedIn:) async -> UserSession?` sets
  `isSigningIn`, calls the coordinator, maps the four `AuthResult` cases to
  exact user-facing copy via `errorMessage`, and returns the decoded session
  on success.
- `LoginView` pulls `AppCoordinator` via `@EnvironmentObject` (registered by
  `AcmeBankApp`) and on a non-nil signIn return calls
  `appCoordinator.handleSignIn(session)`. There is exactly ONE navigation
  mechanism — the `AppCoordinator.@Published session` flip — and PR 4 must
  never invent a second one (no manual root-view swap, no NavigationLink,
  no NotificationCenter post for the sign-in transition).
- `ErrorBannerView` renders nothing when `message` is nil or empty; otherwise
  a light-red row with `exclamationmark.triangle.fill`. Banner clears via
  `LoginViewModel.onFieldEdit()` on the next keystroke in either field.

### Home dashboard (implemented)
- The screen lives in `AcmeBank/Home/` — `Models/` for the BFF wire-contract
  Codables (`HomeDashboard`, `Customer`, `Account`, `Transaction`),
  `Repository/` for the `HomeRepositoryProtocol` seam and its production
  `BFFHomeRepository`, `ViewModel/` for `HomeViewModel` + `HomeState`, and
  `View/` for `HomeView` + the per-section `Components/`.
- `HomeViewModel` depends ONLY on `HomeRepositoryProtocol`; that's the seam.
  Unit tests inject a fixture-backed stub; the production composition root
  injects `BFFHomeRepository`. Never wire a fixture repo on the happy path.
- `BFFHomeRepository` reads `API_BASE_URL` from the app bundle's `Info.plist`
  (the `API_BASE_URL` key). The value is injected by CI / a build script and
  is NEVER hardcoded in source. The convenience init returns `nil` when the
  key is missing or malformed so the coordinator can surface a configuration
  error instead of force-unwrapping.
- **No colours outside `BankPalette`.** Every `foregroundStyle`, `fill`, and
  `background` in `Home/` must resolve through `BankPalette` (navy / white /
  greys). Amounts are monochrome — NO semantic red/green. New components in
  `Home/View/Components/` must follow the same rule; a hardcoded
  `.red` / `.green` / system colour anywhere under `Home/` is a review-block.
- Home accessibility identifiers (consumed by `HomeLogoutUITests`):
  `home.screen` (root), `home.logout` (footer button), `home.accounts.list`
  (accounts section container), `home.account.row.<index>` (per row),
  `home.error.retry` (error-state Retry button).

### Networking Layer (deferred — future PR)
- `APIClient` wraps `URLSession`; decodes with `.convertFromSnakeCase` + `.iso8601`.
- `APIRouter` enum expresses every endpoint with path, method, body, queryItems.
- `API_BASE_URL` read from `Info.plist` (injected by CI xcconfig — never hardcoded).

### Design System (deferred — future PR)
- **Strictly monochrome**: navy + white + greys only — no semantic red/green for amounts.
- `Color.acmeNavy`, `.acmeBackground`, `.acmeSurface`, `.acmeText`, `.acmeSubtext`.
- `Font.acmeTitle`, `.acmeHeadline`, `.acmeBody`, `.acmeCaption`, `.acmeMonoBalance`.
- All fonts support Dynamic Type.

### Internal Notifications (deferred — future PR)
- `AppNotification` typed `Notification.Name` constants (e.g. `.sessionExpired`, `.transferCompleted`).
- `NotificationPublisher.post(_:userInfo:)` used everywhere; no magic strings.
- Subscriptions live in coordinators only — never inside ViewModels.

### Testing Conventions (deferred — future PR)
- **XCTest**: every ViewModel has a `*Tests.swift`; ≥80% line coverage on `Core/` and `Features/`.
- **XCUITest**: critical flows only (Login, Transfer, Sign-out); use accessibility identifiers, not visible text.
- Mock repositories injected via constructor; `XCUIApplication().launchArguments += ["-UITestMode", "YES"]` for UI tests.
- End-to-end XCUITests that need real Okta credentials gate with
  `XCTSkipUnless(ProcessInfo.processInfo.environment["OKTA_ISSUER"]?.isEmpty == false, ...)`
  in `setUpWithError` and forward the `OKTA_*` vars to `app.launchEnvironment` so
  the simulator process sees them too.
- Live-network smoke checks (e.g. `AcmeBankUITests/Support/LiveBFFSmokeTest.swift`)
  must be gated by an opt-in env var (`RUN_LIVE_BFF_SMOKE=1`) so CI never hits
  the live BFF; developers run them locally before closing the story.

### Keychain + CI Note (implemented — entitlements stub in this PR)
Any Keychain query MUST include `kSecUseDataProtectionKeychain: true`. This is required
for CI (`CODE_SIGNING_ALLOWED=NO` simulator) — without this flag `SecItem*` returns
`errSecMissingEntitlement` (-34018) even though the entitlements file is present.
`KeychainStore.baseQuery(for:)` is the single building block every operation goes
through, so the flag is present by construction.

## Deferred Work
- Token refresh (`AuthService.refreshTokenIfNeeded`, `RequestInterceptor`, `AppNotification.sessionExpired`) — future PR
- Networking layer (`APIClient`, `APIRouter`, `APIError`, `RequestInterceptor`) — future PR
- Domain models (`Account`, `Transaction`, `Customer`, `TransferRequest`) — future PR
- Repository protocols + Mock/API implementations — future PR
- Design system (`Colors.swift`, `Typography.swift`) — future PR
- Internal notifications (`AppNotification`, `NotificationPublisher`) — future PR
- Transfer, Cards, Accounts, Bills features — future PRs
- SwiftLint config (`.swiftlint.yml`) — future PR
- CI workflow (`ios-build.yml`, xcconfig, `-warnings-as-errors`) — future PR

## Git Workflow

> **Default PR target branch: `develop`.** Every feature/refactor/docs PR
> opens against `develop`. PRs are only opened against `qa`, `uat`, or
> `main` for explicit promotion PRs.

**Branch model (`develop` → `qa` → `uat` → `main`):**

| Branch  | Role                                 | Receives PRs from              | Promotes to |
|---------|--------------------------------------|--------------------------------|-------------|
| develop | Default integration branch           | feature branches               | qa          |
| qa      | First quality gate                   | develop (promotion PR)         | uat         |
| uat     | Pre-prod acceptance                  | qa (promotion PR)              | main        |
| main    | Production / release tags            | uat (promotion PR)             | tagged only |

All feature PRs MUST target `develop`. Never open a feature PR against
`qa`, `uat`, or `main`. Promotions happen via dedicated promotion PRs.
