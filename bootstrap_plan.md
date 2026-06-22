# Bootstrap Plan — AcmeBank iOS

## In scope (this PR)

### Project name + tech stack decisions
- **App name:** AcmeBank
- **Platform:** iOS 17+, Swift 5.10, SwiftUI
- **Architecture:** MVVM + Coordinator (planned; scaffold only shows entry point)
- **Project file:** XcodeGen (`project.yml`) — never hand-crafted `.xcodeproj`
- **Test runner:** XCTest (unit), XCUITest (UI) — wired in `project.yml`
- **Bundle ID:** `com.acmebank.mobile`
- **Minimum Xcode:** 16.0

### Directory structure (Hello World only)
```
AcmeBank/
├── App/
│   └── AcmeBankApp.swift        # @main SwiftUI entry point
├── ContentView.swift             # Hello World placeholder view
└── Resources/
    └── Assets.xcassets/
        ├── Contents.json
        └── AppIcon.appiconset/
            └── Contents.json
AcmeBankTests/
└── AcmeBankTests.swift          # One trivial unit test
AcmeBankUITests/
└── AcmeBankUITests.swift        # One trivial UI test stub
AcmeBank/
└── AcmeBank.entitlements        # Keychain access group stub
AcmeBank/
└── PrivacyInfo.xcprivacy        # Privacy manifest stub
project.yml                      # XcodeGen spec
.gitignore                       # iOS/XcodeGen ignores
setup.sh                         # One-shot project materialisation
CLAUDE.md                        # Project docs for AI agents
AGENT.md                         # (identical to CLAUDE.md)
README.md                        # Human-facing quick-start
bootstrap_plan.md                # This file
```

### Files this PR creates
| File | Purpose |
|------|---------|
| `project.yml` | XcodeGen spec — generates AcmeBank.xcodeproj |
| `AcmeBank/App/AcmeBankApp.swift` | @main SwiftUI entry point showing "AcmeBank" |
| `AcmeBank/ContentView.swift` | Placeholder view with project name text |
| `AcmeBank/Resources/Assets.xcassets/Contents.json` | Asset catalog metadata |
| `AcmeBank/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` | AppIcon stub (prevents actool error) |
| `AcmeBank/AcmeBank.entitlements` | Keychain access group stub |
| `AcmeBank/PrivacyInfo.xcprivacy` | Privacy manifest (UserDefaults reason) |
| `AcmeBankTests/AcmeBankTests.swift` | One unit test — proves test runner links |
| `AcmeBankUITests/AcmeBankUITests.swift` | One UI test — proves UI test target compiles |
| `.gitignore` | iOS/XcodeGen/macOS ignores |
| `setup.sh` | Installs XcodeGen, runs generate, opens Xcode |
| `CLAUDE.md` | Full project context for AI agents |
| `AGENT.md` | Identical copy of CLAUDE.md |
| `README.md` | Human-facing quick-start |

### How to run locally
```bash
./setup.sh          # installs xcodegen if needed, generates .xcodeproj, opens Xcode
# or manually:
brew install xcodegen
xcodegen generate
open AcmeBank.xcodeproj
```

### How to run tests
```bash
xcodebuild test \
  -scheme AcmeBank \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO
```

### Definition of Hello World
App launches in the iOS Simulator and shows a single screen with the text **"AcmeBank"** centred on a white background. One unit test (`test_contentView_initializes`) passes, proving the test runner links against the app module. One UI test stub compiles and passes.

---

## Out of scope — deferred to future work

- **Okta OIDC Authentication** (`AuthService`, `KeychainStore`, `UserSession`, `Okta.plist`) — future PR
- **Login screen** (`LoginView`, `LoginViewModel`, `LoginCoordinator`) — future PR
- **Home Dashboard screen** (`HomeView`, `HomeViewModel`, `HomeCoordinator`, BFF integration) — future PR
- **MVVM + Coordinator pattern** (`AppCoordinator`, `RootView`, `TabBarCoordinator`) — future PR
- **Networking layer** (`APIClient`, `APIRouter`, `APIError`, `RequestInterceptor`) — future PR
- **Domain models** (`Account`, `Transaction`, `Customer`, `TransferRequest`) — future PR
- **Repository protocols** (`AccountRepositoryProtocol`, `TransactionRepositoryProtocol`, etc.) — future PR
- **Mock data layer** (`MockAccountRepository`, `MockTransactionRepository`, etc.) — future PR
- **Design system** (`Colors.swift`, `Typography.swift`, full `Assets.xcassets`) — future PR
- **Internal notifications** (`AppNotification`, `NotificationPublisher`, `NotificationKey`) — future PR
- **Transfer, Cards, Accounts, Bills features** — future PRs
- **SwiftLint configuration** (`.swiftlint.yml`) — future PR
- **CI workflow** (`ios-build.yml`, xcconfig, `-warnings-as-errors`) — future PR
- **XCUITest critical flows** (Login, Transfer, Sign-out) — future PRs
- **`PrivacyInfo.xcprivacy` expansion** for file timestamps, disk space APIs — future PRs
- **`Okta.plist.example`** config template — future PR (Okta story)
