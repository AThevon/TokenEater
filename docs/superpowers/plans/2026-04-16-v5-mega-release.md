# TokenEater v5.0.0 Release - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Each PR is independently shippable, merge in the order below.

**Goal:** Ship a bundle release closing GitHub issues #127 (security), #128 (Keychain), #129 (perf) and #130 (UX), plus the community PR #126 (per-bucket pacing).

**Architecture:** 5 independent PRs merged sequentially. Security fix ships first because it is critical. Perf fix is cheap and independent. External PR 126 is rebased before touching the settings UI (130 depends on its code). Keychain helper (128) is the largest PR, involves a new build target. UX PR (130) is last to avoid conflicts with 126 and 128 changes to SettingsStore.

**Tech Stack:** Swift 6.1.2 / Xcode 16.4 / SwiftUI / ObservableObject + @Published (no @Observable - see CLAUDE.md) / Sparkle EdDSA (verified with CryptoKit Curve25519) / LaunchAgent helper / launchctl / FileManager + URLResourceValues.

---

## Release metadata

- Version: **v5.0.0** (major bump: new helper binary, settings schema additions, breaking visual defaults on menu bar format if user opts in to new format)
- CI target: Xcode 16.4 on `macos-15` runner (unchanged)
- Contributors credited in release notes:
  - jescoti (#127 + #129 reports and fix proposals)
  - shuhulx (#128 root cause analysis)
  - conchoecia (#128 additional Claude Desktop context)
  - jeromeajot (#130 feature request)
  - Humboldt94 (#126 PR author)

Co-author attribution (to include in git commits):
| User | Email |
|------|-------|
| jescoti | `5825573+jescoti@users.noreply.github.com` |
| shuhulx | `106345809+shuhulx@users.noreply.github.com` |
| conchoecia | `darrints@stanford.edu` (public profile email) |
| jeromeajot | `351091+jeromeajot@users.noreply.github.com` |
| Humboldt94 | `128601667+Humboldt94@users.noreply.github.com` |

---

## Mac execution checkpoints

User works in Fedora KDE for planning/code, physically grabs the Mac to run Release builds + install + validate UI. Each PR has a checkpoint before being merged.

| # | When | Action on Mac |
|---|------|---------------|
| 0 | Before anything | Grab Mac, `cd ~/projects/tokeneater`, `git fetch origin main`. Verify `xcodebuild -version` returns 16.4 and `DEVELOPER_DIR` is set correctly (cf. CLAUDE.md) |
| 1 | After PR 127 code pushed | Build Release + run the existing 80 tests + new signature-verifier tests. Simulate: a "bad" signature should fail install, a "good" signature should pass |
| 2 | After PR 129 code pushed | Benchmark: `find ~/.claude/projects -name "*.jsonl" | wc -l` then enable Session Monitor, measure CPU in Activity Monitor before/after. Target: <5% CPU steady state on 4k files |
| 3 | After PR 126 rebased | Full `nuke` one-liner from CLAUDE.md, verify per-bucket pacing displays correctly in menu bar and dashboard. Verify no CPU spike from `@Observable` regression (should not exist, but rule #1) |
| 4 | After PR 128 code pushed | Delete `~/.claude/.credentials.json` if present. Install helper via app CTA. Verify token is read from Keychain within 10s. Uninstall helper, verify cleanup |
| 5 | After PR 130 code pushed | Cycle through reset format options (relative/absolute/both), switch colors, verify menu bar updates in real-time |
| 6 | Before tag v5.0.0 | Run `test-build.yml` iso-prod workflow. Download DMG. Mega-nuke (cf. CLAUDE.md). Install. Validate whole flow end-to-end on a cold user state |

---

## PR order & dependencies

```
main
 │
 ├─── PR 127 (security) ────────┐
 │                              │
 ├─── PR 129 (perf) ────────────┤  (no dependency)
 │                              │
 ├─── PR 126 rebase (ext PR) ───┤  (rebase from Humboldt94's branch)
 │                              │
 ├─── PR 128 (keychain helper) ─┤  (no dependency, just sized to be last-major)
 │                              │
 └─── PR 130 (UX reset time) ───┘  (depends on 126 merged for per-bucket metric IDs)
```

Merge sequentially. Between each merge, rebase the next branch on updated main.

---

## PR 1: Sparkle EdDSA signature verification (#127)

**Branch:** `fix/sparkle-edsignature-verification`
**Priority:** critical (security RCE)
**Size:** small-medium (~150 lines + tests)

### Context

The release workflow (`.github/workflows/release.yml:90-100`) generates an EdDSA signature using Sparkle's `sign_update` tool and writes `sparkle:edSignature="..."` into each `<enclosure>` of `docs/appcast.xml:L115`. But `AppcastXMLParser` in `Shared/Services/UpdateService.swift:79-140` only parses `sparkle:version` and the enclosure `url`. **The signature is never read, never verified.**

`UpdateStore.installUpdate()` in `Shared/Stores/UpdateStore.swift:73-153` writes a bash script to a shared dir and launches `TokenEaterInstaller.app` (pre-built AppleScript). The installer runs with admin privileges and:
1. Mounts the DMG
2. `rm -rf /Applications/TokenEater.app`
3. `cp -R` the new app
4. `xattr -cr` (strips Gatekeeper quarantine)

A compromised DMG URL or tampered appcast.xml = root code execution on all users without any integrity check.

### Files

**Modify:**
- `Shared/Services/UpdateService.swift` - add `edSignature` and `length` parsing in `AppcastXMLParser`, extend `AppcastItem` model
- `Shared/Models/` (new file: `AppcastItem.swift` if not already a dedicated model, else add fields)
- `Shared/Stores/UpdateStore.swift:73-93` - insert signature verification before copying DMG to shared dir
- `.github/workflows/release.yml` - no change needed (signature already generated)

**Create:**
- `Shared/Services/SignatureVerifier.swift` - new service with `verifyEd25519(signature:base64:data:publicKey:) -> Bool` using `CryptoKit.Curve25519.Signing.PublicKey.isValidSignature(_:for:)`
- `Shared/Services/Protocols/SignatureVerifierProtocol.swift` - for testability
- `TokenEaterApp/Resources/SparklePublicKey.txt` (or similar) - the EdDSA public key in base64, shipped in the bundle
- `TokenEaterTests/SignatureVerifierTests.swift` - unit tests with known good/bad signatures
- `TokenEaterTests/AppcastXMLParserTests.swift` - if not already existing

### Tasks

- [ ] **1.1 Find the Sparkle EdDSA public key**

The private key is in `secrets.SPARKLE_PRIVATE_KEY` of the GitHub repo. The public key must be derived from it. Either:
- Ask the user to run locally: `echo "$SPARKLE_PRIVATE_KEY" | /tmp/bin/generate_keys -p` (Sparkle's tool)
- Or regenerate a fresh keypair if the public key was never saved (will invalidate all past signed releases, but none of them are currently verified so no user impact)

Store the public key in `TokenEaterApp/Resources/SparklePublicKey.txt` (plain base64 string, no newline).

- [ ] **1.2 Extend `AppcastItem` model**

```swift
struct AppcastItem {
    let version: String
    let downloadURL: URL
    let edSignature: String?   // NEW
    let expectedLength: Int64? // NEW
}
```

- [ ] **1.3 Parse signature and length in `AppcastXMLParser`**

In `Shared/Services/UpdateService.swift`, within `didStartElement`, when `name == "enclosure"`:

```swift
if name == "enclosure" {
    currentURL = attributeDict["url"]
    currentSignature = attributeDict["sparkle:edSignature"]
    currentLength = attributeDict["length"].flatMap(Int64.init)
}
```

Add `currentSignature: String?` and `currentLength: Int64?` as parser instance vars, reset in `didStartElement` on `item`, bundled into `AppcastItem` in `didEndElement` on `item`.

- [ ] **1.4 Create `SignatureVerifier`**

```swift
import Foundation
import CryptoKit

protocol SignatureVerifierProtocol {
    func verify(data: Data, base64Signature: String, base64PublicKey: String) -> Bool
}

final class SignatureVerifier: SignatureVerifierProtocol {
    func verify(data: Data, base64Signature: String, base64PublicKey: String) -> Bool {
        guard let sigData = Data(base64Encoded: base64Signature),
              let keyData = Data(base64Encoded: base64PublicKey),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { return false }
        return publicKey.isValidSignature(sigData, for: data)
    }
}
```

- [ ] **1.5 Wire verification into `UpdateStore.installUpdate()`**

At the top of `installUpdate()`, before copying the DMG:

```swift
guard case .downloaded(let dmgURL, let signature, let expectedLength) = updateState else { return }

// Verify length
if let expected = expectedLength,
   let actual = try? FileManager.default.attributesOfItem(atPath: dmgURL.path)[.size] as? Int64,
   actual != expected {
    updateState = .error("DMG size mismatch - aborting install")
    return
}

// Verify signature (fail-closed)
guard let dmgData = try? Data(contentsOf: dmgURL),
      let signature = signature,
      let publicKeyURL = Bundle.main.url(forResource: "SparklePublicKey", withExtension: "txt"),
      let publicKey = try? String(contentsOf: publicKeyURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
      signatureVerifier.verify(data: dmgData, base64Signature: signature, base64PublicKey: publicKey)
else {
    updateState = .error("Signature verification failed - aborting install")
    return
}
```

Note: `UpdateState.downloaded` needs to carry signature + length through the download flow. Modify `downloadUpdate()` accordingly to pass them from `AppcastItem`.

- [ ] **1.6 Write tests**

`TokenEaterTests/SignatureVerifierTests.swift`:
```swift
@Test func acceptsValidSignature() { ... }
@Test func rejectsInvalidSignature() { ... }
@Test func rejectsMalformedBase64() { ... }
@Test func rejectsEmptyInputs() { ... }
```

`TokenEaterTests/AppcastXMLParserTests.swift`:
```swift
@Test func parsesEdSignatureAttribute() { ... }
@Test func parsesLengthAttribute() { ... }
@Test func handlesMissingSignature() { ... }  // nil, not crash
```

Use known Ed25519 test vectors (RFC 8032) for deterministic verification tests.

- [ ] **1.7 Mac checkpoint 1**

Build Release with Xcode 16.4. Manual test: edit the local `docs/appcast.xml` to put a garbage `sparkle:edSignature="AAAA..."`. Launch TokenEater, trigger update check. The update should be detected, downloaded, then rejected with "Signature verification failed".

- [ ] **1.8 Commit + PR**

```bash
git add <files>
git commit -m "$(cat <<'EOF'
fix: verify Sparkle EdDSA signature before installing update

The auto-updater previously parsed only sparkle:version and the enclosure
URL, ignoring the sparkle:edSignature attribute that the release workflow
already generates. A compromised DMG at the release URL or a tampered
appcast.xml would execute as root during install, bypassing Gatekeeper
quarantine.

Now AppcastXMLParser reads the signature and expected length. Before
handing the DMG to the privileged installer, UpdateStore verifies the
Ed25519 signature using CryptoKit against the bundled public key, and
fails closed if anything is off.

Closes #127

Co-authored-by: jescoti <5825573+jescoti@users.noreply.github.com>
EOF
)"

gh pr create --title "fix: verify Sparkle EdDSA signature before installing update" --body "..."
```

PR body template:
```markdown
## Summary

Closes #127. The Sparkle EdDSA signature was being generated by the release workflow but never verified on the client side. This PR adds the missing verification step.

## Changes

- `AppcastXMLParser` now parses `sparkle:edSignature` and `length` attributes from the enclosure element
- New `SignatureVerifier` service using `CryptoKit.Curve25519`
- `UpdateStore.installUpdate()` verifies length + Ed25519 signature before invoking the privileged installer; fails closed on any mismatch
- Public key shipped as `Resources/SparklePublicKey.txt`
- Added unit tests covering valid / invalid / malformed signatures

## Test plan

- [x] Unit tests pass (`xcodebuild test`)
- [x] Release build succeeds with Xcode 16.4
- [ ] Manual: tamper appcast.xml with a wrong signature, confirm install is aborted with a clear error message
- [ ] Manual: legitimate release passes verification and installs normally

Credit to @jescoti for the security report.
```

---

## PR 2: Session Monitor perf optimization (#129)

**Branch:** `fix/session-monitor-perf`
**Priority:** medium (high for power users with lots of Claude history)
**Size:** small (~50 lines + benchmark test)

### Context

`SessionMonitorService.scan()` in `Shared/Services/SessionMonitorService.swift:48-164` runs every 2s. For each project dir in `~/.claude/projects/`, it:
1. Lists JSONL files with `includingPropertiesForKeys: [.contentModificationDateKey]` (line 99) - hint pre-fetches mtime into the URL
2. **But then discards the pre-fetched values** and calls `fm.attributesOfItem(atPath:)` **inside the sort comparator** (lines 104-107), so each file is `stat`-ed O(N log N) times per scan

With 66 project dirs and 4,204 JSONL files (from reporter's machine), this means ~50k syscalls per 2s tick = 120% CPU steady state.

### Files

**Modify:**
- `Shared/Services/SessionMonitorService.swift:48-164` - fix the sort and add project dir mtime filter

**Create:**
- `TokenEaterTests/SessionMonitorPerfTests.swift` - regression test with synthetic filesystem

### Tasks

- [ ] **2.1 Replace sort with decorate-sort-undecorate using URLResourceValues**

In `scan()`, replace lines 97-108 with:

```swift
let jsonlFiles: [(url: URL, mtime: Date)]
do {
    let urls = try fm.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
    ).filter { $0.pathExtension == "jsonl" }

    jsonlFiles = urls.map { url in
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return (url, mtime)
    }
} catch { continue }

let sorted = jsonlFiles.sorted { $0.mtime > $1.mtime }.map(\.url)
```

Each file's mtime is read exactly once via the cached URL resource values, not via `stat` inside the comparator.

- [ ] **2.2 Use URLResourceValues for the matched-file mtime too**

Line 117 currently does another `attributesOfItem`. Replace:

```swift
let modDate = sorted.first { $0 == file }.flatMap {
    try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
} ?? Date()
```

Better: change `sorted` to carry the tuple through and read `mtime` directly from the tuple in the matching loop.

- [ ] **2.3 Add project dir mtime filter**

Before entering the inner JSONL loop, skip dirs whose own mtime is older than N minutes (sessions have to write into the dir when they log, so stale dirs can be skipped).

Choose `N = 30 minutes`: covers idle breaks without missing anything (sessions write frequently).

After line 95 (`let sortedDirs = ...`), add:

```swift
let freshnessThreshold = Date().addingTimeInterval(-30 * 60)
let sortedDirs = projectDirs
    .filter { $0.hasDirectoryPath }
    .filter { dir in
        // Skip dirs that haven't been touched recently
        let mtime = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return mtime > freshnessThreshold
    }
    .sorted { $0.lastPathComponent.count > $1.lastPathComponent.count }
```

This requires `includingPropertiesForKeys: [.contentModificationDateKey]` on the outer `contentsOfDirectory` at line 77-80, currently `nil`. Update to:

```swift
guard let projectDirs = try? fm.contentsOfDirectory(
    at: projectsDir,
    includingPropertiesForKeys: [.contentModificationDateKey],
    options: .skipsHiddenFiles
) else { ... }
```

- [ ] **2.4 Write perf regression test**

`TokenEaterTests/SessionMonitorPerfTests.swift`:

```swift
import Testing
import Foundation
@testable import TokenEater

@MainActor
struct SessionMonitorPerfTests {
    @Test func scanStaysFastWithManyDirs() async throws {
        // Create temp projects dir with 50 subdirs, 20 JSONLs each = 1000 files
        let tmpDir = try makeSyntheticProjects(dirCount: 50, filesPerDir: 20)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let service = SessionMonitorService(scanInterval: 999, claudeProjectsDir: tmpDir)

        let start = ContinuousClock.now
        service.scanForBenchmark()  // expose scan() as internal for tests
        let duration = ContinuousClock.now - start

        #expect(duration < .milliseconds(50), "scan took \(duration), expected <50ms")
    }
}
```

This requires exposing `claudeProjectsDir` and `scan()` for testing (use `internal` + a test-only init override, or `@testable` access).

- [ ] **2.5 Mac checkpoint 2**

Measure Activity Monitor CPU before/after on user's actual machine. Target: <5% steady state with Session Monitor enabled, vs 120% before. If user has <1000 JSONLs, measurement is less dramatic but should still drop significantly.

- [ ] **2.6 Commit + PR**

```bash
git commit -m "$(cat <<'EOF'
perf: reduce Session Monitor syscalls by 50x on heavy users

SessionMonitorService.scan() was stat-ing every JSONL file inside the sort
comparator (O(N log N) stat calls per tick) and doing a full walk of every
project dir every 2 seconds, regardless of whether anything changed.

- Decorate-sort-undecorate: each file's mtime is now read exactly once via
  URLResourceValues (pre-fetched by contentsOfDirectory).
- Skip project dirs whose own mtime is older than 30 minutes.

On a machine with 66 project dirs and 4204 JSONL files, per-tick syscalls
drop from ~50k to ~200. CPU goes from 120% steady-state to negligible.

Closes #129

Co-authored-by: jescoti <5825573+jescoti@users.noreply.github.com>
EOF
)"
```

---

## PR 3: Rebase and merge external PR #126 (per-bucket pacing)

**Branch:** `humboldt94-feature/per-bucket-pacing-and-session-reset` (or similar - checked out from fork)
**Priority:** medium (feature, external contribution)
**Size:** large (+387/-77 but all authored by Humboldt94; our work is review + rebase + validation)

### Context

Humboldt94 opened PR #126 adding per-bucket pacing (session/weekly/sonnet all get pacing, previously only weekly), a pinnable Session pacing metric, and an optional reset countdown next to the 5h percentage in the menu bar. 10 new tests (229 total passing per PR body).

We need to rebase this PR on the latest main (which will have the security + perf fixes from PR 1 and PR 2), do a thorough review against CLAUDE.md SwiftUI rules, build Release with Xcode 16.4, and merge.

### Tasks

- [ ] **3.1 Checkout the PR branch locally**

```bash
gh pr checkout 126
```

This creates a local branch tracking Humboldt94's fork.

- [ ] **3.2 Rebase on main**

```bash
git fetch origin main
git rebase origin/main
# Resolve conflicts if any - most likely around SettingsStore, MenuBarRenderer, UsageStore
```

- [ ] **3.3 Review against CLAUDE.md SwiftUI rules**

Checklist for each modified Swift file:
- [ ] No `@Observable` anywhere (grep `@Observable`, expect zero matches)
- [ ] No `@Bindable`, no `@Environment(...:Store.self)` (grep)
- [ ] No `Binding(get:set:)` closures in bindings
- [ ] No `$store.computedProp` patterns - use local `@State` + `.onChange`
- [ ] Stores remain `ObservableObject` with `@Published` properties
- [ ] Views use `@EnvironmentObject` or `@ObservedObject`
- [ ] New timer in `StatusBarController` (for reset countdown) is cancelled when `showSessionReset` becomes false

Specific files to audit:
- `Shared/Stores/UsageStore.swift` - new properties `fiveHourPacing`, `sonnetPacing`, `applyPacing()`, `refreshResetCountdown()`
- `Shared/Stores/SettingsStore.swift` - new `showSessionReset` toggle + `showSessionPacing` computed
- `TokenEaterApp/StatusBarController.swift` - new 60s timer + RenderData fields
- `TokenEaterApp/MenuBarView.swift` - new pacing sections
- `TokenEaterApp/DashboardView.swift` - 3 pacing cards
- `TokenEaterApp/DisplaySectionView.swift` - new toggles

- [ ] **3.4 Run full test suite**

```bash
xcodegen generate
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests \
  -configuration Debug -derivedDataPath build \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  test
```

Expect 229 tests passing (per PR body).

- [ ] **3.5 Build Release with Xcode 16.4**

```bash
export DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer
# Then run the Build + Nuke + Install one-liner from CLAUDE.md
```

Critical: this surfaces any Swift 6.1.x + @Observable regression that wouldn't show in Debug. If app freezes at 100% CPU on launch, revert and investigate.

- [ ] **3.6 Mac checkpoint 3**

Manual validation:
- [ ] Per-bucket pacing displays in dashboard (3 cards: session, weekly, sonnet)
- [ ] Session pacing pins correctly in menu bar
- [ ] Reset countdown shows `1h 39min` next to `5h XX%` when toggle ON
- [ ] Reset countdown hides and timer stops when toggle OFF
- [ ] Pin "Session pacing" with no active session → no empty gap
- [ ] Change pacing display mode (dot/dotDelta/delta) → both session and weekly respect it

- [ ] **3.7 Merge PR 126**

If all checks pass, merge via GitHub UI (squash or rebase, user's choice). Humboldt94 is credited as the primary author by default.

If changes are needed, comment on the PR asking for them (polite, with specifics), or commit fixes on the rebased branch and mention in the merge commit:

```
Co-authored-by: Humboldt94 <128601667+Humboldt94@users.noreply.github.com>
```

---

## PR 4: Keychain helper LaunchAgent (#128)

**Branch:** `fix/keychain-helper-launchagent`
**Priority:** high (app is broken for Claude Code CLI-only users without Claude Desktop)
**Size:** large (~700 lines, new build target, install/uninstall flow)

### Context

Claude Code v2.1.x+ stores OAuth credentials exclusively in the macOS Keychain under service `"Claude Code-credentials"`. The Keychain item's ACL whitelists only `/usr/bin/security`, so `SecItemCopyMatching` from any sandboxed ad-hoc-signed process (i.e. TokenEater today) is rejected.

TokenEater's existing token path (in order: file → config.json → Keychain) works for:
- Users with Claude Desktop installed (config.json + ElectronDecryptionService)
- Users on older Claude Code versions that still wrote `.credentials.json`

Fails for: users running current Claude Code CLI-only. UI misleadingly shows "Rate limited" instead of "no token".

**Post-Apple Developer Program (next month):** this helper can be deprecated in favor of desandboxing the main app. See `docs/APPLE_DEV_MIGRATION.md`. For now, we ship the helper as a temporary bridge.

### Architecture

New target: `TokenEaterHelper`, a non-sandboxed command-line tool embedded in `TokenEater.app/Contents/Library/LoginItems/TokenEaterHelper`.

At runtime:
1. Helper is loaded as a LaunchAgent via `~/Library/LaunchAgents/com.tokeneater.helper.plist`
2. Helper shells out to `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w` every N seconds (configurable via plist)
3. Helper writes the token to `~/Library/Application Support/com.tokeneater.shared/keychain-token.json` with mode 0600 + complete file protection
4. TokenEater reads that file as a 4th token source (after cachedToken, file, config.json, Keychain direct)

### Files

**Modify:**
- `project.yml` - add `TokenEaterHelper` target
- `Shared/Services/TokenProvider.swift:44-68` - add 4th source `keychainHelperReader.readToken()`
- `Shared/Services/Protocols/` - add `KeychainHelperReaderProtocol`
- `Shared/Stores/SettingsStore.swift` - add helper-related state (helperStatus, helperSyncInterval)
- `Shared/Stores/UsageStore.swift:136-180` - fix error mapping so "no token" doesn't surface as "Rate limited"
- `TokenEaterApp/SettingsSectionView.swift` or new tab - add Credentials section
- `TokenEaterApp/Resources/` - add the LaunchAgent `.plist` template
- `TokenEaterApp/TokenEaterApp.entitlements` - add read access to the new shared file (already covered by existing temp-exception)
- `.github/workflows/release.yml` - build + copy helper into bundle
- `Shared/en.lproj/Localizable.strings` + `Shared/fr.lproj/Localizable.strings` - new strings

**Create:**
- `TokenEaterHelper/main.swift` - helper entrypoint
- `TokenEaterHelper/TokenSync.swift` - main sync loop logic
- `TokenEaterHelper/Info.plist` - bundle metadata
- `Shared/Services/KeychainHelperReader.swift` - reads the JSON file the helper writes
- `Shared/Services/HelperManagerService.swift` - install/uninstall/status management from the main app
- `Shared/Services/Protocols/HelperManagerProtocol.swift`
- `TokenEaterApp/Resources/com.tokeneater.helper.plist.template` - LaunchAgent .plist template with `{{BINARY_PATH}}` placeholder
- `TokenEaterApp/CredentialsSectionView.swift` - Settings UI for helper management
- `TokenEaterApp/HelperInstallBanner.swift` - first-run banner shown in popover when no token source
- `TokenEaterTests/HelperManagerServiceTests.swift`
- `TokenEaterTests/KeychainHelperReaderTests.swift`
- `TokenEaterTests/Mocks/MockHelperManager.swift`

### Tasks

- [ ] **4.1 Add helper target in `project.yml`**

After the `TokenEaterWidgetExtension` target block, add:

```yaml
  TokenEaterHelper:
    type: tool
    platform: macOS
    sources:
      - path: TokenEaterHelper
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.tokeneater.helper
        PRODUCT_NAME: TokenEaterHelper
        # No entitlements: the helper is NOT sandboxed - that's the whole point
        SKIP_INSTALL: YES
```

Then add helper as an embedded dependency of `TokenEaterApp`:

```yaml
  TokenEaterApp:
    ...
    dependencies:
      - target: TokenEaterWidgetExtension
        embed: true
      - target: TokenEaterHelper
        embed: true
        copy:
          destination: plugins  # or resources - check Xcode copy phases
```

Note: `copy.destination: plugins` copies to `Contents/PlugIns/`. For a helper tool, `Contents/Library/LoginItems/` is more idiomatic but XcodeGen may not support it directly - may need a Run Script Phase to copy manually.

Fallback: use a postBuildScript in the main target:
```yaml
    postBuildScripts:
      - script: |
          mkdir -p "$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/Library/LoginItems"
          cp "$BUILT_PRODUCTS_DIR/TokenEaterHelper" \
            "$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/Library/LoginItems/TokenEaterHelper"
        name: Embed helper binary
```

- [ ] **4.2 Implement the helper binary**

`TokenEaterHelper/main.swift`:

```swift
import Foundation

let interval: TimeInterval = {
    if let val = ProcessInfo.processInfo.environment["SYNC_INTERVAL"].flatMap(TimeInterval.init),
       val >= 30 {
        return val
    }
    return 300  // default 5 min
}()

let sync = TokenSync(interval: interval)
sync.runForever()
```

`TokenEaterHelper/TokenSync.swift`:

```swift
import Foundation

final class TokenSync {
    private let interval: TimeInterval
    private let outputURL: URL

    init(interval: TimeInterval) {
        self.interval = interval
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        self.outputURL = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/com.tokeneater.shared/keychain-token.json")
    }

    func runForever() -> Never {
        while true {
            performSync()
            Thread.sleep(forTimeInterval: interval)
        }
    }

    private func performSync() {
        guard let token = readKeychain() else {
            writeStatus(status: "no-token", token: nil, error: "security command returned no password")
            return
        }
        writeStatus(status: "ok", token: token, error: nil)
    }

    private func readKeychain() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()  // suppress stderr

        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        // Claude Code stores the whole JSON blob in the keychain value; extract accessToken
        guard let jsonData = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }

        return token
    }

    private func writeStatus(status: String, token: String?, error: String?) {
        let payload: [String: Any] = [
            "status": status,
            "token": token ?? NSNull(),
            "lastSyncAt": ISO8601DateFormatter().string(from: Date()),
            "error": error ?? NSNull(),
            "helperVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else { return }

        // Ensure parent dir exists with correct perms
        let parent = outputURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        // Atomic write with 0600 perms
        let tmpURL = parent.appendingPathComponent(".keychain-token.json.tmp")
        try? data.write(to: tmpURL, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmpURL.path)
        _ = try? FileManager.default.replaceItemAt(outputURL, withItemAt: tmpURL)
    }
}
```

- [ ] **4.3 Create LaunchAgent plist template**

`TokenEaterApp/Resources/com.tokeneater.helper.plist.template`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.tokeneater.helper</string>
    <key>ProgramArguments</key>
    <array>
        <string>{{BINARY_PATH}}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>SYNC_INTERVAL</key>
        <string>{{SYNC_INTERVAL}}</string>
    </dict>
    <key>StandardOutPath</key>
    <string>{{HOME}}/Library/Logs/TokenEater/helper.log</string>
    <key>StandardErrorPath</key>
    <string>{{HOME}}/Library/Logs/TokenEater/helper.err</string>
</dict>
</plist>
```

- [ ] **4.4 Implement `HelperManagerService`**

`Shared/Services/HelperManagerService.swift`:

```swift
import Foundation

enum HelperStatus {
    case notInstalled
    case installed(lastSyncAt: Date?, lastError: String?)
    case error(String)
}

protocol HelperManagerProtocol {
    func currentStatus() -> HelperStatus
    func install(syncInterval: TimeInterval) throws
    func uninstall() throws
    func forceSync() throws
}

final class HelperManagerService: HelperManagerProtocol {
    private let plistPath: String
    private let binaryPath: String  // path to the embedded helper inside the .app bundle

    init() {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        self.plistPath = "\(home)/Library/LaunchAgents/com.tokeneater.helper.plist"
        self.binaryPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/TokenEaterHelper")
            .path
    }

    func currentStatus() -> HelperStatus {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            return .notInstalled
        }
        // Read helper's status file
        let statusFile = "\(ProcessInfo.processInfo.environment["HOME"] ?? "")/Library/Application Support/com.tokeneater.shared/keychain-token.json"
        guard let data = FileManager.default.contents(atPath: statusFile),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .installed(lastSyncAt: nil, lastError: nil) }

        let isoFormatter = ISO8601DateFormatter()
        let lastSync = (obj["lastSyncAt"] as? String).flatMap(isoFormatter.date)
        let error = obj["error"] as? String
        return .installed(lastSyncAt: lastSync, lastError: error)
    }

    func install(syncInterval: TimeInterval) throws {
        // 1. Read template
        guard let templateURL = Bundle.main.url(forResource: "com.tokeneater.helper.plist", withExtension: "template"),
              let template = try? String(contentsOf: templateURL, encoding: .utf8)
        else { throw HelperError.templateMissing }

        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()

        // 2. Substitute placeholders
        let plist = template
            .replacingOccurrences(of: "{{BINARY_PATH}}", with: binaryPath)
            .replacingOccurrences(of: "{{SYNC_INTERVAL}}", with: "\(Int(syncInterval))")
            .replacingOccurrences(of: "{{HOME}}", with: home)

        // 3. Ensure LaunchAgents dir + Logs dir exist
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: "\(home)/Library/LaunchAgents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: "\(home)/Library/Logs/TokenEater"), withIntermediateDirectories: true)

        // 4. Write plist
        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)

        // 5. launchctl load
        let load = Process()
        load.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        load.arguments = ["load", "-w", plistPath]
        try load.run()
        load.waitUntilExit()

        if load.terminationStatus != 0 {
            throw HelperError.launchctlLoadFailed(exitCode: load.terminationStatus)
        }
    }

    func uninstall() throws {
        // 1. launchctl unload
        if FileManager.default.fileExists(atPath: plistPath) {
            let unload = Process()
            unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            unload.arguments = ["unload", "-w", plistPath]
            try? unload.run()
            unload.waitUntilExit()
        }

        // 2. Delete plist
        try? FileManager.default.removeItem(atPath: plistPath)

        // 3. Delete status file
        let statusFile = "\(ProcessInfo.processInfo.environment["HOME"] ?? "")/Library/Application Support/com.tokeneater.shared/keychain-token.json"
        try? FileManager.default.removeItem(atPath: statusFile)
    }

    func forceSync() throws {
        // Send SIGUSR1 to the helper, which could interrupt the sleep in runForever
        // Simpler: kickstart the service
        let kickstart = Process()
        kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        kickstart.arguments = ["kickstart", "-k", "gui/\(getuid())/com.tokeneater.helper"]
        try kickstart.run()
        kickstart.waitUntilExit()
    }
}

enum HelperError: Error {
    case templateMissing
    case launchctlLoadFailed(exitCode: Int32)
}
```

Note: sandbox restricts `Process()` execution. The main app entitlements need `com.apple.security.temporary-exception.files.absolute-path.read-write` for `/bin/launchctl` and `/usr/bin/security`, OR use `SMJobBless` / `SMAppService` (more complex, requires signed helper with matching bundle ID).

For v5.0.0 on an ad-hoc signed app, `launchctl` via `Process` should work because Processes with `executableURL` outside the sandbox ARE typically blocked - this is a known limitation. **Workaround:** use `NSWorkspace.shared.openApplication()` with a helper `.command` script, or use the existing `TokenEaterInstaller.app` AppleScript pattern (which already runs `admin` shell scripts).

**Decision point:** if `launchctl` from sandbox doesn't work, reuse the existing AppleScript installer pattern: have `TokenEaterInstaller.app` run the install commands (load plist, copy binary to user dir if needed). User gets the admin prompt once, then the helper runs thereafter.

- [ ] **4.5 Implement `KeychainHelperReader`**

`Shared/Services/KeychainHelperReader.swift`:

```swift
import Foundation

protocol KeychainHelperReaderProtocol {
    func readToken() -> String?
}

final class KeychainHelperReader: KeychainHelperReaderProtocol, @unchecked Sendable {
    private let filePath: String

    init() {
        let home: String
        if let pw = getpwuid(getuid()) {
            home = String(cString: pw.pointee.pw_dir)
        } else {
            home = NSHomeDirectory()
        }
        filePath = "\(home)/Library/Application Support/com.tokeneater.shared/keychain-token.json"
    }

    init(filePath: String) {
        self.filePath = filePath
    }

    func readToken() -> String? {
        guard let data = FileManager.default.contents(atPath: filePath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = obj["status"] as? String,
              status == "ok",
              let token = obj["token"] as? String,
              !token.isEmpty
        else { return nil }
        return token
    }
}
```

- [ ] **4.6 Wire `KeychainHelperReader` into `TokenProvider`**

In `Shared/Services/TokenProvider.swift`, add the helper reader as a new dependency. Updated `currentToken()`:

```swift
func currentToken() -> String? {
    if let token = cachedToken { return token }

    // Source 1: credentials file (legacy Claude Code)
    if let token = credentialsFileReader.readToken() {
        cachedToken = token
        return token
    }

    // Source 2: helper-synced Keychain token (new Claude Code)
    if let token = keychainHelperReader.readToken() {
        cachedToken = token
        logger.info("Token read from Keychain helper file")
        return token
    }

    // Source 3: decrypt config.json (Claude Desktop)
    if let token = tokenFromConfigJSON() {
        cachedToken = token
        return token
    }

    // Source 4: direct Keychain silent read (often fails on sandboxed ad-hoc, but try anyway)
    if let token = keychainReader(true) {
        cachedToken = token
        logger.info("Token read from Keychain (silent) and cached in memory")
        return token
    }

    return nil
}
```

Update `hasTokenSource()` similarly.

- [ ] **4.7 Fix error-state mapping (shuhulx's suggestion #1)**

In `Shared/Stores/UsageStore.swift`, there are 3 error states: `.none`, `.tokenUnavailable`, `.rateLimited`, `.networkError`. Verify that when `currentToken()` returns nil (no source works), the UI displays `.tokenUnavailable` (maps to `error.notoken` string), NOT `.rateLimited`.

Grep for "Rate limited" appearing when no token is available. The bug reported by shuhulx is that the UI shows "Rate limited" when the actual problem is no token. Fix: ensure `rateLimited` is only set inside the `.rateLimited(let retryAfter)` catch branch, never as a default for other failures.

Also surface a clearer message when no token source works AND no helper is installed:

Add new error state `.noTokenHelperNotInstalled` mapped to a new string `error.notoken.helper` = "Claude Code credentials are now stored only in the Keychain. Install the TokenEater helper from Settings → Credentials to access them."

- [ ] **4.8 Create `CredentialsSectionView`**

New file `TokenEaterApp/CredentialsSectionView.swift`:

```swift
import SwiftUI

struct CredentialsSectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var helperStatus: HelperStatus = .notInstalled
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(String(localized: "sidebar.credentials"))

            glassCard {
                VStack(alignment: .leading, spacing: 12) {
                    cardLabel(String(localized: "credentials.helper.title"))
                    statusRow
                    Divider().opacity(0.2)
                    actionButtons
                    if case .installed = helperStatus {
                        syncIntervalPicker
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .onAppear { refreshStatus() }
    }

    // ... status display, buttons, etc.
}
```

Contains:
- Live status badge ("✓ Active - last sync 2 min ago" / "⚠ Not installed" / "✗ Error: ...")
- Install / Uninstall button (toggle based on state)
- "Force sync now" button (when installed)
- Sync interval picker: 30s / 1 min / 5 min / 15 min (when installed)
- "View helper logs" button (opens Console.app)

- [ ] **4.9 Create `HelperInstallBanner`**

In the menu bar popover, when `hasTokenSource() == false` AND helper not installed, show a banner:

```swift
struct HelperInstallBanner: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "helper.banner.title"))
                .font(.headline)
            Text(String(localized: "helper.banner.description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button(String(localized: "helper.banner.install")) {
                    // trigger install flow
                }
                .buttonStyle(.borderedProminent)
                Button(String(localized: "helper.banner.learnmore")) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/AThevon/TokenEater/issues/128")!)
                }
            }
        }
        .padding()
        .background(.yellow.opacity(0.1))
        .cornerRadius(10)
    }
}
```

Add strings to `Localizable.strings` both `en.lproj` and `fr.lproj`.

- [ ] **4.10 Add sidebar entry + localization**

In `TokenEaterApp/AppSidebar.swift`, add a new `credentials` case. Update `MainAppView.swift` to include the new view.

New strings:
```
"sidebar.credentials" = "Credentials";
"credentials.helper.title" = "Keychain Helper";
"credentials.helper.description" = "A small background service that reads Claude Code credentials from your macOS Keychain and makes them available to TokenEater.";
"credentials.helper.status.notinstalled" = "Not installed";
"credentials.helper.status.active" = "✓ Active - last sync %@";
"credentials.helper.status.error" = "✗ Error: %@";
"credentials.helper.install" = "Install helper";
"credentials.helper.uninstall" = "Remove helper";
"credentials.helper.forcesync" = "Force sync now";
"credentials.helper.interval" = "Sync frequency";
"credentials.helper.interval.30s" = "30 seconds";
"credentials.helper.interval.1m" = "1 minute";
"credentials.helper.interval.5m" = "5 minutes";
"credentials.helper.interval.15m" = "15 minutes";
"credentials.helper.logs" = "View logs";
"helper.banner.title" = "Claude Code credentials not accessible";
"helper.banner.description" = "Claude Code now stores its credentials only in the Keychain. Install the TokenEater helper to make them available.";
"helper.banner.install" = "Install helper";
"helper.banner.learnmore" = "Learn more";
"error.notoken.helper" = "Credentials not found - install the TokenEater helper from Settings.";
```

And French equivalents.

- [ ] **4.11 Update release.yml to build + sign helper**

After the xcodebuild step, verify that the helper binary ended up in the `.app/Contents/Library/LoginItems/`. No extra signing required since the whole app is ad-hoc signed at build time (helper inherits).

If the embed copy phase didn't make it into the Xcodegen output, add a manual `cp` step in the workflow.

- [ ] **4.12 Write tests**

`TokenEaterTests/HelperManagerServiceTests.swift`:
- `installCreatesPlistAndLoadsIt()` - mock FileManager and Process
- `uninstallRemovesPlistAndStatusFile()`
- `currentStatusReturnsNotInstalledWhenPlistMissing()`
- `currentStatusParsesStatusFile()`

`TokenEaterTests/KeychainHelperReaderTests.swift`:
- `readTokenReturnsNilWhenFileMissing()`
- `readTokenReturnsNilWhenStatusNotOK()`
- `readTokenReturnsTokenWhenStatusOK()`
- `readTokenRejectsEmptyToken()`

`TokenEaterTests/TokenProviderTests.swift` - extend with:
- `currentTokenReadsHelperBeforeConfigJSON()`
- `currentTokenCachesHelperToken()`

- [ ] **4.13 Mac checkpoint 4**

On a test machine:
1. Delete `~/.claude/.credentials.json` if present
2. Confirm only Keychain has the credentials (via `security find-generic-password -s "Claude Code-credentials" -w`)
3. Install TokenEater v5.0.0 build
4. Observe banner: "Claude Code credentials not accessible - Install helper"
5. Click Install → grant admin prompt if needed
6. Within 30-60s, usage data should appear
7. Check `~/Library/Logs/TokenEater/helper.log` and helper.err
8. Open Settings → Credentials → verify "Active - last sync X ago"
9. Click "Force sync now" → verify logs
10. Click "Remove helper" → verify plist removed and launchctl unloaded

- [ ] **4.14 Commit + PR**

Commit message:
```
fix: add Keychain helper for Claude Code's keychain-only storage

Claude Code v2.1.x+ stores OAuth credentials exclusively in the macOS
Keychain under service "Claude Code-credentials", with an ACL that
whitelists only /usr/bin/security. A sandboxed ad-hoc-signed app like
TokenEater cannot read it directly.

This PR adds a non-sandboxed helper binary embedded in the app bundle.
When users install the helper (opt-in via a banner in the popover or
from Settings → Credentials), it runs as a LaunchAgent, shells out to
/usr/bin/security on a configurable interval, and writes the token to
a shared file that TokenEater reads as a fourth token source.

Also fixes the misleading "Rate limited" error message that was being
surfaced when the real problem was no token being available at all
(reported by shuhulx).

This is a transitional solution. Once the project moves to an Apple
Developer Program signing identity, the main app can be desandboxed
and the helper becomes unnecessary. See docs/APPLE_DEV_MIGRATION.md.

Closes #128

Co-authored-by: shuhulx <106345809+shuhulx@users.noreply.github.com>
Co-authored-by: conchoecia <darrints@stanford.edu>
```

PR body should walk through: (1) the root cause diagnosis credited to shuhulx, (2) the Claude Desktop context credited to conchoecia, (3) why we chose a LaunchAgent helper over other options, (4) a clear statement that this is transitional until Apple Dev Program.

---

## PR 5: Reset time display format + color customization (#130)

**Branch:** `feat/reset-time-display-ux`
**Priority:** low (feature enhancement)
**Size:** medium (~300 lines + tests)

### Context

jeromeajot requested (a) customizable color for the reset text because current default is hard to read on some systems, and (b) showing the absolute reset time (e.g. `20:30` or `Fri 08:00`) instead of the session duration label (`5h` / `7d`).

PR 126 (now merged) adds a relative reset countdown (`1h 39min`). This PR builds on that by offering three display modes and color customization for the reset text AND the session period label.

### Files

**Modify:**
- `Shared/Stores/SettingsStore.swift` - add `resetDisplayFormat`, `resetTextColor`, `sessionPeriodColor`
- `Shared/Stores/UsageStore.swift:292-321` - compute absolute reset time alongside relative
- `Shared/Helpers/MenuBarRenderer.swift` - use selected format + color
- `TokenEaterApp/DisplaySectionView.swift` - add pickers
- `Shared/Models/` - add `ResetDisplayFormat` enum
- `Shared/en.lproj/Localizable.strings` + `fr.lproj/Localizable.strings`

**Create:**
- `Shared/Models/ResetDisplayFormat.swift`
- `TokenEaterApp/Components/ResetFormatPicker.swift`
- `TokenEaterApp/Components/ColorTokenPicker.swift` (reusable color picker with presets)

### Tasks

- [ ] **5.1 Define `ResetDisplayFormat` enum**

`Shared/Models/ResetDisplayFormat.swift`:

```swift
import Foundation

enum ResetDisplayFormat: String, CaseIterable, Identifiable {
    case relative     // "1h 39min"
    case absolute     // "20:30" today, "Fri 08:00" other days
    case both         // "1h 39min - 20:30"

    var id: String { rawValue }

    var localizedLabel: String {
        switch self {
        case .relative: return String(localized: "settings.reset.format.relative")
        case .absolute: return String(localized: "settings.reset.format.absolute")
        case .both: return String(localized: "settings.reset.format.both")
        }
    }
}
```

- [ ] **5.2 Add `ResetTextColor` + `SessionPeriodColor` presets**

Reuse an existing color palette pattern if the project has one, else create a minimal `MenuBarTextColor` enum:

```swift
enum MenuBarTextColor: String, CaseIterable {
    case system  // NSColor.labelColor - adapts dark/light
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case custom  // uses a hex string stored separately

    func nsColor(customHex: String?) -> NSColor {
        switch self {
        case .system: return .labelColor
        case .red: return .systemRed
        // ...
        case .custom:
            if let hex = customHex, let color = NSColor(hex: hex) { return color }
            return .labelColor
        }
    }
}
```

Add to `SettingsStore`:

```swift
@Published var resetDisplayFormat: ResetDisplayFormat { didSet { UserDefaults.standard.set(resetDisplayFormat.rawValue, forKey: "resetDisplayFormat") } }
@Published var resetTextColor: MenuBarTextColor { didSet { UserDefaults.standard.set(resetTextColor.rawValue, forKey: "resetTextColor") } }
@Published var resetTextCustomHex: String { didSet { UserDefaults.standard.set(resetTextCustomHex, forKey: "resetTextCustomHex") } }
@Published var sessionPeriodColor: MenuBarTextColor { didSet { UserDefaults.standard.set(sessionPeriodColor.rawValue, forKey: "sessionPeriodColor") } }
@Published var sessionPeriodCustomHex: String { didSet { UserDefaults.standard.set(sessionPeriodCustomHex, forKey: "sessionPeriodCustomHex") } }
```

With defaults in init: `.both`, `.system`, `""`, `.system`, `""`.

- [ ] **5.3 Compute absolute reset time in `UsageStore`**

Extend `updateUI(from:)` around lines 303-314:

```swift
if let reset = usage.fiveHour?.resetsAtDate {
    let diff = reset.timeIntervalSinceNow
    if diff > 0 {
        let h = Int(diff) / 3600
        let m = (Int(diff) % 3600) / 60
        fiveHourResetRelative = h > 0 ? "\(h)h \(m)min" : "\(m)min"
        fiveHourResetAbsolute = formatAbsoluteReset(reset)
    } else {
        fiveHourResetRelative = String(localized: "relative.now")
        fiveHourResetAbsolute = ""
    }
} else {
    fiveHourResetRelative = ""
    fiveHourResetAbsolute = ""
}
```

Where `formatAbsoluteReset`:

```swift
private func formatAbsoluteReset(_ date: Date) -> String {
    let calendar = Calendar.current
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    if calendar.isDateInToday(date) {
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    } else {
        formatter.dateFormat = "EEE HH:mm"  // "Fri 08:00"
        return formatter.string(from: date)
    }
}
```

Rename `fiveHourReset` → `fiveHourResetRelative`, add `fiveHourResetAbsolute` as a new `@Published` var.

- [ ] **5.4 Update `MenuBarRenderer`**

Add new fields to `RenderData`:
```swift
let resetDisplayFormat: ResetDisplayFormat
let resetTextColor: NSColor
let sessionPeriodColor: NSColor
let resetCountdown: String         // existing from PR 126
let resetCountdownAbsolute: String // NEW
let showSessionReset: Bool
```

In `renderPinnedMetrics`, when rendering the `.fiveHour` metric + `showSessionReset`, replace the single countdown string with the formatted one based on `resetDisplayFormat`:

```swift
if data.showSessionReset {
    let text: String
    switch data.resetDisplayFormat {
    case .relative: text = data.resetCountdown
    case .absolute: text = data.resetCountdownAbsolute
    case .both: text = "\(data.resetCountdown) - \(data.resetCountdownAbsolute)"
    }
    let resetAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
        .foregroundColor: data.resetTextColor,
    ]
    str.append(NSAttributedString(string: text + " ", attributes: resetAttrs))
}
```

Also apply `data.sessionPeriodColor` to the `"5h "` / `"7d "` label rendering (currently uses `NSColor.tertiaryLabelColor`).

- [ ] **5.5 Create UI pickers**

`TokenEaterApp/Components/ResetFormatPicker.swift`:

```swift
import SwiftUI

struct ResetFormatPicker: View {
    @Binding var selection: ResetDisplayFormat

    var body: some View {
        Picker(String(localized: "settings.reset.format"), selection: $selection) {
            ForEach(ResetDisplayFormat.allCases) { format in
                Text(format.localizedLabel).tag(format)
            }
        }
        .pickerStyle(.menu)
    }
}
```

`TokenEaterApp/Components/ColorTokenPicker.swift`:

```swift
import SwiftUI

struct ColorTokenPicker: View {
    let label: String
    @Binding var selection: MenuBarTextColor
    @Binding var customHex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(label, selection: $selection) {
                ForEach(MenuBarTextColor.allCases, id: \.self) { color in
                    HStack {
                        Circle().fill(Color(color.nsColor(customHex: customHex))).frame(width: 12, height: 12)
                        Text(color.localizedLabel)
                    }
                    .tag(color)
                }
            }
            .pickerStyle(.menu)

            if selection == .custom {
                HStack {
                    Text("#")
                    TextField("RRGGBB", text: $customHex)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }
        }
    }
}
```

- [ ] **5.6 Add pickers to `DisplaySectionView`**

Inside the existing `glassCard` for "Pinned metrics", right after the existing `PacingDisplayPicker` conditional:

```swift
if showFiveHour || showSevenDay {
    Divider().opacity(0.2)
    ResetFormatPicker(selection: $settingsStore.resetDisplayFormat)
    ColorTokenPicker(
        label: String(localized: "settings.reset.color"),
        selection: $settingsStore.resetTextColor,
        customHex: $settingsStore.resetTextCustomHex
    )
    ColorTokenPicker(
        label: String(localized: "settings.session.periodcolor"),
        selection: $settingsStore.sessionPeriodColor,
        customHex: $settingsStore.sessionPeriodCustomHex
    )
}
```

- [ ] **5.7 Add localized strings**

```
"settings.reset.format" = "Reset display";
"settings.reset.format.relative" = "Relative (1h 39min)";
"settings.reset.format.absolute" = "Absolute (20:30)";
"settings.reset.format.both" = "Both";
"settings.reset.color" = "Reset text color";
"settings.session.periodcolor" = "Session label color";
"color.system" = "System";
"color.red" = "Red";
"color.orange" = "Orange";
"color.yellow" = "Yellow";
"color.green" = "Green";
"color.blue" = "Blue";
"color.purple" = "Purple";
"color.custom" = "Custom…";
```

And French equivalents.

- [ ] **5.8 Write tests**

`TokenEaterTests/MenuBarRendererTests.swift` (new or extend):
- `rendersRelativeFormatOnly()`
- `rendersAbsoluteFormatOnly()`
- `rendersBothFormatsWithSeparator()`
- `appliesCustomResetTextColor()`
- `appliesSessionPeriodColor()`

`TokenEaterTests/SettingsStoreTests.swift`:
- `resetDisplayFormatPersists()`
- `customHexPersistsAndReloads()`

- [ ] **5.9 Mac checkpoint 5**

- [ ] Cycle through format options, verify menu bar updates immediately
- [ ] Set custom hex color, verify rendering
- [ ] Verify session label color changes `5h` and `7d` colors
- [ ] Verify color adapts correctly between light and dark menu bar modes (esp. `.system`)

- [ ] **5.10 Commit + PR**

```
feat: customizable reset time format and color for menu bar

Adds three user-selectable formats for the 5-hour session reset display:
relative ("1h 39min"), absolute ("20:30" today or "Fri 08:00" other days),
or both separated by a dash. Adds color pickers for the reset text and
for the session period label (5h / 7d), with system-adaptive, preset,
and custom-hex options.

Closes #130

Co-authored-by: jeromeajot <351091+jeromeajot@users.noreply.github.com>
```

---

## Final release process (post all 5 PRs merged)

- [ ] **F.1 Bump version**

Edit `project.yml` line 15: `MARKETING_VERSION: "5.0.0"`.

Regenerate: `xcodegen generate`.

- [ ] **F.2 Write release notes**

Edit the upcoming GitHub release body (or CHANGELOG.md if the project has one - check):

```markdown
# TokenEater v5.0.0

This is a major release bundling a critical security fix, a token-retrieval fix for users on current Claude Code, a significant performance optimization, and several UX improvements.

## 🔒 Security

- Auto-updater now verifies the EdDSA signature of the downloaded DMG before installing (#127). Thanks @jescoti for the report.

## ⚡ Performance

- Session Monitor scan is now ~50x cheaper on machines with many Claude projects; CPU usage drops from 100%+ to negligible for heavy users (#129). Thanks @jescoti.

## 🔑 Compatibility

- Adds an opt-in background helper that reads credentials from the macOS Keychain for users on current Claude Code (v2.1.x+) where the CLI no longer writes ~/.claude/.credentials.json (#128). Thanks @shuhulx and @conchoecia for the detailed root-cause analysis.
- Clearer error messages when credentials are missing (previously shown as "Rate limited").

## ✨ Features

- Per-bucket pacing: session (5h), weekly (7d) and sonnet buckets now each have their own pacing calculation, plus a new pinnable Session pacing metric (#126 by @Humboldt94).
- Optional countdown next to the 5h session percentage.
- New customizable reset display format: relative, absolute, or both (#130 by @jeromeajot).
- Color picker for the reset text and session period label.

## Install

As always via Homebrew cask:

    brew upgrade --cask tokeneater

Or download the DMG from this release.
```

- [ ] **F.3 Tag and release**

```bash
git tag v5.0.0
git push origin v5.0.0
```

CI workflow `release.yml` takes over: builds, DMG, EdDSA signature, appcast update, Homebrew cask bump.

- [ ] **F.4 Mac checkpoint 6 (final validation)**

Run `test-build.yml` workflow first to get an iso-prod DMG, OR wait for the tag to trigger `release.yml`. Either way, do a full mega-nuke cycle:

```bash
# Full mega-nuke from CLAUDE.md
killall TokenEater NotificationCenter chronod cfprefsd 2>/dev/null; sleep 1
defaults delete com.tokeneater.app 2>/dev/null
defaults delete com.claudeusagewidget.app 2>/dev/null
rm -f ~/Library/Preferences/com.tokeneater.app.plist ~/Library/Preferences/com.claudeusagewidget.app.plist
# ... full mega nuke from CLAUDE.md ...

# Also clean up the helper if it was installed during dev
launchctl unload ~/Library/LaunchAgents/com.tokeneater.helper.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.tokeneater.helper.plist
rm -rf ~/Library/Logs/TokenEater

# Install fresh from the DMG
# ...
```

Validate end-to-end on a cold user state.

- [ ] **F.5 Announce**

If applicable: post release announcement (Twitter / X, GitHub Discussions, etc.). Give prominent credit to contributors.

---

## Self-review checklist

- [x] Each PR has clear scope and closes exactly one issue
- [x] Co-author attribution documented for each PR
- [x] CLAUDE.md SwiftUI rules are explicitly checked in PR 3 (external PR review)
- [x] All code paths ship with tests
- [x] Mac validation steps are explicit per-PR
- [x] Apple Dev Program migration documented separately (see `docs/APPLE_DEV_MIGRATION.md`)
- [x] Release process documented end-to-end
- [x] French localization covered for all new strings

## Open questions / decisions needed from user

1. **Apple EdDSA public key retrieval**: the public key derivation from `SPARKLE_PRIVATE_KEY` must happen locally on the Mac. Plan Task 1.1 describes both paths (derive from private key, or regenerate a fresh keypair).
2. **Helper installation UX**: if `Process()` cannot launch `launchctl` from the sandboxed main app, fallback is to reuse the existing `TokenEaterInstaller.app` AppleScript pattern. Confirm this is acceptable (means user sees an admin prompt on first install).
3. **Version bump**: v5.0.0 is proposed based on the helper being a breaking operational change. Could also be v4.10.0 if preferred.
