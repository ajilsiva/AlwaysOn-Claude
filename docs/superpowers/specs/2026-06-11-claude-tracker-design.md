# Claude Tracker — Implementation Plan

## Context

Build **Claude Tracker**, a native macOS menu bar + Touch Bar utility that shows live Claude Code usage metrics (model, rate-limit utilization %, reset countdowns, context-window %, effort level), tracks the active project directory and cumulative time on it, and provides a Wake toggle wrapping `caffeinate` so the Mac doesn't sleep during long sessions.

**Environment (verified):** MacBookPro17,1 (M1, physical Touch Bar, TouchBarServer running), macOS 26.5, Swift 6.3.2 with CLI tools only (no Xcode). Project dir is empty greenfield. ⚠️ The directory name has a **trailing space** (`/Users/trashpc01/Desktop/Claude Tracker `) — every script must quote paths.

**User-confirmed decisions:**
1. Rate-limit data via **Anthropic OAuth usage endpoint** using Claude Code's existing local credentials (logs don't contain utilization/reset data — verified).
2. Touch Bar as a **persistent Control Strip item via private DFRFoundation API** (Pock/MTMR approach; public API only shows when app is focused, useless for a background utility). Must degrade gracefully to menu-bar-only.
3. **SwiftPM-only build, no Xcode** — AppKit, code-only UI, script assembles the `.app` bundle, ad-hoc codesign (mandatory on arm64).

## Verified technical facts (do not re-research)

### Usage endpoint (confirmed via CodexBar + CCometixLine sources)
- `GET https://api.anthropic.com/api/oauth/usage`
- Headers: `Authorization: Bearer <accessToken>`, `anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-code/<version>` (read version from newest transcript record; fallback `claude-code/2.1.0`), `Accept: application/json`
- Response: `{five_hour: {utilization, resets_at}, seven_day: {...}, [seven_day_opus, seven_day_sonnet, ...]}` — `utilization` is **percent 0–100**, `resets_at` is ISO8601 with fractional seconds. Decode with all-optional fields.
- Errors: 401 → re-read creds once, retry once, then "re-auth via `claude login`"; 429 → parse `Retry-After` (seconds or HTTP-date), gate further calls; 5xx/offline → keep cached values, mark "stale" after 5 min.

### Credentials (verified on this machine)
- Keychain generic password, service **`"Claude Code-credentials"`** (fresher), fallback file `~/.claude/.credentials.json`. Payload: `{"claudeAiOauth": {"accessToken", "refreshToken", "expiresAt" (epoch **ms**), ...}}`.
- **Read Keychain by spawning `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w`** — NOT SecItemCopyMatching. Ad-hoc cdhash changes every rebuild and would re-prompt; the ACL grant on Apple-signed `security` persists (one "Always Allow" prompt, ever). Never log token values. No token-refresh implementation.

### Touch Bar private API (verified live: symbols resolve via dlopen on this machine)
- **Do NOT link `-framework DFRFoundation`** (no binary on disk, no .tbd — link fails). Use `dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)` + `dlsym`.
- C symbols: `DFRElementSetControlStripPresenceForIdentifier(NSString, Bool)`, `DFRSystemModalShowsCloseBoxWhenFrontMost(Bool)`.
- ObjC selectors via `perform()` on class objects (no bridging header needed): `+[NSTouchBarItem addSystemTrayItem:]`, `removeSystemTrayItem:`, `+[NSTouchBar presentSystemModalTouchBar:systemTrayItemIdentifier:]`, `dismissSystemModalTouchBar:`, `minimizeSystemModalTouchBar:`.
- MTMR-verified sequence: showsCloseBox(true) → create `NSCustomTouchBarItem` with NSButton view → addSystemTrayItem → setControlStripPresence(id, true). Re-assert on 60s tick + wake (ControlStrip restarts drop items).
- Every call guarded by nil-checks → silent degradation to menu-bar-only.

### Transcript data (verified schema)
- `~/.claude/projects/{encoded-cwd}/{sessionId}.jsonl`; assistant records: top-level `timestamp` (ISO8601), `sessionId`, `cwd`, `gitBranch`, `version`, `isSidechain`; `message.model`, `message.usage.{input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens}`.
- **Context % formula** (CCometixLine-confirmed): last `type=="assistant"` record with usage, skipping `isSidechain==true`; `contextTokens = input + cache_creation + cache_read` (constant flag to add output_tokens for parity); limit 200,000 (1,000,000 if model string contains `[1m]`).
- Effort level: `effortLevel` key in settings cascade `{cwd}/.claude/settings.local.json` → `{cwd}/.claude/settings.json` → `~/.claude/settings.json` (currently `"xhigh"` in user settings). Absent everywhere → hide row.

## File tree

```
Claude Tracker /                      (trailing space — quote everything)
├── Package.swift                     (swift-tools 6.0, platforms macOS .v14,
│                                      single executableTarget, .swiftLanguageMode(.v5))
├── Resources/Info.plist              (CFBundleIdentifier=com.aproitsolutions.claude-tracker,
│                                      LSUIElement=true, NSPrincipalClass=NSApplication, ...)
├── scripts/make-app.sh               (swift build -c release → assemble dist/Claude Tracker.app
│                                      → codesign --force --sign -)
├── scripts/run.sh                    (make-app.sh; pkill -x ClaudeTracker || true; open app)
└── Sources/ClaudeTracker/
    ├── main.swift                    (NSApplication bootstrap, .accessory policy)
    ├── App/AppDelegate.swift         (wiring, single-instance via NSRunningApplication, teardown)
    ├── App/AppState.swift            (UsageSnapshot + SessionSnapshot + wakeEnabled; onChange fan-out;
    │                                  main-thread only)
    ├── Menu/StatusItemController.swift  (NSStatusItem, monospaced "◐ 42% · 89%" title,
    │                                     orange ≥70% / red ≥90%)
    ├── Menu/MenuBuilder.swift        (dropdown rows; 1s countdown tick only while menu open)
    ├── TouchBar/DFRPrivateAPI.swift  (dlopen/dlsym shims + perform() wrappers; isAvailable)
    ├── TouchBar/ControlStripController.swift (one strip button "42·89"; tap → modal bar:
    │                                  [5h% →reset] [wk%] [ctx%] [☕Wake] [↻]; re-assertion)
    ├── Data/CredentialsProvider.swift (security CLI → file fallback → notFound)
    ├── Data/UsageAPIClient.swift     (async fetch, status mapping, blockedUntil gate)
    ├── Data/UsageModels.swift        (tolerant Decodables, ISO8601+fractional date parsing)
    ├── Data/TranscriptIndexer.swift  (active session = max-mtime .jsonl across projects;
    │                                  tie-break size then name; idle >10min, gone >24h;
    │                                  FSEvents on ~/.claude/projects, latency 2s, debounce 1s)
    ├── Data/TranscriptParser.swift   (read last 256KB, reverse-scan lines, try? decode minimal struct)
    ├── Data/ProjectTimeAggregator.swift (sum consecutive-timestamp deltas ≤300s across all the active
    │                                  project's sessions; per-file {size, offset, lastTs, seconds} cache;
    │                                  incremental tail reads; shrunk file → full reparse)
    ├── Data/SettingsReader.swift     (effortLevel/model cascade; claude version from newest transcript)
    ├── Data/RefreshCoordinator.swift (60s network+local timer; FSEvents→local; manual = both, network
    │                                  debounced ≥5s; NSWorkspace.didWakeNotification → full refresh)
    └── Power/CaffeinateController.swift (Process: /usr/bin/caffeinate -dims -w <our pid>;
                                       -w makes it die with us even on kill -9; terminationHandler
                                       syncs state; stop() on quit)
```

## Menu dropdown layout

```
Fable 5  ⚡ xhigh                      (model display = strip "claude-", capitalize)
Session  42% · resets 14:32 (in 1h 23m)
Week     12% · resets Mon 09:00 (in 3d 4h)
Context  89% of 200k (177.6k)
─────
Project  <last path component>        (tooltip = full cwd)
Time on project  12h 34m
─────
✓ Keep Mac Awake
Refresh Now          ⌘R
─────
Quit Claude Tracker  ⌘Q
```
Error states replace Session/Week rows: "sign in via Claude Code" / "re-auth needed" / "rate-limited until HH:MM" / "42% (stale 7m)".

## Build order (each milestone verified before the next)

- **M1 Skeleton**: Package.swift, main, AppDelegate, StatusItem with static title + Quit, Info.plist, make-app.sh. ✓ icon appears, no Dock icon, single-instance, `codesign -dv` = adhoc.
- **M2 Wake**: CaffeinateController + menu checkbox. ✓ `pmset -g assertions` shows/clears PreventUserIdleSystemSleep; `kill -9` app → caffeinate self-exits (`-w` test).
- **M3 Transcript engine**: Indexer, Parser, SettingsReader, AppState, menu data rows, manual refresh. ✓ model/effort/project/context% match live session.
- **M4 Project timer + FSEvents**: Aggregator + watcher. ✓ time matches hand-computed deltas; live updates ≤3s during streaming; ~0% CPU idle (incremental offsets working).
- **M5 Usage endpoint**: CredentialsProvider, UsageAPIClient, RefreshCoordinator, live status title. ✓ one-time Keychain prompt; % + countdowns match Claude Code `/usage`; offline → "stale"; no secrets in logs. Pre-verify endpoint with curl (token via `security` piped, never echoed).
- **M6 Touch Bar**: DFRPrivateAPI + ControlStripController. ✓ strip button shows, tap opens modal bar, Wake/Refresh work from Touch Bar, `killall ControlStrip` → item returns ≤60s, simulated dlopen failure → menu-bar-only, no crash.
- **M7 Polish**: wake-refresh, error rows, colors, full checklist pass.

## Verification (end-to-end)

1. `swift build -c release` clean; `bash scripts/make-app.sh` → signed bundle verifies.
2. Launch/relaunch: menu bar only, single instance, clean quit (caffeinate gone, strip item removed).
3. Wake: assertions via `pmset -g assertions`; kill -9 orphan test.
4. Data: cross-check context % and utilization against the live Claude Code session's `/usage` and statusline; idle/stale rules fire; FSEvents latency ≤3s.
5. Network etiquette: ≤1 req/min sustained; 429 honors Retry-After.
6. Touch Bar: all controls functional; ControlStrip-restart recovery; graceful degradation.

## Known caveats (accepted)

- Private DFR API may break in a future macOS update → isolated in one file, nil-degradable.
- Per-session `/effort` overrides aren't persisted locally; only settings-file effort is shown.
- Concurrent sessions on one project may slightly double-count timer (merged-timeline = v1.1).
- Post-compact `summary` records: v1 reverse-scans within the 256KB window; `leafUuid` chase = v1.1.
- Directory's trailing space is kept (renaming would break this session's cwd + project mapping); scripts quote everything. Optionally rename later.
