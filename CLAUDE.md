# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

AlwaysOn Claude (app bundle name: "Claude Tracker") — a macOS menu bar + Touch Bar
utility showing live Claude Code usage: rate-limit utilization with reset countdowns,
context-window %, active project + time on it, and a `caffeinate` Wake toggle.
LSUIElement accessory app, single SwiftPM executable target, zero dependencies,
AppKit only (no SwiftUI, no storyboards).

## Commands

```bash
swift build                                   # compile (debug)
bash scripts/run.sh                           # dev loop: build → dist/Claude Tracker.app → launch
bash scripts/install.sh                       # build → install /Applications → launch (login item points here)
".build/debug/ClaudeTracker" --dump           # print local-data snapshot, no GUI — primary verification tool
".build/debug/ClaudeTracker" --dump --usage   # + live OAuth usage fetch (prints percentages only)
```

There is no test suite. Verify changes with `--dump` (exercises the exact production
pipeline), plus: `pmset -g assertions` for the Wake feature, `kill -USR1 <pid>` to
toggle Wake from the shell, `--login-status` / `--register-login` for the login item,
`--set-display both|menubar|touchbar` for the surface preference (persisted in
UserDefaults `displayMode`), `CT_NO_TOUCHBAR=1` to simulate a Mac without a Touch Bar.

**Display modes:** `DisplayMode` (AppState.swift) + `AppDelegate.applyDisplayMode()`
enforce one invariant — the app always has ≥1 UI surface. Touch Bar hardware is
detected via `ControlStripController.hardwarePresent` (pgrep TouchBarServer); without
it, Touch Bar menu options are disabled and "Touch Bar Only" falls back to menu bar.

**Build constraints:** only Xcode CLT is installed (no Xcode/xcodebuild — never add an
.xcodeproj). The .app bundle is assembled by `scripts/make-app.sh` and ad-hoc signed
(mandatory on arm64). Paths contain spaces — always quote. `Package.swift` is
intentionally pinned to `swift-tools-version:5.9` — Swift 5 language mode is the
default at that manifest version, so the package builds in v5 mode (avoiding
strict-concurrency churn) on any toolchain from Xcode 15 up. Do NOT "upgrade" it to
tools-version 6.0 + `swiftSettings: [.swiftLanguageMode(.v5)]`: that API only exists
on newer Swift 6.x toolchains and breaks the manifest on earlier ones (clean-machine
forks fail to compile before any source is touched).

## Architecture

Everything renders from one observable model and two data paths feed it:

- **`App/AppState`** — central snapshot store (`UsageSnapshot` from the network,
  `SessionSnapshot` from local files, `wakeEnabled`). Main-thread only; UI controllers
  `subscribe` and re-render on every mutation. All display formatting lives in `Format`
  (same file).
- **`Data/RefreshCoordinator`** — the nervous system. 60 s timer + FSEvents (via
  `TranscriptIndexer`) + wake notification + manual refresh all funnel here. Local
  parsing runs on its serial utility queue via `LocalDataPipeline`; snapshots are
  applied to AppState on main. Network etiquette is enforced here: ≥55 s between timer
  fetches, ≥5 s for manual, 429 `Retry-After` gates via `blockedUntil`, one credential
  re-read + retry on 401.
- **Local path:** `TranscriptIndexer` (active session = most-recently-modified
  `~/.claude/projects/*/*.jsonl`) → `TranscriptParser` (reads only the last 256 KB,
  reverse-scans for the last non-sidechain assistant record) → `SettingsReader`
  (effortLevel/model cascade) → `ProjectTimeAggregator` (sums timestamp deltas ≤ 5 min
  across the project's transcripts, **incrementally** — per-file byte offsets, only
  appended bytes are ever re-read; cold reparse only if a file shrinks).
- **Network path:** `CredentialsProvider` → `UsageAPIClient` → decoded by tolerant
  all-optional `UsageModels`.
- **UI:** `Menu/StatusItemController` (menu bar title: glyph + drawn bar + percentages),
  `Menu/MenuBuilder` (dropdown; `UsageCardView` replicates Claude Code's /usage card),
  `TouchBar/ControlStripController` (persistent Control Strip widget + tap-expanded
  modal bar). All bar drawing is shared in `UI/BarRenderer` (green < 50 ≤ orange < 85 ≤ red).
- **`TouchBar/DFRPrivateAPI`** — the app's entire private-API surface, isolated in this
  one file and nil-degradable everywhere (app falls back to menu-bar-only).

## Hard-won constraints (do not "simplify" these away)

- **DFRFoundation cannot be linked** — no binary on disk, no .tbd. It must be
  `dlopen`ed from the dyld shared cache; ObjC private class methods are called via
  `perform()` so the target stays pure Swift.
- **Keychain reads must go through `/usr/bin/security`**, not `SecItemCopyMatching`:
  the ad-hoc signature's cdhash changes every rebuild and would re-trigger the Keychain
  ACL prompt; the grant to Apple-signed `security` persists. Service name:
  `"Claude Code-credentials"`; fallback `~/.claude/.credentials.json`; `expiresAt` is
  epoch **milliseconds**. Never log token material.
- **Usage endpoint** (`GET https://api.anthropic.com/api/oauth/usage`) requires
  `anthropic-beta: oauth-2025-04-20` and a `claude-code/<version>` User-Agent.
  `utilization` is percent 0–100. `resets_at` carries **6-digit fractional seconds**
  which `ISO8601DateFormatter.withFractionalSeconds` rejects — `APIDate` strips the
  fraction as a fallback; keep that. The response contains unknown/null window keys —
  decoders must stay all-optional.
- **Context formula:** `input_tokens + cache_creation_input_tokens +
  cache_read_input_tokens` of the last non-sidechain assistant record (skip models
  containing `<`, i.e. `<synthetic>`); limit 200k, or 1M when the model string contains
  `[1m]`. The displayed % can legitimately exceed 100 right before auto-compaction.
- **caffeinate is spawned with `-w <our pid>`** so a crash/kill -9 can never orphan a
  sleep assertion — keep that flag if touching `CaffeinateController`.
- ControlStrip/TouchBarServer restarts silently drop tray items — the 60 s re-assertion
  (remove + add + setPresence) in `ControlStripController` is load-bearing.
