# TokenEater — Setup

Native macOS widget to display Claude usage (session, weekly all models, weekly Sonnet).

## Prerequisites

1. **macOS 14 (Sonoma)** or later
2. **Xcode 15+** installed from the Mac App Store (Xcode 16.4 recommended for validating SwiftUI/Release changes, see [`AGENTS.md`](AGENTS.md) for why)
3. **Homebrew** (for XcodeGen)
4. **Claude Code** installed and authenticated (`claude` then `/login`)

### Install Xcode

```bash
# After installing Xcode.app:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Build

```bash
git clone https://github.com/AThevon/TokenEater.git
cd TokenEater

# Install XcodeGen
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Fix widget Info.plist (XcodeGen strips NSExtension)
plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' \
  TokenEaterWidget/Info.plist 2>/dev/null || true

# Build
xcodebuild -project TokenEater.xcodeproj \
  -scheme TokenEaterApp \
  -configuration Release \
  -derivedDataPath build build
```

### Install

```bash
cp -R "build/Build/Products/Release/TokenEater.app" /Applications/
```

> **Note** - this section covers building from source for local development. The build above is signed with your Apple Development cert (or ad-hoc) and is **not notarized**, so Gatekeeper will block the first launch:
>
> 1. Double-click **TokenEater.app** in Applications - macOS will block it
> 2. Open **System Settings -> Privacy & Security** -> scroll to the TokenEater entry -> click **Open Anyway**
>
> If you want a frictionless install, **download the official notarized DMG from [Releases](https://github.com/AThevon/TokenEater/releases/latest)** instead - it opens directly without any Gatekeeper prompt.

## Configuration

1. Open **TokenEater.app** — the onboarding wizard guides you through setup
2. It reads the OAuth token from Claude Code's Keychain entry automatically
3. Add the widget: **right-click desktop** > **Edit Widgets** > search "TokenEater"

## Structure

```
TokenEaterApp/               App host (menu bar, popover, main window, overlay, onboarding)
  ├── TokenEaterApp.swift       # @main + AppDelegate, store wiring
  ├── StatusBarController.swift # AppKit menu bar item + popover hosting
  ├── MainAppView.swift         # Main floating window (sidebar + sections)
  ├── Popover/                  # Popover dashboard layouts (Classic / Compact / Focus)
  ├── Onboarding/               # Onboarding wizard + cards
  ├── OverlayWindowController.swift, OverlayView.swift  # Agent Watchers overlay
  ├── Resources/                # Sparkle public key + installer applet
  └── TokenEaterApp.entitlements
TokenEaterWidget/            Widget Extension (sandboxed, read-only)
  ├── TokenEaterWidget.swift # @main WidgetBundle (usage + pacing widgets)
  ├── Provider.swift         # TimelineProvider
  ├── *WidgetView.swift      # SwiftUI widget views
  ├── Info.plist
  └── TokenEaterWidget.entitlements
Shared/                      Shared code (compiled into all targets)
  ├── Models/                Pure Codable structs
  ├── Services/              Protocol-based I/O (+ Protocols/)
  ├── Repositories/          UsageRepository (API -> shared file)
  ├── Stores/                ObservableObject state containers
  ├── Helpers/               Pure functions
  ├── Components/            Reusable SwiftUI views (app + widget)
  ├── Design/                Design tokens
  └── en.lproj / fr.lproj    Localization (EN / FR)
```

## API

- **Endpoint**: `GET https://api.anthropic.com/api/oauth/usage`
- **Auth**: `Authorization: Bearer <oauth-token>`
- **Response**:
  - `five_hour.utilization` — Session (5h sliding window)
  - `seven_day.utilization` — Weekly all models
  - `seven_day_sonnet.utilization` — Weekly Sonnet only

The OAuth token is managed by Claude Code and refreshes automatically.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Widget shows error | Reopen the app and check connection in Settings |
| Widget shows "Open app" | Launch the app and complete onboarding |
| Build fails | Verify `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` points to Xcode.app |
| Widget flagged as malware | You're running an ad-hoc local build that stripped its quarantine attrs. Either reinstall via the official notarized DMG from [Releases](https://github.com/AThevon/TokenEater/releases/latest), or rebuild + approve via System Settings -> Privacy & Security -> Open Anyway |
| Widget not visible | Disconnect/reconnect your session or restart |
