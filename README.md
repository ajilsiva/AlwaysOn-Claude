# Claude Tracker

macOS menu bar + Touch Bar utility that tracks your live Claude Code usage:
model, rate-limit utilization with reset countdowns, context-window %, active
project and time spent on it — plus a Wake toggle (`caffeinate` wrapper) to
keep the Mac awake during long sessions.

## Build & run

Requires only Xcode Command Line Tools (no Xcode):

```bash
bash scripts/run.sh        # build, assemble dist/Claude Tracker.app, sign, launch
```

The menu bar shows `◐ 5h% · ctx%` (orange ≥ 70%, red ≥ 90%; ☕ prefix while
Wake is on). The dropdown has the full readout, Wake toggle, Refresh (⌘R),
and Quit (⌘Q). On Touch Bar Macs a persistent Control Strip button shows the
compact readout; tapping it opens the full strip with Wake/Refresh controls.

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
