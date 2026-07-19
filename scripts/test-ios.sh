#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_ROOT="$PROJECT_ROOT/ios"
TEST_BUILD_ROOT="$PROJECT_ROOT/.build/tests"

cd "$IOS_ROOT"
xcodegen generate --spec project.yml

SIMULATOR_ID="$(
  xcrun simctl list devices available -j | python3 -c '
import json
import sys

devices = json.load(sys.stdin)["devices"]
for runtime_devices in devices.values():
    for device in runtime_devices:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit("No available iPhone simulator was found")
'
)"

xcodebuild test \
  -project AdminDomain.xcodeproj \
  -scheme AdminDomain \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$TEST_BUILD_ROOT" \
  CODE_SIGNING_ALLOWED=NO
