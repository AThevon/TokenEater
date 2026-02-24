# Auto-Update System Design

## Context

TokenEater is distributed via Homebrew Cask (`brew install --cask tokeneater`) through a custom tap (`AThevon/homebrew-tokeneater`). Users currently have no way to know a new version exists without manually running `brew outdated` or checking GitHub. The app is sandboxed (Personal Team signing, no Apple Developer Program).

**Goal**: Semi-automatic update flow — the app detects new versions, shows a modal with release notes, and the user clicks "Update" to trigger a seamless `brew upgrade`.

## Constraints

- App is sandboxed (`com.apple.security.app-sandbox: true`)
- Personal Team signing (no Developer ID, no notarization)
- No `Process` execution to modify `/Applications/` from sandbox
- Existing entitlements: `network.client` + `temporary-exception.files.home-relative-path.read-write` for `~/Library/Application Support/com.tokeneater.shared/`
- Zero external dependencies (no SPM, no Sparkle)
- Widget is not impacted

## Architecture

```
                    +---------------+
                    |  GitHub API   |
                    |  /releases/   |
                    +-------+-------+
                            | GET latest
                    +-------v-------+
                    | UpdateService |  (protocol-based)
                    +-------+-------+
                            |
                    +-------v-------+
                    |  UpdateStore  |  (@Observable, @Environment)
                    +-------+-------+
                            |
              +-------------+-------------+
              |             |             |
      +-------v--+  +------v------+  +---v-----------+
      | Settings |  |   Update    |  |  Auto-check   |
      |  badge   |  |   Modal     |  |  on launch    |
      +----------+  +------+------+  +---------------+
                           | "Update" clicked
                    +------v--------------+
                    | Write .command to    |
                    | ~/App Support/...   |
                    +------+--------------+
                           | NSWorkspace.open
                    +------v------+
                    |  Terminal   |
                    | brew upgrade --cask |
                    +------+------+
                           |
                    +------v------+
                    |  Relaunch   |
                    +-------------+
```

## 1. Version Detection (GitHub API)

New `UpdateService` (protocol-based) queries the GitHub Releases API.

- **Endpoint**: `GET https://api.github.com/repos/AThevon/TokenEater/releases/latest`
- **Version comparison**: `tag_name` (e.g. `"v4.1.0"`) vs `Bundle.main.infoDictionary["CFBundleShortVersionString"]`
- **Frequency**: on app launch + every 6 hours (Timer)
- **Persistence**: `lastCheckDate` and `skippedVersion` in UserDefaults
- Works from sandbox via existing `network.client` entitlement
- GitHub API rate limit: 60 req/hour unauthenticated (more than enough for every-6h checks)

## 2. State Management (UpdateStore)

New `@Observable` store injected via `@Environment`:

```
UpdateStore (@Observable)
├── updateAvailable: Bool
├── latestVersion: String?
├── releaseNotes: String?        // GitHub Release body (markdown)
├── downloadURL: URL?            // Asset URL (for fallback)
├── isChecking: Bool
├── isUpdating: Bool
├── updateError: String?
├── skippedVersion: String?      // UserDefaults — persisted
│
├── checkForUpdate()             // Calls UpdateService
├── performUpdate()              // Writes script + opens Terminal
└── skipCurrentUpdate()          // Persists skipped version
```

If `skippedVersion == latestVersion`, no automatic modal. User can still check manually from Settings.

## 3. UI

### Update Modal (sheet)

Dark-themed sheet matching existing `guideSheet` style:

- Header: current version → new version
- Scrollable release notes (markdown from GitHub Release body)
- Three buttons: "Skip this version", "Later", "Update"
- Progress indicator when updating

### Settings Integration

- Version display uses `Bundle.main.infoDictionary["CFBundleShortVersionString"]` (no longer hardcoded)
- Orange "New" badge next to version when update is available (clickable → reopens modal)
- "Check for updates" button in connection tab

### Trigger

- Modal pops automatically **once** on launch if update available (and not skipped)
- No repeated pop-ups within a session

## 4. Update Mechanism (.command file)

The sandbox prevents direct `Process` execution for `brew upgrade`. The solution uses a `.command` shell script:

1. App writes `update.command` to `~/Library/Application Support/com.tokeneater.shared/`
2. Sets executable permission via `FileManager.setAttributes([.posixPermissions: 0o755])`
3. Opens via `NSWorkspace.shared.open(URL(fileURLWithPath: path))` — macOS opens `.command` files with Terminal
4. App quits itself
5. Terminal runs the script:

```bash
#!/bin/bash
# TokenEater Auto-Update

# Detect brew path (Apple Silicon vs Intel)
if [ -x "/opt/homebrew/bin/brew" ]; then
    BREW="/opt/homebrew/bin/brew"
elif [ -x "/usr/local/bin/brew" ]; then
    BREW="/usr/local/bin/brew"
else
    echo "Homebrew not found."
    echo "Run manually: brew upgrade --cask tokeneater"
    read -p "Press Enter to close..."
    exit 1
fi

echo "Updating TokenEater..."
$BREW upgrade --cask tokeneater

if [ $? -eq 0 ]; then
    echo "Done! Relaunching..."
    sleep 1
    open /Applications/TokenEater.app
else
    echo "Update failed. Try: brew upgrade --cask tokeneater"
    read -p "Press Enter to close..."
fi

# Self-cleanup
rm -f "$0"
```

### Why this works

| Point | Explanation |
|-------|-------------|
| No extra entitlement | Writes to already-authorized directory, `NSWorkspace.open` is allowed from sandbox |
| No quarantine | File is created locally (not downloaded), no Gatekeeper flag |
| Clean replacement | `brew upgrade --cask` removes old .app and installs new one — zero residue |
| Self-cleanup | Script deletes itself after execution |
| ARM + Intel | Detects both Homebrew paths |
| Error handling | Clear fallback message if brew not found |

## 5. Homebrew Cask Integration

Add `auto_updates true` to `Casks/tokeneater.rb` in the `homebrew-tokeneater` tap. This tells Homebrew the app manages its own updates, preventing conflicts with `brew upgrade` global runs.

## Files to Create/Modify

| File | Action |
|------|--------|
| `Shared/Services/UpdateService.swift` | Create — GitHub API call + response parsing |
| `Shared/Services/Protocols/UpdateServiceProtocol.swift` | Create — protocol for testability |
| `Shared/Stores/UpdateStore.swift` | Create — @Observable state container |
| `Shared/Models/UpdateModels.swift` | Create — GitHubRelease Codable struct |
| `TokenEaterApp/UpdateModalView.swift` | Create — update sheet UI |
| `TokenEaterApp/TokenEaterApp.swift` | Modify — init UpdateStore + auto-check on launch |
| `TokenEaterApp/SettingsView.swift` | Modify — dynamic version + badge + check button |
| Cask `tokeneater.rb` (external tap) | Modify — add `auto_updates true` |

## What Doesn't Change

- No entitlements added
- No SPM dependencies
- Widget not impacted
- CI/CD workflow unchanged (release.yml continues pushing versions normally)
- Existing stores/services untouched
