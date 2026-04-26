<p align="center">
  <img src="TokenEaterApp/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="TokenEater">
</p>

<h1 align="center">TokenEater</h1>

<p align="center">
  <strong>Monitor your Claude AI usage limits directly from your macOS desktop.</strong>
  <br>
  <a href="https://tokeneater.vercel.app">Website</a> · <a href="https://tokeneater.vercel.app/en/docs">Docs</a> · <a href="https://github.com/AThevon/TokenEater/releases/latest">Download</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/WidgetKit-native-007AFF?logo=apple&logoColor=white" alt="WidgetKit">
  <img src="https://img.shields.io/badge/Claude-Pro%20%2F%20Max%20%2F%20Team-D97706" alt="Claude Pro / Max / Team">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/github/v/release/AThevon/TokenEater?color=F97316" alt="Release">
  <a href="https://buymeacoffee.com/athevon"><img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?logo=buymeacoffee&logoColor=black" alt="Buy Me a Coffee"></a>
</p>

---

> **Requires a Claude Pro, Max, or Team plan.** The free plan does not expose usage data.

## What is TokenEater?

A native macOS menu bar app + desktop widgets + floating overlay that tracks your Claude AI usage in real-time.

- **Menu bar** — Live percentages, color-coded thresholds, detailed popover dashboard with three layout variants (Classic / Compact / Focus).
- **Dashboard** — Three-space layout (Monitoring / History / Settings) with flippable tiles surfacing 7d sparklines, peak day, and a pacing-vs-equilibrium graph.
- **History** — Tokens-over-time browser sourced from Claude Code's local JSONL logs. Filter by model family (Opus / Sonnet / Haiku), switch range (24h / 7d / 30d / 90d), hover bars for daily breakdown, identify your heaviest day and top project at a glance.
- **Widgets** — Native WidgetKit widgets (usage gauges, progress bars, pacing) with reactive refresh.
- **Agent Watchers** — Floating overlay showing active Claude Code sessions with dock-like hover effect. Click to jump to the right terminal (Terminal.app, iTerm2, tmux, Kitty, WezTerm). Frost or Neon style, with per-session context fraction.
- **Smart Color** — Risk-aware coloring that combines absolute usage, projection rate, and pacing into a continuous risk score with early-window confidence damping. Three temperaments (Confident / Balanced / Suspicious) to dial sensitivity to your appetite for risk.
- **Smart pacing** — Are you burning through tokens or cruising? Four zones: chill, on track, warning, hot.
- **Themes** — 4 presets + full custom colors. Configurable warning/critical thresholds.
- **Notifications** — Granular per-surface (5h / 7d / Sonnet / Design) and per-event toggles (escalation, recovery, pacing, scheduled reset reminders, extra credits, token expiry).

See all features in detail on the [website](https://tokeneater.vercel.app).

## Install

### Download DMG (recommended)

**[Download TokenEater.dmg](https://github.com/AThevon/TokenEater/releases/latest/download/TokenEater.dmg)**

Open the DMG, drag TokenEater to Applications, and launch it. The DMG is signed with a Developer ID and notarized by Apple, so Gatekeeper lets it run on first launch without any extra steps.

### Homebrew

```bash
brew tap AThevon/tokeneater
brew install --cask tokeneater
```

### First Setup

**Prerequisites:** [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated (`claude` then `/login`). Requires a **Pro, Max, or Team plan**.

1. Open TokenEater — a guided setup walks you through connecting your account
2. Right-click on desktop > **Edit Widgets** > search "TokenEater"

## Update

TokenEater checks for updates automatically. When a new version is available, a modal lets you download and install it in-app — macOS will ask for your admin password to replace the app in `/Applications`.

If you installed via Homebrew: `brew update && brew upgrade --cask tokeneater`

## Uninstall

Delete `TokenEater.app` from Applications, then optionally clean up shared data:
```bash
rm -rf /Applications/TokenEater.app
rm -rf ~/Library/Application\ Support/com.tokeneater.shared
```

If installed via Homebrew: `brew uninstall --cask tokeneater`

## Build from source

```bash
# Requirements: macOS 14+, Xcode 16.4+, XcodeGen (brew install xcodegen)

git clone https://github.com/AThevon/TokenEater.git
cd TokenEater
xcodegen generate
plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' \
  TokenEaterWidget/Info.plist 2>/dev/null || true
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp \
  -configuration Release -derivedDataPath build build
cp -R "build/Build/Products/Release/TokenEater.app" /Applications/
```

## Architecture

```
TokenEaterApp/           App host (settings, OAuth, menu bar, overlay)
TokenEaterWidget/        Widget Extension (WidgetKit, reactive refresh)
Shared/                  Shared code (services, stores, models, pacing)
  ├── Models/            Pure Codable structs
  ├── Services/          Protocol-based I/O (API, TokenProvider, SharedFile, Notification, SessionMonitor, SessionHistory)
  ├── Repositories/      Orchestration (UsageRepository)
  ├── Stores/            ObservableObject state containers (Usage, Theme, Settings, History, MonitoringInsights, Session, Update)
  └── Helpers/           Pure functions (PacingCalculator, MenuBarRenderer, JSONLParser, SmartColor)
```

The app reads Claude Code's OAuth token silently from the macOS Keychain (`kSecUseAuthenticationUISkip`), calls the Anthropic usage API, and writes results to a shared JSON file. A `TokenFileMonitor` watches for credential changes via FSEvents and triggers immediate refresh. The widget reads the shared file — it never touches the network or Keychain. The Agent Watchers overlay scans running Claude Code processes every 2s using macOS system APIs and tail-reads their JSONL logs.

## How it works

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <token>
anthropic-beta: oauth-2025-04-20
```

Returns `utilization` (0–100) and `resets_at` for each limit bucket.

## Security & Privacy

TokenEater reads an **OAuth access token** from the Claude Code keychain entry - the same standard token that Claude Code itself uses. At first launch, macOS will prompt you to allow this access; this is normal macOS behavior for any app reading a keychain item it didn't create.

**What the app does with the token:**
- Calls `GET /api/oauth/usage` (your current usage stats)
- Calls `GET /api/oauth/profile` (your plan info)

**What the app cannot do:** send messages, read conversations, modify your account, or access anything beyond read-only usage data.

The token never leaves your machine except for these two API calls to `api.anthropic.com`. The widget reads a local JSON file and has no network or keychain access at all.

Anthropic does not currently offer a third-party OAuth flow or scoped API tokens - reading the existing token from the keychain is the only option. If scoped tokens become available, TokenEater will adopt them immediately. The entire codebase is open source and auditable: keychain access is in [`SecurityCLIReader.swift`](Shared/Services/SecurityCLIReader.swift) (primary) and [`KeychainService.swift`](Shared/Services/KeychainService.swift) (fallback), API calls in [`APIClient.swift`](Shared/Services/APIClient.swift).

## Troubleshooting

### Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Rate limited" or "API unavailable" | Your OAuth token has hit its per-token request limit | Run `claude /login` in your terminal for a fresh token - TokenEater detects the change and recovers automatically within seconds |
| Keychain popup asking to access "Claude Code-credentials" | First run on a new install needs to authorize `/usr/bin/security` to read your Claude Code token | Click **Always Allow** once - it sticks across future app updates |
| Widget stuck / not updating | macOS caches widget extensions aggressively | Remove the widget, run a clean reset, re-add the widget |

### Clean reset

If something is broken and you want to start fresh, run this in your terminal. It kills all related processes, wipes caches, preferences, and containers, then removes the app:

```bash
# 1. Kill processes
killall TokenEater NotificationCenter chronod cfprefsd 2>/dev/null; sleep 1

# 2. Wipe preferences
defaults delete com.tokeneater.app 2>/dev/null
defaults delete com.claudeusagewidget.app 2>/dev/null
rm -f ~/Library/Preferences/com.tokeneater.app.plist
rm -f ~/Library/Preferences/com.claudeusagewidget.app.plist

# 3. Wipe sandbox containers
for c in com.tokeneater.app com.tokeneater.app.widget com.claudeusagewidget.app com.claudeusagewidget.app.widget; do
    d="$HOME/Library/Containers/$c/Data"
    [ -d "$d" ] && rm -rf "$d/Library/Preferences/"* "$d/Library/Caches/"* "$d/Library/Application Support/"* "$d/tmp/"* 2>/dev/null
done

# 4. Wipe shared data and caches
rm -rf ~/Library/Application\ Support/com.tokeneater.shared
rm -rf ~/Library/Application\ Support/com.claudeusagewidget.shared
rm -rf ~/Library/Caches/com.tokeneater.app
rm -rf ~/Library/Group\ Containers/group.com.claudeusagewidget.shared

# 5. Wipe WidgetKit caches (critical - macOS keeps old widget binaries here)
TMPBASE=$(getconf DARWIN_USER_TEMP_DIR)
CACHEBASE=$(getconf DARWIN_USER_CACHE_DIR)
rm -rf "${TMPBASE}com.apple.chrono" "${CACHEBASE}com.apple.chrono" 2>/dev/null
rm -rf "${CACHEBASE}com.tokeneater.app" "${CACHEBASE}com.claudeusagewidget.app" 2>/dev/null

# 6. Unregister widget plugins
pluginkit -r -i com.tokeneater.app.widget 2>/dev/null
pluginkit -r -i com.claudeusagewidget.app.widget 2>/dev/null

# 7. Remove the app
rm -rf /Applications/TokenEater.app
```

> Some `Operation not permitted` errors on container metadata files are normal - macOS protects those, but the actual data is cleaned.

After this, reinstall from the [latest release](https://github.com/AThevon/TokenEater/releases/latest/download/TokenEater.dmg) or via Homebrew, then **remove old widgets from your desktop and add them again** (right-click > Edit Widgets > TokenEater).

## Support

If TokenEater saves you from hitting your limits blindly, consider [buying me a coffee](https://buymeacoffee.com/athevon) ☕

## License

MIT

