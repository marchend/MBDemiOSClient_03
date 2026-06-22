#!/bin/bash
#
# inject_okta_config.sh
#
# Xcode build-phase script (runs BEFORE Compile Sources). Reads the four
# OKTA_* environment variables from the calling process and writes them
# into the app's Info.plist with `plutil -replace` so that
# `OktaConfig.load()` can read them via `Bundle.main.infoDictionary` at
# runtime.
#
# Design choices:
#   * If an env var is unset/empty, write a `__<NAME>_UNSET__` sentinel
#     instead of failing the build. A fresh clone with NO Okta secrets
#     MUST still produce a green `xcodebuild`. `OktaConfig.load()`
#     detects the sentinels at runtime and surfaces `.notConfigured`.
#   * We NEVER `exit 1` here for missing vars: failure-on-missing is the
#     app's concern, not the build script's.
#   * The script is idempotent — it always writes all four keys, so on a
#     clean repo with no env vars the source plist's sentinels are
#     rewritten as identical sentinels (no git diff).
#
# Why a Run Script and not xcconfig `$(VAR)`:
# xcconfig `$(VAR)` interpolation does NOT pick up shell env vars — it
# only chains other build settings. A Run Script phase IS passed the
# calling process's environment, which is why this is the right
# injection point. See README "Okta build configuration" for the three
# supported ways to make sure Xcode actually sees the env vars
# (launchctl setenv / ~/.zshrc + xed / per-command on the CLI).

set -u

# Prefer the source plist so the change feeds through Xcode's
# Process-Info.plist phase. `INFOPLIST_FILE` is the project setting;
# fall back to the conventional location for safety.
SRC_PLIST="${SRCROOT:-$(pwd)}/${INFOPLIST_FILE:-AcmeBank/Info.plist}"

if [ ! -f "${SRC_PLIST}" ]; then
  echo "warning: Info.plist not found at ${SRC_PLIST}; skipping Okta injection."
  exit 0
fi

inject() {
  local key="$1"
  local value="$2"
  local sentinel="$3"
  local resolved="${value:-${sentinel}}"
  plutil -replace "${key}" -string "${resolved}" "${SRC_PLIST}"
}

inject "OktaIssuer"      "${OKTA_ISSUER:-}"       "__OKTA_ISSUER_UNSET__"
inject "OktaClientID"    "${OKTA_CLIENT_ID:-}"    "__OKTA_CLIENT_ID_UNSET__"
inject "OktaRedirectURI" "${OKTA_REDIRECT_URI:-}" "__OKTA_REDIRECT_URI_UNSET__"
inject "OktaScopes"      "${OKTA_SCOPES:-}"       "__OKTA_SCOPES_UNSET__"

exit 0
