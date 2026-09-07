# Troubleshooting

Common fixes first, the full clean reset after. If none of this helps, [open an issue](https://github.com/AThevon/TokenEater/issues/new/choose) with your macOS version, your TokenEater version (shown on the update card in Settings), and what you saw.

## Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Rate limited" or "API unavailable" | Your OAuth token has hit its per-token request limit | Run `claude /login` in your terminal for a fresh token. TokenEater detects the change and recovers automatically within seconds |
| Keychain popup asking to access "Claude Code-credentials" | First run on a new install needs to authorize `/usr/bin/security` to read your Claude Code token | Click **Always Allow** once; it sticks across future app updates |
| Widget stuck or not updating | macOS caches widget extensions aggressively | Remove the widget, run the clean reset below, re-add the widget |
| A session is missing from Agent Watchers | The session runs from an old VSCode extension (2.0.x era), which executes through node and is invisible to the process scanner | Update the Claude Code extension; current versions ship a native binary the scanner detects |
| Widget flagged as malware | You are running an ad-hoc local build without notarization | Reinstall the official notarized DMG from [Releases](https://github.com/AThevon/TokenEater/releases/latest), or approve the local build via System Settings > Privacy & Security > Open Anyway |

## Clean reset

If something is wedged and you want to start fresh, run this in your terminal. It kills all related processes, wipes caches, preferences, and containers, then removes the app:

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

# 5. Wipe WidgetKit caches (critical: macOS keeps old widget binaries here)
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

> Some `Operation not permitted` errors on container metadata files are normal; macOS protects those, but the actual data is cleaned.

## After the reset

Reinstall from the [latest release](https://github.com/AThevon/TokenEater/releases/latest/download/TokenEater.dmg) or via Homebrew, then **remove old widgets from your desktop and add them again** (right-click > Edit Widgets > TokenEater).
