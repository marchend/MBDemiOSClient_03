#!/bin/bash
#
# inject_okta_config.sh
#
# Xcode build-phase script (runs AFTER "Process Info.plist", BEFORE
# Compile Sources / Code Sign). Reads the four OKTA_* environment
# variables from the calling process and writes them into the
# **built-product copy** of Info.plist (inside `BUILT_PRODUCTS_DIR`,
# which lives under `DerivedData` and is git-ignored) so that
# `OktaConfig.load()` can read them via `Bundle.main.infoDictionary` at
# runtime.
#
# Design choices:
#   * We write to `$BUILT_PRODUCTS_DIR/$INFOPLIST_PATH` (the copy Xcode
#     already produced via the "Process Info.plist" phase), NOT to the
#     source `$SRCROOT/$INFOPLIST_FILE`. This is deliberate: mutating
#     the source plist would leave live tenant credentials sitting in
#     the working tree after every build, where a stray `git add -A`
#     or Xcode's "Commit All" would silently include them. By writing
#     only into the built copy, secrets stay entirely inside
#     `DerivedData` (already git-ignored).
#   * If an env var is unset/empty, write a `__<NAME>_UNSET__` sentinel
#     instead of failing the build. A fresh clone with NO Okta secrets
#     MUST still produce a green `xcodebuild`. `OktaConfig.load()`
#     detects the sentinels at runtime and surfaces `.notConfigured`.
#   * We NEVER `exit 1` here for missing vars: failure-on-missing is the
#     app's concern, not the build script's.
#   * The script is idempotent — it always writes all four keys to the
#     built plist on every build.
#
# Why a Run Script and not xcconfig `$(VAR)`:
# xcconfig `$(VAR)` interpolation does NOT pick up shell env vars — it
# only chains other build settings. A Run Script phase IS passed the
# calling process's environment, which is why this is the right
# injection point. See README "Okta build configuration" for the three
# supported ways to make sure Xcode actually sees the env vars
# (launchctl setenv / ~/.zshrc + xed / per-command on the CLI).

set -u

# Target the built Info.plist (inside DerivedData), not the source plist.
# `BUILT_PRODUCTS_DIR` and `INFOPLIST_PATH` are set by Xcode for every
# build-phase script. If they are absent (e.g. ad-hoc CLI invocation
# outside an Xcode build), there is nothing to inject into — exit
# cleanly so the script remains safe to run by hand.
if [ -z "${BUILT_PRODUCTS_DIR:-}" ] || [ -z "${INFOPLIST_PATH:-}" ]; then
  echo "note: BUILT_PRODUCTS_DIR / INFOPLIST_PATH not set; not an Xcode build context — skipping Okta injection."
  exit 0
fi

BUILT_PLIST="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"

if [ ! -f "${BUILT_PLIST}" ]; then
  echo "warning: Built Info.plist not found at ${BUILT_PLIST}; skipping Okta injection. Ensure this Run Script phase runs AFTER \"Process Info.plist\"."
  exit 0
fi

inject() {
  local key="$1"
  local value="$2"
  local sentinel="$3"
  local resolved="${value:-${sentinel}}"
  plutil -replace "${key}" -string "${resolved}" "${BUILT_PLIST}"
}

inject "OktaIssuer"      "${OKTA_ISSUER:-}"       "__OKTA_ISSUER_UNSET__"
inject "OktaClientID"    "${OKTA_CLIENT_ID:-}"    "__OKTA_CLIENT_ID_UNSET__"
inject "OktaRedirectURI" "${OKTA_REDIRECT_URI:-}" "__OKTA_REDIRECT_URI_UNSET__"
inject "OktaScopes"      "${OKTA_SCOPES:-}"       "__OKTA_SCOPES_UNSET__"

exit 0
