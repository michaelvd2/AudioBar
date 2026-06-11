#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_STORE_PROVISIONING_PROFILE="${APP_STORE_PROVISIONING_PROFILE:-}"
APP_STORE_APP_SIGN_IDENTITY="${APP_STORE_APP_SIGN_IDENTITY:-}"
APP_STORE_INSTALLER_SIGN_IDENTITY="${APP_STORE_INSTALLER_SIGN_IDENTITY:-}"
APP_STORE_CONNECT_USERNAME="${APP_STORE_CONNECT_USERNAME:-}"
APP_STORE_CONNECT_PASSWORD="${APP_STORE_CONNECT_PASSWORD:-}"
CHECK_PUBLIC_URLS="${CHECK_PUBLIC_URLS:-0}"
SUPPORT_URL="${SUPPORT_URL:-https://michaelvd2.github.io/AudioBar/support.html}"
PRIVACY_URL="${PRIVACY_URL:-https://michaelvd2.github.io/AudioBar/privacy.html}"

cd "$ROOT_DIR"

failures=0

check_pass() {
  printf 'PASS: %s\n' "$1"
}

check_fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

if [[ -z "$APP_STORE_APP_SIGN_IDENTITY" ]]; then
  APP_STORE_APP_SIGN_IDENTITY="$(
    security find-identity -v -p codesigning |
      sed -n 's/.*"\(Mac App Distribution: [^"]*\)".*/\1/p; s/.*"\(3rd Party Mac Developer Application: [^"]*\)".*/\1/p; s/.*"\(Apple Distribution: [^"]*\)".*/\1/p' |
      head -n 1
  )"
fi

if [[ -n "$APP_STORE_APP_SIGN_IDENTITY" ]]; then
  check_pass "App Store application signing identity is available"
else
  check_fail "Missing APP_STORE_APP_SIGN_IDENTITY"
fi

if [[ -z "$APP_STORE_INSTALLER_SIGN_IDENTITY" ]]; then
  APP_STORE_INSTALLER_SIGN_IDENTITY="$(
    security find-identity -v -p basic |
      sed -n 's/.*"\(Mac Installer Distribution: [^"]*\)".*/\1/p; s/.*"\(3rd Party Mac Developer Installer: [^"]*\)".*/\1/p' |
      head -n 1
  )"
fi

if [[ -n "$APP_STORE_INSTALLER_SIGN_IDENTITY" ]]; then
  check_pass "App Store installer signing identity is available"
else
  check_fail "Missing APP_STORE_INSTALLER_SIGN_IDENTITY"
fi

if [[ -n "$APP_STORE_PROVISIONING_PROFILE" && -f "$APP_STORE_PROVISIONING_PROFILE" ]]; then
  check_pass "App Store provisioning profile exists"
else
  check_fail "Missing APP_STORE_PROVISIONING_PROFILE file"
fi

if [[ -f docs/privacy.html ]]; then
  check_pass "privacy.html exists"
else
  check_fail "docs/privacy.html is missing"
fi

if [[ -f docs/support.html ]]; then
  check_pass "support.html exists"
else
  check_fail "docs/support.html is missing"
fi

if [[ -f docs/app-store-submission.md ]]; then
  check_pass "App Store submission notes exist"
else
  check_fail "docs/app-store-submission.md is missing"
fi

if [[ -n "$APP_STORE_CONNECT_USERNAME" && -n "$APP_STORE_CONNECT_PASSWORD" ]]; then
  check_pass "App Store Connect username/password credentials are configured"
else
  check_fail "Missing APP_STORE_CONNECT_USERNAME or APP_STORE_CONNECT_PASSWORD"
fi

if [[ "$CHECK_PUBLIC_URLS" == "1" ]]; then
  if curl -fsI "$SUPPORT_URL" >/dev/null; then
    check_pass "Public support URL is reachable"
  else
    check_fail "Public support URL is not reachable: $SUPPORT_URL"
  fi

  if curl -fsI "$PRIVACY_URL" >/dev/null; then
    check_pass "Public privacy URL is reachable"
  else
    check_fail "Public privacy URL is not reachable: $PRIVACY_URL"
  fi
else
  printf 'SKIP: public URL checks disabled; set CHECK_PUBLIC_URLS=1 to verify published pages\n'
fi

printf '\nNext package command:\n'
printf '  APP_STORE_PROVISIONING_PROFILE=<profile.provisionprofile> APP_STORE_CONNECT_USERNAME=<apple-id> APP_STORE_CONNECT_PASSWORD=<password-or-keychain-ref> script/package_app_store.sh\n'
printf '\nValidation command produced by the package lane:\n'
printf '  xcrun altool --validate-app dist/app-store/AudioBar-AppStore.pkg --username "$APP_STORE_CONNECT_USERNAME" --password "$APP_STORE_CONNECT_PASSWORD"\n'

if [[ "$failures" -gt 0 ]]; then
  printf '\nApp Store preflight failed with %d blocker(s).\n' "$failures" >&2
  exit 1
fi

printf '\nApp Store preflight passed.\n'
