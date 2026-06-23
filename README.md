# AcmeBank iOS

iOS 17+ banking app built with Swift 5.10 and SwiftUI.

## Quick Start

```bash
./setup.sh
```

This installs [XcodeGen](https://github.com/yonaskolb/XcodeGen) if needed,
generates `AcmeBank.xcodeproj` from `project.yml`, and opens the project in Xcode.

**Manual fallback** (for environments that block shell scripts):
```bash
brew install xcodegen
xcodegen generate
open AcmeBank.xcodeproj
```

## Running Tests

```bash
xcodebuild test \
  -scheme AcmeBank \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO
```

## Okta build configuration

The Okta tenant values are NEVER committed and NEVER written to the
source `AcmeBank/Info.plist`. They are read from four shell environment
variables at build time and written into the **built-product copy** of
`Info.plist` (inside `$BUILT_PRODUCTS_DIR`, which lives under
`DerivedData` and is git-ignored) by the `Scripts/inject_okta_config.sh`
Run Script build phase. The source `AcmeBank/Info.plist` is checked in
with `__<NAME>_UNSET__` sentinel values for the four Okta keys and is
never mutated by the build; this means a developer can never
accidentally commit live tenant credentials via `git add -A` or Xcode's
"Commit All". The app reads the injected values at runtime via
`OktaConfig.load()`.

| Env var              | Info.plist key      | Example                                       |
|----------------------|---------------------|-----------------------------------------------|
| `OKTA_ISSUER`        | `OktaIssuer`        | `https://acme.okta.com/oauth2/default`        |
| `OKTA_CLIENT_ID`     | `OktaClientID`      | `0oaXXXXXXXXXXXXXXXXX`                        |
| `OKTA_REDIRECT_URI`  | `OktaRedirectURI`   | `com.acmebank.mobile:/callback`               |
| `OKTA_SCOPES`        | `OktaScopes`        | `openid profile offline_access`               |

If any of these is unset, the build still succeeds — the script writes a
`__<NAME>_UNSET__` sentinel into the built plist and `OktaConfig.load()`
returns `.notConfigured(reason:)` at runtime so the auth layer can gate
sign-in without crashing.

The Run Script phase is registered as a **post-build script** in
`project.yml` so it runs AFTER Xcode's standard "Process Info.plist"
step has produced the built copy in `$BUILT_PRODUCTS_DIR/$INFOPLIST_PATH`
and BEFORE code signing.

### Three ways to make Xcode see the env vars

Xcode's `PhaseScriptExecution` runs each build-phase script in a fresh
non-interactive subshell. That subshell inherits the environment of the
**process that launched Xcode**, NOT the variables you exported in a
random Terminal tab afterwards. Pick the recipe that matches how you
start Xcode:

**1. Finder-launched Xcode (double-click `.xcodeproj` from Finder, or
launch Xcode from the Dock):** use `launchctl setenv` so the per-user
launchd domain (the parent of Finder-launched GUI apps) exports the var:

```bash
launchctl setenv OKTA_ISSUER       "https://acme.okta.com/oauth2/default"
launchctl setenv OKTA_CLIENT_ID    "0oaXXXXXXXXXXXXXXXXX"
launchctl setenv OKTA_REDIRECT_URI "com.acmebank.mobile:/callback"
launchctl setenv OKTA_SCOPES       "openid profile offline_access"
# then fully quit + relaunch Xcode for the new launchd env to take effect
```

**2. Shell-launched Xcode (`xed .` / `open AcmeBank.xcodeproj` from a
terminal):** export in your `~/.zshrc` (or `~/.bash_profile`) so every
new shell — and any Xcode launched from it — inherits them:

```bash
# ~/.zshrc
export OKTA_ISSUER="https://acme.okta.com/oauth2/default"
export OKTA_CLIENT_ID="0oaXXXXXXXXXXXXXXXXX"
export OKTA_REDIRECT_URI="com.acmebank.mobile:/callback"
export OKTA_SCOPES="openid profile offline_access"
```

```bash
source ~/.zshrc
xed .   # Xcode inherits the shell's env vars
```

**3. Per-command `xcodebuild` (CI, scripted local builds):** prefix the
invocation so the vars only live for that one process:

```bash
OKTA_ISSUER="$OKTA_ISSUER" \
OKTA_CLIENT_ID="$OKTA_CLIENT_ID" \
OKTA_REDIRECT_URI="$OKTA_REDIRECT_URI" \
OKTA_SCOPES="$OKTA_SCOPES" \
xcodebuild build \
  -scheme AcmeBank \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO
```

> **Why this matters:** `PhaseScriptExecution` subshells do NOT inherit
> job-level env vars from arbitrary processes. They inherit only what
> Xcode itself was launched with. A common pitfall is exporting vars in
> Terminal *after* Xcode is already running and expecting them to reach
> the build script — they will not. Either restart Xcode after exporting
> (recipes 1 + 2), or pass the vars per-invocation on the command line
> (recipe 3).

## Running against a live BFF

The Home dashboard fetches `GET /v1/home` from the URL stored under the
`API_BASE_URL` key in the app's built `Info.plist`. The committed
`AcmeBank/Info.plist` ships with a placeholder; a real BFF URL is wired
in one of two ways:

1. **Edit the value into your local `Info.plist`** (or override it via
   an xcconfig that sets `API_BASE_URL`) — the `BFFHomeRepository`
   convenience init reads `bundle.object(forInfoDictionaryKey:
   "API_BASE_URL")` at app start. Never commit a real URL into the
   source plist; treat it the same way as the `OKTA_*` env vars.
2. **Inject it from CI** the same way the `OKTA_*` script does — by
   `plutil -replace`ing the key in `$BUILT_PRODUCTS_DIR/$INFOPLIST_PATH`
   after "Process Info.plist" runs.

### Gated live-BFF smoke test

`AcmeBankUITests/Support/LiveBFFSmokeTest.swift` performs a REAL
`GET /v1/home` against the configured `API_BASE_URL` using a real Okta
access token, and asserts the response decodes into the
`HomeDashboard` shape with at least one account. This is the verifier
to run **before calling the Home story done** — unit tests use
fixtures, XCUITests use the UI, but only this test confirms that the
deployed BFF still matches the wire contract the app expects.

The test is **skipped by default** so CI never hits the live BFF.
Opt in by setting `RUN_LIVE_BFF_SMOKE=1`, along with `API_BASE_URL`
and a real Okta access token:

```bash
RUN_LIVE_BFF_SMOKE=1 \
API_BASE_URL="https://bff.example.com" \
OKTA_ACCESS_TOKEN="<paste-a-live-token>" \
xcodebuild test \
  -scheme AcmeBank \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:AcmeBankUITests/LiveBFFSmokeTest \
  CODE_SIGNING_ALLOWED=NO
```

Obtain `OKTA_ACCESS_TOKEN` out-of-band — e.g. with the Okta CLI, with
a `curl` against your tenant's `/v1/token` endpoint, or by signing
into the app once and reading the token from the Keychain. The token
is read from the test runner's `ProcessInfo.environment`; it is never
committed and never written into any plist.

## Project Structure

| Path | Description |
|------|-------------|
| `project.yml` | XcodeGen spec — source of truth for the Xcode project |
| `Scripts/inject_okta_config.sh` | Build-phase script that bridges `OKTA_*` env vars → the built Info.plist in `$BUILT_PRODUCTS_DIR` |
| `AcmeBank/` | App source (SwiftUI, MVVM + Coordinator) |
| `AcmeBank/Sources/Auth/OktaConfig.swift` | Runtime view of injected Okta tenant config |
| `AcmeBank/Home/` | Home dashboard feature (`Models/`, `Repository/`, `ViewModel/`, `View/`) |
| `AcmeBank/Info.plist` | Committed Info.plist with `__*_UNSET__` defaults for the four Okta keys and the `API_BASE_URL` key — NEVER mutated by the build |
| `AcmeBankTests/` | XCTest unit tests |
| `AcmeBankUITests/` | XCUITest end-to-end flow tests |
| `AcmeBankUITests/Support/LiveBFFSmokeTest.swift` | Developer-only live BFF smoke check (gated by `RUN_LIVE_BFF_SMOKE=1`) |
| `CLAUDE.md` / `AGENT.md` | Full architecture context for AI agents |

## Notes

- `AcmeBank.xcodeproj` is **git-ignored** — it is generated by `xcodegen generate`.
- Never hand-edit `project.pbxproj`. Add Swift files to the appropriate directory
  under `AcmeBank/` and run `xcodegen generate` to pick them up automatically.
- See `CLAUDE.md` for the full planned architecture, deferred work, and Git workflow.
