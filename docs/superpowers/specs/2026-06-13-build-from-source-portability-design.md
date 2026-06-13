# Build-from-source portability — design

Date: 2026-06-13

## Context

AlwaysOn Claude (app: "Claude Tracker") is distributed as source: users
`git clone` and run `bash scripts/install.sh`, which builds with SwiftPM and
installs to `/Applications`. A friend forking the repo onto a MacBook M2 Air
could not install it. The failure was **not** the missing Touch Bar (that path
already degrades to menu-bar-only); it was the package manifest:

```
Package.swift: 'SwiftSetting' has no member 'swiftLanguageMode'
```

`Package.swift` declared `swift-tools-version:6.0` and used
`swiftSettings: [.swiftLanguageMode(.v5)]`. That `SwiftSetting` API only exists
on newer Swift 6.x toolchains, so the manifest failed to compile on his older
6.0 toolchain — before any source code was touched. (Already fixed: manifest
pinned to `swift-tools-version:5.9`, commit `fc5fea4`.)

The goal: **`git clone && bash scripts/install.sh` should succeed on any
macOS 14+ MacBook — Intel or Apple Silicon, Touch Bar or not** — and when the
prerequisites are missing, the user should get a clear, actionable message
instead of a cryptic compiler/`xcrun` error.

## Scope decisions (confirmed with user)

- **Distribution:** build-from-source only. No prebuilt `.app`, no
  notarization, no universal-binary tooling.
- **macOS floor:** keep macOS 14 (Sonoma). No lowering, so no API-availability
  auditing or `#available` guards. On macOS 14 the minimum toolchain is
  Xcode 15 / Swift 5.9, which the 5.9 manifest pin targets exactly.
- **No runtime/behavior changes.** Touch Bar already degrades cleanly
  (`ControlStripController.hardwarePresent`, `AppDelegate.applyDisplayMode`),
  `swift build` targets the host architecture, and `codesign --sign -` works on
  Intel. Nothing Apple-Silicon-only exists in the sources.

## Changes

### 1. Toolchain preflight in `scripts/make-app.sh`

`make-app.sh` is the single build entry point — both `install.sh` and `run.sh`
call it. Add a preflight at the top (after `set -euo pipefail` and the `cd`,
before `swift build`) that catches the two real failure modes and exits with a
one-line fix:

- **CLT path invalid / not installed** — `xcode-select -p` fails → print
  `xcode-select --install` and exit 1.
- **`swift` not on PATH** — `command -v swift` fails → same hint, exit 1.

No Swift *version* check is needed: the macOS 14 floor guarantees Swift 5.9+,
and the 5.9 manifest pin already builds on everything from there up.

Representative shape:

```bash
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
  echo "error: Xcode Command Line Tools (Swift) not found." >&2
  echo "Install them, then re-run this script:" >&2
  echo "    xcode-select --install" >&2
  exit 1
fi
```

### 2. README troubleshooting section

The README already lists prerequisites correctly (macOS 14+, Intel/Apple
Silicon, CLT only, build-from-source so no Gatekeeper override). Add a short
**Troubleshooting** section covering:

- `swift: command not found` / `xcrun: error: invalid active developer path`
  → `xcode-select --install`.
- Manifest/`swiftLanguageMode` error on an older fork → `git pull` to get the
  5.9-pinned manifest.

### 3. Keep prior fixes

- `Package.swift` pinned to `swift-tools-version:5.9` (done, committed).
- `CLAUDE.md` build-constraints note explaining the pin (edited, pending
  commit) — commit it with this work.

## Verification

```bash
swift build -c release                  # clean build on this (host) toolchain
bash scripts/install.sh                 # preflight passes → builds → installs → launches
".build/release/ClaudeTracker" --dump   # local pipeline still works

# Preflight negative path (simulate missing toolchain without uninstalling CLT):
PATH=/usr/bin:/bin bash -c '! command -v swift' && echo "would trigger preflight"
```

On the friend's M2 Air (the real acceptance test): `git pull &&
bash scripts/install.sh` → clean build, app in `/Applications`, ✲ menu-bar item
(no Touch Bar widget — correct for an M2 Air).

## Out of scope (YAGNI)

- Prebuilt releases / `.dmg` / notarization.
- Universal binary cross-compilation.
- macOS < 14 support and `SMLoginItemSetEnabled` fallback.
- Any change to the Touch Bar or data-pipeline code.
