#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/make-app.sh
pkill -x ClaudeTracker || true
sleep 0.5
open "dist/Claude Tracker.app"
