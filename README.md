<p align="center">
  <img src="TokenEaterApp/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="TokenEater">
</p>

<h1 align="center">TokenEater</h1>

<p align="center">
  <strong>Monitor your Claude and Codex usage limits directly from your macOS desktop.</strong>
</p>

<p align="center">
  <a href="https://tokeneater.athevon.dev">Website</a> ·
  <a href="#install">Install</a> ·
  <a href="#what-you-get">Features</a> ·
  <a href="#privacy-read-only-usage-calls">Privacy</a> ·
  <a href="https://tokeneater.athevon.dev/en/docs">Docs</a> ·
  <a href="https://github.com/AThevon/TokenEater/releases">Releases</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/WidgetKit-native-007AFF?logo=apple&logoColor=white" alt="WidgetKit">
  <img src="https://img.shields.io/badge/Claude-Pro%20%2F%20Max%20%2F%20Team-D97706" alt="Claude Pro / Max / Team">
  <img src="https://img.shields.io/github/downloads/AThevon/TokenEater/total?color=F97316" alt="Downloads">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/github/v/release/AThevon/TokenEater?color=F97316" alt="Release">
  <a href="https://buymeacoffee.com/athevon"><img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?logo=buymeacoffee&logoColor=black" alt="Buy Me a Coffee"></a>
</p>

---

> **Requires a Claude Pro, Max, or Team plan.** The free plan does not expose usage data.

<!--
Screenshots slot. Four shots, ~200px wide each, dropped into docs/assets/readme/:
  popover.png    (menu bar + popover dashboard)
  monitoring.png (main window, Monitoring space)
  watchers.png   (Agent Watchers overlay over a desktop)
  widgets.png    (desktop widgets)
Then wire them here as a centered row:
<p align="center">
  <img src="docs/assets/readme/popover.png" width="200" alt="...">
  ...
</p>
-->

## What you get

A native menu bar app, desktop widgets, and a floating overlay that track your Claude usage in real time, with optional Codex tracking on the dashboard and desktop.

- **Menu bar.** Live percentages with color-coded thresholds, and a popover dashboard you compose element by element (rings, chips, arcs, pacing bars at full, half, or third width), start from built-in templates, and save as your own.
- **Dashboard.** A three-space window (Monitoring / History / Settings) with flippable tiles, 7-day sparklines, peak day, and a pacing-vs-equilibrium graph.
- **Codex.** Detects a Codex CLI ChatGPT login and tracks its usage windows, pacing, reset reminders, and quota-reset alerts. A separate small or medium Codex Usage widget sits alongside the Claude widgets. API-key accounts have no usage windows to track.
- **History.** Combined Claude Code and Codex tokens from local session logs: a stacked chart by model, project ranking, session counts, and cache hit rate, filterable by Claude family or Codex model across 24h to 90d ranges. The History widget shows the combined daily totals.
- **Widgets.** Native WidgetKit gauges, progress bars, and pacing, refreshed reactively.
- **Agent Watchers.** A floating overlay of your live Claude Code sessions, terminals and VSCode-family extensions alike. Click a session to jump to its terminal or editor (Terminal, iTerm2, tmux, Kitty, WezTerm), right-click for quick actions.
- **Smart Color.** Blends how much you have used with how fast you are burning, so the color warns you before the number does. Three temperaments set how cautious it is.
- **Smart pacing.** Are you burning through tokens or cruising? Four zones: chill, on track, warning, hot.
- **Themes.** Four presets plus full custom colors, a glow or flat look, and configurable warning thresholds.
- **Notifications.** Per-surface and per-event toggles: escalation, recovery, pacing, scheduled reset reminders, extra credits, token expiry.

Everything in detail on the [website](https://tokeneater.athevon.dev).

## Install

### Download DMG (recommended)

**[Download TokenEater.dmg](https://github.com/AThevon/TokenEater/releases/latest/download/TokenEater.dmg)**

Open the DMG, drag TokenEater to Applications, and launch it. The DMG is signed with a Developer ID and notarized by Apple, so Gatekeeper lets it run on first launch without any extra steps.

### Homebrew

```bash
brew tap AThevon/tokeneater
brew trust AThevon/tokeneater
brew install --cask tokeneater
```

> `brew trust` is required on Homebrew 6.0+, which no longer loads a third-party tap until you trust it.

### First setup

**Prerequisites:** [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated (`claude` then `/login`), on a **Pro, Max, or Team plan**.

1. Open TokenEater: a guided setup walks you through connecting your account
2. Right-click on the desktop > **Edit Widgets** > search "TokenEater"

## Update

TokenEater checks for updates automatically. When a new version is available, a modal lets you download and install it in-app; macOS will ask for your admin password to replace the app in `/Applications`.

If you installed via Homebrew: `brew update && brew upgrade --cask tokeneater`

## Uninstall

Delete `TokenEater.app` from Applications, then optionally clean up shared data:

```bash
rm -rf /Applications/TokenEater.app
rm -rf ~/Library/Application\ Support/com.tokeneater.shared
```

If you installed via Homebrew: `brew uninstall --cask tokeneater`. For a complete wipe, caches and widget state included, use the clean reset in the [troubleshooting guide](docs/TROUBLESHOOTING.md).

## Build it yourself

```bash
git clone https://github.com/AThevon/TokenEater.git
cd TokenEater
./build.sh
```

The script checks Xcode, installs XcodeGen if needed, and assembles the app. Local builds are not notarized, so Gatekeeper blocks the first launch (right-click > Open, or System Settings > Privacy & Security > Open Anyway). The step-by-step walkthrough is in [`SETUP.md`](SETUP.md).

## Privacy: read-only usage calls

TokenEater reads the **OAuth access token** Claude Code already keeps in your macOS Keychain, the same token Claude Code itself uses. At first launch, macOS asks you to allow that access: click **Always Allow** once. The prompt is standard macOS behavior for any app reading a keychain item it did not create, and since the read goes through Apple's own `security` tool, whose signature never changes, the prompt does not come back on updates.

Everything the app does with the token:

- `GET api.anthropic.com/api/oauth/usage`, your current usage stats
- `GET api.anthropic.com/api/oauth/profile`, your plan info

When Codex tracking is enabled, the app also reads the Codex CLI access token from `~/.codex/auth.json` (or `CODEX_HOME`) and makes one additional authenticated call:

- `GET chatgpt.com/backend-api/wham/usage`, your Codex usage windows and credits

These usage and profile calls are read-only. TokenEater does not send messages, read conversations, or modify either account. Each access token is sent only to its own provider. TokenEater never writes to Codex credentials or refreshes its OAuth token; open Codex or run `codex login` if it expires. API-key and keyring-only Codex logins are not supported in this version.

Widgets read local JSON files with no network or Keychain access. The Codex widget reads `codex.json` for usage and `shared.json` for theme preferences; its cache contains no token, email, or account ID. History reads Claude Code and Codex local session logs without uploading them; Agent Watchers reads Claude Code sessions.

Anthropic does not offer a third-party OAuth flow or scoped tokens yet, so reading the existing token is the only way an app like this can exist. If scoped tokens become available, TokenEater will adopt them immediately. The relevant code is short and auditable: keychain access in [`SecurityCLIReader.swift`](Shared/Services/SecurityCLIReader.swift) and [`TokenProvider.swift`](Shared/Services/TokenProvider.swift), the Claude calls in [`APIClient.swift`](Shared/Services/APIClient.swift), and Codex access in [`CodexAuthReader.swift`](Shared/Services/CodexAuthReader.swift) and [`CodexAPIClient.swift`](Shared/Services/CodexAPIClient.swift).

## Codex setup and widgets

Sign in to the Codex CLI with your ChatGPT account. TokenEater enables Codex tracking automatically on the first launch that detects that login. If you sign in later, enable **Codex** under **Settings > General > Providers**. This version adds Codex to Monitoring, widgets, and combined History; menu bar segments, the popover, and Agent Watchers remain Claude features. The existing Claude onboarding requirements still apply.

History includes local sessions from both providers, independently of quota authentication. It reads Codex `sessions/` and `archived_sessions/` under `CODEX_HOME` (default `~/.codex`). `All` sums uncached input, cache writes, and output tokens for both providers. Only cache reads count as reused tokens in the cache breakdown. Guardian / auto-review sessions are excluded from all History statistics and the History widget. Reasoning tokens are already included in Codex output. Models are discovered from the logs and have individual filters. The History widget receives seven calendar-day totals from the app, refreshed every minute while TokenEater runs; it does not read session files itself.

In **Edit Widgets > TokenEater**, choose **Codex Usage** (small or medium) alongside **Claude Overview**, **Claude Session Ring**, or the other Claude widgets. Existing Claude widgets keep their identity when upgrading; only their gallery names change. Codex windows are labelled by duration, so weekly-only plans show a weekly window rather than an invented five-hour session.

## If something breaks

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Rate limited" or "API unavailable" | Your OAuth token has hit its per-token request limit | Run `claude /login` for a fresh token; TokenEater detects the change and recovers within seconds |
| Keychain popup on first run | A new install needs authorization to read your Claude Code token | Click **Always Allow** once; it sticks across updates |
| Widget stuck or not updating | macOS caches widget extensions aggressively | Remove the widget, run the clean reset, re-add the widget |

Anything deeper, including the full clean reset that wipes caches, preferences, and widget state, lives in the [troubleshooting guide](docs/TROUBLESHOOTING.md).

## Documentation

- [Setup](SETUP.md), building from source step by step
- [Troubleshooting](docs/TROUBLESHOOTING.md), common fixes and the clean reset
- [Contributing](CONTRIBUTING.md), workflow, commit conventions, and testing
- [AGENTS.md](AGENTS.md), architecture, data flow, and the SwiftUI rules, for contributors and AI agents alike
- [Design system](docs/design/MASTER.md), how the windows are built and colored

## Contributing

Contributions are welcome: bug reports, feature ideas, and code PRs all help. Start with [`CONTRIBUTING.md`](CONTRIBUTING.md); it covers the workflow and a few SwiftUI rules worth knowing before touching the code.

## Support

If TokenEater saves you from hitting your limits blindly, consider [buying me a coffee](https://buymeacoffee.com/athevon).

## License

MIT

---

<p align="center">
  Built by <a href="https://athevon.dev"><strong>Adrien Thevon</strong></a>, software engineer in Toulouse.
  <br />
  <sub>
    Also mine:
    <a href="https://github.com/AThevon/genjutsu">genjutsu</a>, creative coding skills for Claude
    &nbsp;·&nbsp;
    <a href="https://github.com/AThevon/worktigre">worktigre</a>, a git worktree manager
  </sub>
</p>
