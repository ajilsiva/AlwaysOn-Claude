#!/bin/bash
# Build the SwiftPM binary, assemble the .app bundle, ad-hoc sign it.
# NB: the project path contains a trailing space — quote everything.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="dist/Claude Tracker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/ClaudeTracker" "$APP/Contents/MacOS/ClaudeTracker"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "OK: $APP"
