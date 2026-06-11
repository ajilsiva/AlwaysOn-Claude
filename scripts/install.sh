#!/bin/bash
# Build, install to /Applications, and (re)launch. Use this instead of run.sh
# when you want the persistent copy that "Launch at Login" points at.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/make-app.sh
pkill -x ClaudeTracker || true
sleep 0.5
rm -rf "/Applications/Claude Tracker.app"
cp -R "dist/Claude Tracker.app" "/Applications/Claude Tracker.app"
open "/Applications/Claude Tracker.app"
echo "Installed and launched /Applications/Claude Tracker.app"
