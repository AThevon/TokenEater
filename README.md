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
  <img src="https://img.shields.io/badge/Claude-Pro%20%2F%20Team-D97706" alt="Claude Pro / Team">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/github/v/release/AThevon/TokenEater?color=F97316" alt="Release">
  <a href="https://buymeacoffee.com/athevon"><img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?logo=buymeacoffee&logoColor=black" alt="Buy Me a Coffee"></a>
</p>

---

> **Requires a Claude Pro or Team plan.** The free plan does not expose usage data.

## What is TokenEater?

A native macOS menu bar app + desktop widgets + floating overlay that tracks your Claude AI usage in real-time.

- **Menu bar** — Live percentages, color-coded thresholds, detailed popover dashboard
- **Widgets** — Three WidgetKit widgets (usage gauges, progress bars, pacing)
- **Agent Watchers** — Floating overlay showing active Claude Code sessions with dock-like hover effect. Click to jump to the right terminal.
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

**Prerequisites:** [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated (`claude` then `/login`). Requires a **Pro or Team plan**.

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
TokenEaterWidget/        Widget Extension (WidgetKit, 15-min refresh)
Shared/                  Shared code (services, stores, models, pacing)
  ├── Models/            Pure Codable structs
  ├── Services/          Protocol-based I/O (API, Keychain, SharedFile, Notification, SessionMonitor)
  ├── Repositories/      Orchestration (UsageRepository)
  ├── Stores/            ObservableObject state containers
  └── Helpers/           Pure functions (PacingCalculator, MenuBarRenderer, JSONLParser)
```

The app reads Claude Code's OAuth token from `~/.claude/.credentials.json`, calls the Anthropic usage API, and writes results to a shared JSON file. The widget reads that file — it never touches the network or Keychain. The Agent Watchers overlay scans running Claude Code processes every 2s using macOS system APIs and tail-reads their JSONL logs.

## How it works

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <token>
anthropic-beta: oauth-2025-04-20
```

Returns `utilization` (0–100) and `resets_at` for each limit bucket.

## Support

If TokenEater saves you from hitting your limits blindly, consider [buying me a coffee](https://buymeacoffee.com/athevon) ☕

## License

MIT

