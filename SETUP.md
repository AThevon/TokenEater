# TokenEater — Setup

Native macOS widget to display Claude usage (session, weekly all models, weekly Sonnet).

## Prerequisites

1. **macOS 14 (Sonoma)** or later
2. **Xcode 15+** installed from the Mac App Store
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
xattr -cr /Applications/TokenEater.app
open "/Applications/TokenEater.app"
```

## Configuration

1. Open **TokenEater.app** — the onboarding wizard guides you through setup
2. It reads the OAuth token from Claude Code's Keychain entry automatically
3. Add the widget: **right-click desktop** > **Edit Widgets** > search "TokenEater"

## Structure

```
TokenEaterApp/               App host (settings UI, OAuth auth, menu bar)
  ├── TokenEaterApp.swift
  ├── SettingsView.swift
  └── TokenEaterApp.entitlements
TokenEaterWidget/            Widget Extension
  ├── TokenEaterWidget.swift # Widget entry point
  ├── Provider.swift         # TimelineProvider (15-min refresh)
  ├── UsageEntry.swift       # TimelineEntry
  ├── UsageWidgetView.swift  # SwiftUI view
  ├── Info.plist
  └── TokenEaterWidget.entitlements
Shared/                      Shared code
  ├── Models/                Pure Codable structs
  ├── Services/              Protocol-based I/O
  ├── Repositories/          Orchestration (Keychain → API → SharedFile)
  ├── Stores/                @Observable state containers
  └── Helpers/               Pure functions
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
| Widget not visible | Disconnect/reconnect your session or restart |
