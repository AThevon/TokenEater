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

- **Menu bar** — Live percentages, color-coded thresholds, detailed popover dashboard
- **Widgets** — Native WidgetKit widgets (usage gauges, progress bars, pacing) with reactive refresh
- **Agent Watchers** — Floating overlay showing active Claude Code sessions with dock-like hover effect. Click to jump to the right terminal (Terminal.app, iTerm2, tmux, Kitty, WezTerm).
- **Smart pacing** — Are you burning through tokens or cruising? Three zones: chill, on track, hot.
- **Themes** — 4 presets + full custom colors. Configurable warning/critical thresholds.
- **Notifications** — Alerts at warning, critical, and reset.

See all features in detail on the [website](https://tokeneater.vercel.app).

## Install

### Download DMG (recommended)

**[Download TokenEater.dmg](https://github.com/AThevon/TokenEater/releases/latest/download/TokenEater.dmg)**

Open the DMG, drag TokenEater to Applications, then:

1. Double-click TokenEater in Applications — macOS will block it
2. Open **System Settings → Privacy & Security** — scroll down to find the message about TokenEater
3. Click **Open Anyway** and confirm

> **Important:** Do not use `xattr -cr` to bypass this step — it prevents macOS from approving the widget extension, which will then be flagged as malware in the widget gallery.

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
# Then approve via System Settings → Privacy & Security → Open Anyway
```

## Architecture

```
TokenEaterApp/           App host (settings, OAuth, menu bar, overlay)
TokenEaterWidget/        Widget Extension (WidgetKit, reactive refresh)
Shared/                  Shared code (services, stores, models, pacing)
  ├── Models/            Pure Codable structs
  ├── Services/          Protocol-based I/O (API, TokenProvider, SharedFile, Notification, SessionMonitor)
  ├── Repositories/      Orchestration (UsageRepository)
  ├── Stores/            ObservableObject state containers
  └── Helpers/           Pure functions (PacingCalculator, MenuBarRenderer, JSONLParser)
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

Anthropic does not currently offer a third-party OAuth flow or scoped API tokens - reading the existing token from the keychain is the only option. If scoped tokens become available, TokenEater will adopt them immediately. The entire codebase is open source and auditable: keychain access is in [`KeychainService.swift`](Shared/Services/KeychainService.swift), API calls in [`APIClient.swift`](Shared/Services/APIClient.swift).

## Troubleshooting

### Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Rate limited" or "API unavailable" | Your OAuth token has hit its per-token request limit | Run `claude /login` in your terminal for a fresh token - TokenEater picks it up automatically |
| Error persists for hours | The app backs off for ~6h after token exhaustion | Click **Retry now** in the menu bar popover after running `claude /login` |
| Keychain popup every few hours | macOS re-validates app signatures after updates | Click **Always Allow** - if it persists, run a clean reset |
| Widget stuck / not updating | macOS caches widget extensions aggressively | Remove the widget, run a clean reset, re-add the widget |
| App flagged as malware in widget gallery | `xattr -cr` was used instead of System Settings approval | Run a clean reset, reinstall, and approve via **System Settings > Privacy & Security > Open Anyway** |

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

