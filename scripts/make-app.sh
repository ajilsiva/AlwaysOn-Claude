#!/bin/bash
# Build the SwiftPM binary, assemble the .app bundle, ad-hoc sign it.
# NB: the project path contains a trailing space — quote everything.
set -euo pipefail
cd "$(dirname "$0")/.."

# Preflight: a build-from-source install needs the Swift toolchain (Xcode
# Command Line Tools). Catch the two common "fresh machine" failures and print
# the fix, instead of letting swiftpm emit a cryptic xcrun/manifest error.
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
  echo "error: Xcode Command Line Tools (Swift) not found." >&2
  echo "Install them, then re-run this script:" >&2
  echo "    xcode-select --install" >&2
  exit 1
fi

swift build -c release

APP="dist/Claude Tracker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/ClaudeTracker" "$APP/Contents/MacOS/ClaudeTracker"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "OK: $APP"
