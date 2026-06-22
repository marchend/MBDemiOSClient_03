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
  Info.plist                    # Committed plist with __*_UNSET__ defaults for Okta keys (implemented)
  Sources/
    Auth/
      OktaConfig.swift          # Runtime view of injected Okta tenant config (implemented)
  Core/
    Auth/                       # AuthService, KeychainStore, UserSession (deferred)
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
    Login/                      # LoginView, LoginViewModel, LoginCoordinator (deferred)
    Home/                       # HomeView, HomeViewModel, HomeCoordinator (deferred)
    Accounts/                   # (deferred)
    Transfer/                   # (deferred)
    Cards/                      # (deferred)
  DesignSystem/                 # Colors.swift, Typography.swift (deferred)
  Resources/                    # Assets.xcassets, PrivacyInfo.xcprivacy (stub implemented)
AcmeBankTests/                  # XCTest unit tests
AcmeBankUITests/                # XCUITest critical-flow tests
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

### Authentication — Okta OIDC (deferred — future PR)
- `AuthService` implements `signIn()`, `signOut()`, `refreshTokenIfNeeded()`.
- Tokens persisted to Keychain via `KeychainStore`.
- `UserSession` value type passed through coordinators; never stored in `UserDefaults` or as a global singleton.
- `RequestInterceptor` calls `refreshTokenIfNeeded()` before every request; on failure posts `AppNotification.sessionExpired`.

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

### Keychain + CI Note (implemented — entitlements stub in this PR)
Any Keychain query MUST include `kSecUseDataProtectionKeychain: true`. This is required
for CI (`CODE_SIGNING_ALLOWED=NO` simulator) — without this flag `SecItem*` returns
`errSecMissingEntitlement` (-34018) even though the entitlements file is present.

## Deferred Work
- Okta OIDC authentication (`AuthService`, `KeychainStore`, `UserSession`) — future PR (PR 1 ships the config plumbing only)
- Login screen (`LoginView`, `LoginViewModel`, `LoginCoordinator`) — future PR
- Home Dashboard + BFF integration (`HomeView`, `HomeViewModel`, `HomeCoordinator`) — future PR
- MVVM + Coordinator wiring (`AppCoordinator`, `RootView`, `TabBarCoordinator`) — future PR
- Networking layer (`APIClient`, `APIRouter`, `APIError`, `RequestInterceptor`) — future PR
- Domain models (`Account`, `Transaction`, `Customer`, `TransferRequest`) — future PR
- Repository protocols + Mock/API implementations — future PR
- Design system (`Colors.swift`, `Typography.swift`) — future PR
- Internal notifications (`AppNotification`, `NotificationPublisher`) — future PR
- Transfer, Cards, Accounts, Bills features — future PRs
- SwiftLint config (`.swiftlint.yml`) — future PR
- CI workflow (`ios-build.yml`, xcconfig, `-warnings-as-errors`) — future PR
- XCUITest critical-flow tests — future PRs

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
