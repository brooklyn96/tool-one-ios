#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then echo "Usage: $0 <ipa-path>" >&2; exit 2; fi
IPA_PATH="$1"
if [[ ! -f "$IPA_PATH" ]]; then echo "[X] IPA not found: $IPA_PATH" >&2; exit 1; fi

VERIFY_ROOT="$(mktemp -d)"
trap 'rm -rf "$VERIFY_ROOT"' EXIT
ditto -x -k "$IPA_PATH" "$VERIFY_ROOT"

APP_PATH="$VERIFY_ROOT/Payload/AdminDomain.app"
INFO_PATH="$APP_PATH/Info.plist"
BINARY_PATH="$APP_PATH/AdminDomain"
if [[ ! -f "$INFO_PATH" || ! -f "$BINARY_PATH" ]]; then echo "[X] IPA payload is incomplete" >&2; exit 1; fi

BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$INFO_PATH")"
DISPLAY_NAME="$(plutil -extract CFBundleDisplayName raw "$INFO_PATH")"
MINIMUM_IOS="$(plutil -extract MinimumOSVersion raw "$INFO_PATH")"
ATS_ARBITRARY="$(plutil -extract NSAppTransportSecurity.NSAllowsArbitraryLoads raw "$INFO_PATH")"
[[ "$BUNDLE_ID" == "com.beyondk.admindomain" ]]
[[ "$DISPLAY_NAME" == "Tool One" ]]
[[ "$MINIMUM_IOS" == "16.0" ]]
[[ "$ATS_ARBITRARY" == "false" ]]
lipo -archs "$BINARY_PATH" | tr ' ' '\n' | grep -qx "arm64"

if [[ -d "$APP_PATH/_CodeSignature" || -f "$APP_PATH/embedded.mobileprovision" ]]; then echo "[X] Expected an unsigned LiveContainer guest app" >&2; exit 1; fi
if find "$APP_PATH" -type d -name "*.framework" -print -quit | grep -q .; then echo "[X] Unexpected bundled framework detected" >&2; exit 1; fi

if find "$APP_PATH" -type f ! -name AdminDomain -print0 | xargs -0 grep -a -E -i "performance\\.beyondk\\.live|control-dashboard"; then
  echo "[X] Prohibited dashboard hostname found in packaged configuration or resources" >&2; exit 1
fi
if grep -R -a -E "BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}" "$APP_PATH"; then
  echo "[X] Secret pattern found in IPA" >&2; exit 1
fi

echo "[OK] IPA verified: $DISPLAY_NAME, $BUNDLE_ID, iOS $MINIMUM_IOS, arm64, strict ATS, unsigned"
