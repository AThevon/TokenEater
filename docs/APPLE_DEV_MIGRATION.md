# Apple Developer Program migration

Notes for future work, written 2026-04-16 at the time of the v5.0.0 release. The Personal Team (free Apple ID) drives every workaround below. Paying for the Apple Developer Program ($99/year) unlocks cleaner alternatives for most of them.

**Who reads this:** future me (or whoever picks this up after the upgrade). The goal is to avoid re-deriving why each workaround exists and to make the cleanup incremental rather than a big-bang refactor.

---

## Current state (v5.0.0)

### Signing

- Ad-hoc signing (`CODE_SIGN_IDENTITY=""` or `"-"`), `TeamIdentifier=not set`
- Users receive `xattr -cr` instructions in the README to bypass Gatekeeper quarantine
- The installer flow re-applies `xattr -cr` during auto-update to avoid re-quarantine after install

### Sandbox

- Main app: `com.apple.security.app-sandbox = true`
- Widget: `com.apple.security.app-sandbox = true` (WidgetKit requires it; no escape there)
- Both use `temporary-exception.files.home-relative-path.read-write` for `/Library/Application Support/com.tokeneater.shared/`
- Main app uses `temporary-exception.files.home-relative-path.read-only` for `/.claude/` and `/Library/Application Support/Claude/`
- `keychain-access-groups` is NOT used (would require a real Team ID)

### Credential access

Three token sources in priority order (see `Shared/Services/TokenProvider.swift:44-68`):

1. `~/.claude/.credentials.json` via `CredentialsFileReader` - works for users on old Claude Code that still wrote the file
2. `~/Library/Application Support/com.tokeneater.shared/keychain-token.json` via `KeychainHelperReader` - written by the **TokenEaterHelper** LaunchAgent added in v5.0.0. Works for users on new Claude Code.
3. `~/Library/Application Support/Claude/config.json` encrypted `oauth:tokenCache`, decrypted via `ElectronDecryptionService` - works for users with Claude Desktop installed
4. Direct `SecItemCopyMatching` on service `"Claude Code-credentials"` - almost never works (Keychain ACL blocks sandboxed ad-hoc apps), but tried as last resort

### The helper (transitional, introduced in v5.0.0)

- `TokenEaterHelper` - non-sandboxed command-line tool embedded in `TokenEater.app/Contents/Library/LoginItems/`
- Shells out to `/usr/bin/security find-generic-password` on a configurable interval
- Loaded via `~/Library/LaunchAgents/com.tokeneater.helper.plist`
- Managed by `HelperManagerService` (install/uninstall/status)
- UI: Settings → Credentials section; first-run banner in popover

### App/widget data sharing

- No App Groups (free tier cannot use them on macOS Sequoia)
- Shared JSON file at `~/Library/Application Support/com.tokeneater.shared/shared.json`, written by the app, read by the widget
- Both sides use `temporary-exception.files.home-relative-path.read-write` in entitlements

### Update flow

- Auto-updater uses Sparkle appcast at `https://raw.githubusercontent.com/AThevon/TokenEater/main/docs/appcast.xml`
- EdDSA signature verification was added in v5.0.0 (see `SignatureVerifier`)
- Installation uses `TokenEaterInstaller.app` (an AppleScript applet compiled at build time via `osacompile`) to run privileged commands: mount DMG, copy to `/Applications`, run `xattr -cr`

---

## What the Developer Program unlocks

### Real Team ID and automatic code signing

- `CODE_SIGN_STYLE=Automatic` with real `DEVELOPMENT_TEAM`
- Hardened Runtime (`com.apple.security.cs.*` entitlements)
- Notarization via `xcrun notarytool`
- Stapled tickets - users no longer need `xattr -cr`
- Gatekeeper passes on first launch

### App Groups (for app ↔ widget sharing)

- Real `group.com.tokeneater` App Group
- `NSUbiquitousContainer` or `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` returns a usable URL on both ends
- Can drop all `temporary-exception.files.home-relative-path.*` entitlements
- `UserDefaults(suiteName: "group.com.tokeneater")` works properly (currently broken because `cfprefsd` validates provisioning)

### Keychain access groups (indirect relevance)

- **Does NOT solve Claude Code credential access** - that's gated by Anthropic's Keychain item ACL (whitelist `/usr/bin/security`), not by our signing identity
- But does allow cleaner sharing between any future TokenEater-owned Keychain items (currently there are none)

### Main app desandboxing option

- App Store distribution requires sandbox; direct Mac distribution (the current model via GitHub release + Homebrew cask) does NOT require sandbox
- With Developer ID + Hardened Runtime, the main app can be desandboxed while keeping the widget sandboxed (WidgetKit still requires it on the extension)
- A desandboxed app can shell out directly to `/usr/bin/security find-generic-password` - no helper needed

---

## Migration plan (target: v5.1.0 or v6.0.0 depending on scope)

### Phase 1 - Signing and notarization (low risk, pure win)

- [ ] Add `DEVELOPMENT_TEAM` to `project.yml` (either directly, or via environment variable like today)
- [ ] Set `CODE_SIGN_STYLE=Automatic` and `CODE_SIGN_IDENTITY="Apple Development"` (Debug) / `"Developer ID Application"` (Release)
- [ ] Enable Hardened Runtime entitlements:
  - `com.apple.security.cs.allow-jit = true` (only if needed - unlikely here)
  - `com.apple.security.cs.disable-library-validation = false`
  - `com.apple.security.cs.allow-unsigned-executable-memory = false`
- [ ] Update `.github/workflows/release.yml`:
  - Add a Keychain profile with the Developer ID certificate as a GitHub secret
  - After build, run `xcrun notarytool submit TokenEater.dmg --apple-id --team-id --password --wait`
  - Run `xcrun stapler staple TokenEater.dmg`
- [ ] Update README: remove the `xattr -cr` instructions; keep a "Troubleshooting Gatekeeper" section for edge cases
- [ ] Update `UpdateStore.installUpdate()`: remove the `xattr -cr` line from `installScript` (step 4 in the bash template). Quarantine will no longer be set for notarized DMGs.

### Phase 2 - App Groups (drops temp-exception entitlements)

- [ ] Register App Group `group.com.tokeneater` in the Developer Portal
- [ ] Add the App Group entitlement to both the main app and the widget
- [ ] Rewrite `SharedFileService` to use `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.tokeneater")` for the shared directory
- [ ] Migrate existing users: on first launch, copy `~/Library/Application Support/com.tokeneater.shared/*` to the new container location. Keep a compatibility read path for one or two releases.
- [ ] Remove `temporary-exception.files.home-relative-path.read-write` from both entitlements files
- [ ] Remove the `rm -rf ~/Library/Application\ Support/com.tokeneater.shared` step from the dev nuke one-liner in `CLAUDE.md` (or update it to target the new container path)

### Phase 3 - Decide on helper vs desandboxed main app

Two options, pick one:

**Option A: desandbox the main app, delete the helper**

- [ ] Remove `com.apple.security.app-sandbox = true` from `TokenEaterApp.entitlements` (keep it on the widget)
- [ ] Remove all `temporary-exception.*` entitlements from the main app (no longer relevant outside sandbox)
- [ ] Add direct shell-out to `/usr/bin/security` in `TokenProvider`:
  ```swift
  private func readKeychainDirect() -> String? {
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
      task.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
      // ...
  }
  ```
- [ ] Delete `TokenEaterHelper/` target and all files
- [ ] Delete `Shared/Services/KeychainHelperReader.swift`
- [ ] Delete `Shared/Services/HelperManagerService.swift`
- [ ] Delete `TokenEaterApp/CredentialsSectionView.swift`
- [ ] Delete `TokenEaterApp/HelperInstallBanner.swift`
- [ ] Delete `TokenEaterApp/Resources/com.tokeneater.helper.plist.template`
- [ ] Remove helper-related strings from `Localizable.strings`
- [ ] Remove helper build steps from `.github/workflows/release.yml`
- [ ] Remove helper settings from `SettingsStore`
- [ ] Migration for existing installs: on first launch after upgrade, call `HelperManagerService.uninstall()` (before deleting the service), to clean up the user's LaunchAgent. Keep the service around for one release purely for this cleanup.
- [ ] Update `TokenProvider.currentToken()` source order: remove the `KeychainHelperReader` step, rely on direct shell-out instead

**Option B: keep the helper, widen its role**

- [ ] Sign the helper binary properly with the Developer ID (currently inherits ad-hoc)
- [ ] Add CPU/memory limits to the LaunchAgent plist for good citizenship
- [ ] Potentially adopt `SMAppService` API (macOS 13+) for cleaner install/uninstall without the user admin prompt

Option A is the recommended path because it removes ~500-700 lines of code, eliminates the admin prompt from first-run, and matches how other menu bar apps (Rectangle, AlDente, Stats) read Keychain items. Keep this doc around as "how we did it in v5.0.0".

### Phase 4 - UpdateStore cleanup

The current `UpdateStore.installUpdate()` uses a convoluted AppleScript installer (`TokenEaterInstaller.app`) to get admin privileges. With notarization + stapling:

- [ ] Gatekeeper no longer blocks the copy, so no `xattr -cr` needed
- [ ] Could replace the AppleScript installer with a simpler approach: either Sparkle's built-in installer (which handles all of this), or a direct `NSWorkspace.shared.open(…, withApplicationAt:)` that moves the app in place before relaunching
- [ ] Consider just adopting Sparkle proper (the real framework, not the appcast parsing we do manually). Sparkle's installer handles update-in-place, signature verification, pre/post-install hooks, all with less custom code.

This is a nice-to-have, not a blocker. Current homegrown flow works; Sparkle adoption is a v6.x consideration.

### Phase 5 - CLAUDE.md updates

- [ ] Remove the sections about Personal Team restrictions and `temporary-exception` workarounds
- [ ] Update the "Notes techniques" block: `UserDefaults(suiteName:)` now works; `FileManager.containerURL(...)` now returns a usable URL
- [ ] Replace the build commands to use the signed workflow
- [ ] Update the mega-nuke one-liner to purge the new container location and drop helper cleanup

---

## What NOT to change

Not everything needs updating just because we have more capabilities. Keep:

- **Protocol-oriented services and MV pattern**: `ObservableObject` + `@Published`. The `@Observable` ban is NOT related to signing or sandbox - it's a Swift 6.1.x compiler bug with our CI toolchain. Do not flip.
- **Widget's sandbox**: WidgetKit still requires it. Widget entitlements don't change meaningfully (App Groups replace temp-exceptions, that's it).
- **Homebrew cask distribution**: notarization strengthens this but doesn't replace it.
- **Ad-hoc signing as a fallback in test-build.yml**: keep the ability to produce a test build without the real cert, for contributors without Developer Program membership.

---

## Cost estimates

Rough effort (single developer, focused time):

| Phase | Estimate | Risk |
|-------|----------|------|
| 1 - Signing + notarization | 1-2 days | Low (well-documented) |
| 2 - App Groups | 1 day | Low, mainly migration logic |
| 3A - Desandbox + delete helper | 2-3 days | Medium (touches token source, needs careful migration for existing helper users) |
| 3B - Keep helper cleanly signed | 0.5 day | Low |
| 4 - UpdateStore cleanup | 1-3 days | Low for cleanup; medium if adopting Sparkle proper |
| 5 - CLAUDE.md updates | 0.5 day | Trivial |

Total for recommended path (1 + 2 + 3A + 5): ~4-6 days.

---

## Checklist when starting

Before beginning migration, verify:

- [ ] Apple Developer Program membership is active
- [ ] `xcode-select -p` points to Xcode 16.4 (or validated newer)
- [ ] `security find-identity -v -p codesigning` lists both `Apple Development` and `Developer ID Application` certs
- [ ] A spare test Mac or fresh user account to validate notarization + install without muscle-memory interfering
- [ ] The current v5.0.0 release is stable in the wild (no regression reports pending) - migration is a major version bump
