#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_ROOT="$PROJECT_ROOT/ios"
BUILD_ROOT="$PROJECT_ROOT/.build/ios"
DIST_ROOT="$PROJECT_ROOT/dist"
APP_PATH="$BUILD_ROOT/Build/Products/Release-iphoneos/AdminDomain.app"

rm -rf "$BUILD_ROOT" "$DIST_ROOT"
mkdir -p "$BUILD_ROOT" "$DIST_ROOT"

cd "$IOS_ROOT"
xcodegen generate --spec project.yml

xcodebuild \
  -project AdminDomain.xcodeproj \
  -scheme AdminDomain \
  -configuration Release \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$BUILD_ROOT" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  clean build

if [[ ! -d "$APP_PATH" ]]; then
  echo "[X] Built app not found: $APP_PATH" >&2
  exit 1
fi

PACKAGE_ROOT="$(mktemp -d)"
trap 'rm -rf "$PACKAGE_ROOT"' EXIT
mkdir -p "$PACKAGE_ROOT/Payload"
cp -R "$APP_PATH" "$PACKAGE_ROOT/Payload/AdminDomain.app"

find "$PACKAGE_ROOT/Payload" -exec touch -h -t 202601010000.00 {} +
(
  cd "$PACKAGE_ROOT"
  COPYFILE_DISABLE=1 TZ=UTC zip -X -y -q -r "$DIST_ROOT/ToolOne.ipa" Payload
)

echo "[OK] Created deterministic $DIST_ROOT/ToolOne.ipa"
