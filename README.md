# AlwaysOn Claude

macOS menu bar + Touch Bar utility (app name: Claude Tracker) that tracks
your live Claude Code usage:
model, rate-limit utilization with reset countdowns, context-window %, active
project and time spent on it — plus a Wake toggle (`caffeinate` wrapper) to
keep the Mac awake during long sessions.

## Build & install

Requires only Xcode Command Line Tools (no Xcode):

```bash
bash scripts/install.sh    # build, install to /Applications, launch
bash scripts/run.sh        # dev loop: build + launch from dist/ instead
```

To survive restarts: run `install.sh` once, then enable **Launch at Login**
in the dropdown menu (manageable later in System Settings › Login Items).

The menu bar shows `✳︎ [bar] 5h% · wk%` — a drawn 5-hour progress bar colored
like Claude Code's /usage card (green, orange ≥ 50%, red ≥ 85%), with ☕
replacing ✳︎ while Wake is on. The dropdown opens with a /usage-style card
(plan badge, 5-hour and Weekly bars, reset countdowns, status dot), then
model/context/project rows, Wake toggle, Launch at Login, Refresh (⌘R), Quit
(⌘Q). On Touch Bar Macs a persistent Control Strip widget shows both bars;
tapping opens the full strip with Wake/Refresh controls.

The tracker is global: it watches every Claude Code session in every
terminal (all of `~/.claude/projects/`) and shows the most recently active
one; utilization numbers are account-wide.

## Data sources

- **Transcripts** `~/.claude/projects/*/*.jsonl` — model, context tokens
  (input + cache_creation + cache_read of the last assistant turn), active
  project (cwd), project time (sum of message-timestamp deltas ≤ 5 min,
  parsed incrementally), effort level from the settings cascade.
- **OAuth usage endpoint** (`api.anthropic.com/api/oauth/usage`) — the same
  5-hour/weekly utilization and reset times Claude Code's `/usage` shows,
  authenticated with your existing Claude Code credentials (Keychain via
  `/usr/bin/security`, fallback `~/.claude/.credentials.json`). Polled at most
  once per minute. Tokens are never logged.

## CLI / scripting

```bash
".build/release/ClaudeTracker" --dump           # print the local snapshot
".build/release/ClaudeTracker" --dump --usage   # + live utilization fetch
kill -USR1 $(pgrep -x ClaudeTracker)            # toggle Wake (hotkey-friendly)
CT_NO_TOUCHBAR=1 open "dist/Claude Tracker.app" # menu-bar-only mode
```

## Caveats

- The Touch Bar Control Strip item uses the private DFRFoundation API
  (same approach as Pock/MTMR): fine for a personal app, not App
  Store-distributable, could break in a future macOS release. The app
  degrades to menu-bar-only automatically if the API is unavailable.
- If the OAuth token expires, the menu shows "re-auth needed" — run `claude`
  to refresh it; the app picks the new token up on the next poll.
- First launch may show one Keychain prompt for `/usr/bin/security` — choose
  "Always Allow"; it never re-prompts, even across rebuilds.
