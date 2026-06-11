# Changelog

## 1.1.0 — 2026-06-11

- Display preference: **Menu Bar + Touch Bar** (default), **Menu Bar Only**, or
  **Touch Bar Only** — pick in the dropdown's Display submenu or via
  `--set-display both|menubar|touchbar` (persists; relaunches a running instance).
- Touch Bar hardware detection (TouchBarServer check): on Macs without a Touch
  Bar the Touch Bar options are greyed out and the app runs menu-bar-only —
  no errors, nothing to configure.
- Safety rule: the app never runs with zero surfaces. "Touch Bar Only" falls
  back to showing the menu bar whenever the Touch Bar is unavailable.

## 1.0.0 — 2026-06-11

Initial release.

- Menu bar readout: drawn 5-hour utilization bar (green/orange/red, /usage-style
  thresholds) + 5h and weekly percentages; ☕ glyph while Wake is on.
- Dropdown: /usage-style card (plan badge, 5-hour + Weekly bars, reset countdowns,
  status dot, updated/error footer), model + effort level, context-window %, active
  project, cumulative time-on-project, Wake toggle, Launch at Login, Refresh (⌘R).
- Touch Bar (Touch Bar Macs): persistent Control Strip widget with stacked 5h/wk
  bars; tap expands to a modal strip with reset countdown, context %, Wake and
  Refresh. Degrades to menu-bar-only when unavailable (`CT_NO_TOUCHBAR=1` to force).
- Wake: `caffeinate -dims` wrapper, crash-safe via `-w <pid>`; toggleable from the
  menu, Touch Bar, or `kill -USR1`.
- Data: account-wide utilization + reset times from Anthropic's OAuth usage endpoint
  (existing Claude Code credentials, ≤1 request/min); session/model/context/project
  metrics parsed incrementally from `~/.claude` transcripts with FSEvents live
  updates across all terminal sessions.
- CLI: `--dump [--usage]`, `--register-login` / `--unregister-login` / `--login-status`.
- Install: `scripts/install.sh` → /Applications + SMAppService login item.
