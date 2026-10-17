# Troubleshooting

Common fixes first, the full clean reset after. If none of this helps, [open an issue](https://github.com/AThevon/TokenEater/issues/new/choose) with your macOS version, your TokenEater version (shown on the update card in Settings), and what you saw.

## Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Rate limited" or "API unavailable" | Your OAuth token has hit its per-token request limit | Run `claude /login` in your terminal for a fresh token. TokenEater detects the change and recovers automatically within seconds |
| Keychain popup asking to access "Claude Code-credentials" | TokenEater reads your Claude Code token through Apple's `/usr/bin/security`, and macOS asks before allowing it | Click **Always Allow** in the dialog that names `security`. TokenEater never asks for that item in its own name: a dialog that names TokenEater and keeps coming back came from older versions, so update TokenEater |
| "Your Claude Code login expired" in the popover or dashboard | Claude Code renews its saved login only when the CLI runs, so working only in the Claude desktop app lets it expire. TokenEater only reads that login and never renews it | Run `claude` once in a terminal, or open Claude Code, then click **Retry now** in the popover. For an account kept in another config folder, run `CLAUDE_CONFIG_DIR=<folder> claude` instead (the banner shows the exact command) |
| Codex shows not logged in or login expired | The CLI has no usable file-backed ChatGPT access token, or it expired | Open Codex or run `codex login`, then retry in Providers. API-key and keyring-only logins are not supported; TokenEater never refreshes or rewrites the CLI token |
| Codex widget is empty or off | Tracking is disabled, no successful sync exists, or WidgetKit has cached the old extension | Enable it in Settings > Providers and refresh Monitoring. Add **Codex Usage** from Edit Widgets > TokenEater; if still stale, use the reset below |
| Widget stuck or not updating | macOS caches widget extensions aggressively | Remove the widget, run the clean reset below, re-add the widget |
| A session is missing from Agent Watchers | The session runs from an old VSCode extension (2.0.x era), which executes through node and is invisible to the process scanner | Update the Claude Code extension; current versions ship a native binary the scanner detects |
| "No login for this exact folder" when adding a Claude account, or "No login in this folder" for a main account on a custom folder | Claude Code names a folder's Keychain item after the `CLAUDE_CONFIG_DIR` value exactly as typed. TokenEater tries the usual spellings (trailing slash, `~`, symlinks), but a login made under another spelling, or no login at all, is not found | Run the command TokenEater shows (`CLAUDE_CONFIG_DIR=<folder> claude`), type `/login`, then connect again. If you launch Claude Code with an unusual spelling of the path, log in once with the command shown |
| macOS asks for Keychain access when you connect a Claude account | Each config folder has its own Keychain item, and macOS asks once per item | Click **Always Allow** in the dialog that names `security`. TokenEater asks only when you click Connect, never at launch |
| "This folder signs in to the same account as …" when connecting | That folder holds a login already tracked under another folder, the main one included | Log in to the other account in that folder (`CLAUDE_CONFIG_DIR=<folder> claude`, then `/login`), then connect again |
| "This folder now signs in to another account" | With two accounts or more, each one stays tied to the login it was connected with, and its folder now holds another one (a `/login` with another account, an account switcher) | Log back in to the right account in that folder, or click **Use this account** in the account's row to keep the new login under that name |
| "Your main login now points to …", or "This folder now signs in to …, which is already tracked" | The folder now holds the login of another tracked account, so TokenEater shows nothing under this name rather than count that account twice | Switch that folder back to its own login (for the main account, `claude` then `/login`, or your account switcher) |
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
USERBASE=$(getconf DARWIN_USER_DIR)
rm -rf "${TMPBASE}com.apple.chrono" "${CACHEBASE}com.apple.chrono" "${USERBASE}com.apple.chrono" 2>/dev/null
rm -rf "${CACHEBASE}com.tokeneater.app" "${CACHEBASE}com.claudeusagewidget.app" 2>/dev/null

# 6. Unregister widget plugins
pluginkit -r -i com.tokeneater.app.widget 2>/dev/null
pluginkit -r -i com.claudeusagewidget.app.widget 2>/dev/null

# 7. Remove the app
rm -rf /Applications/TokenEater.app
```

> Some `Operation not permitted` errors on container metadata files are normal; macOS protects those, but the actual data is cleaned.

The shared-data removal also deletes `codex.json` (Codex usage and widget state) and the files of additional Claude accounts (`shared-acct-*.json`, `history-cache.acct-*.json`). It does not remove `~/.codex/auth.json` or sign you out of Codex. The list of tracked Claude accounts lives in the preferences wiped in step 2, so you add those accounts again after a reset; Claude Code's own folders and logins are never touched.

## After the reset

Reinstall from the [latest release](https://github.com/AThevon/TokenEater/releases/latest/download/TokenEater.dmg) or via Homebrew, then **remove old widgets from your desktop and add them again** (right-click > Edit Widgets > TokenEater).
