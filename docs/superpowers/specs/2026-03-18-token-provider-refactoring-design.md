# TokenEater — Token Provider Refactoring & Stability Overhaul

**Date:** 2026-03-18
**Status:** Draft
**Branch:** To be created from `main`

---

## Problem Statement

TokenEater suffers from three recurring issues that have resisted multiple fix attempts:

1. **macOS Keychain modal dialogs** reappear after sleep, wake, or periodically — despite using `kSecUseAuthenticationUISkip`. Root cause: Claude Code deletes and recreates its Keychain entry `Claude Code-credentials` on every token refresh (~8h), resetting the ACL. "Always Allow" never persists.

2. **Rate limiting (429)** from Anthropic's API due to 5-minute fixed polling, compounded by burst refreshes after wake/restart.

3. **Widget staleness** — widgets don't reliably reflect current data because the refresh pipeline is complex and fragile.

Additionally, the `CredentialsFileReader` reads `~/.claude/.credentials.json` which **does not exist on macOS**. Claude Code stores credentials exclusively in the Keychain + encrypted `config.json`. Every token read falls back to the Keychain, which is the true source of the modal problem.

## Design Goals

- **Zero Keychain modals after onboarding** — one Keychain read during onboarding, cached forever
- **Reactive refresh** — FSEvents-driven instead of blind polling
- **Simpler codebase** — fewer error states, fewer recovery paths, less code
- **Reliable widgets** — widgets always reflect the latest data from the menu bar app
- **No regressions** — agent watchers, themes, settings, notifications unchanged

## Non-Goals

- Changing the widget visual design
- Implementing TokenEater's own OAuth flow (Anthropic doesn't allow third-party OAuth registration)
- Migrating to `@Observable` (still broken in Release builds with Swift 6.1.x / Xcode 16.4)
- Paying for the Apple Developer Program

---

## Architecture Overview

### Current Flow (broken)

```
Every 5 min:
  CredentialsFileReader → nil (file doesn't exist)
  → Keychain "Claude Code-credentials" → modal (ACL reset every 8h)
  → API call → shared.json → widget
```

### New Flow

```
Onboarding (once):
  Keychain "Claude Safe Storage" → derive AES key → cache locally (dk.bin)
  → never touch Keychain again

Auto-refresh (reactive):
  FSEvents on config.json → decrypt with cached key → token → API → shared.json → widget
  + 10min backup timer
  + wake handler (refresh if stale >2min)
```

---

## Section 1: Token Provider

### New Services

#### `ElectronDecryptionService`

Decrypts Electron safeStorage encrypted values from Claude Code's `config.json`.

**Encryption format** (Chromium standard, stable 10+ years):
- Base64-encoded payload
- First 3 bytes: `v10` version prefix
- Remaining bytes: AES-128-CBC ciphertext with PKCS7 padding
- Key derivation: PBKDF2-HMAC-SHA1(keychain_password, salt="saltysalt", iterations=1003, keylen=16)
- IV: 16 space characters (0x20)

**Protocol:**
```swift
protocol ElectronDecryptionServiceProtocol: Sendable {
    func decrypt(_ encryptedBase64: String) throws -> Data
    var hasEncryptionKey: Bool { get }
    func bootstrapEncryptionKey() throws
    func clearCachedKey()
}
```

**Key caching:**
- Derived AES key stored in TokenEater's **own Keychain** entry: service `TokenEater`, account `decryption-key`
- Uses `kSecUseAuthenticationUISkip` — no modal ever, since TokenEater owns this entry (ACL includes TokenEater by default)
- Prefixed with version byte `0x01` followed by 16 bytes of derived key (facilitates future format migration)
- Created during onboarding, read on every app launch
- Invalidated when decryption fails (Claude Code reinstalled → new Keychain key)
- **Not stored in `com.tokeneater.shared/`** — the widget has read access to that directory and should never access the decryption key

**Keychain read:**
- Service: `Claude Safe Storage`, Account: `Claude Key`
- Read with `kSecUseAuthenticationUI: kSecUseAuthenticationUIAllow` (interactive, onboarding only)
- This Keychain entry is created once at Claude Code installation and **never deleted/recreated** — "Always Allow" persists permanently

#### `ClaudeConfigReader`

Reads and parses Claude Code's `config.json`.

**Protocol:**
```swift
protocol ClaudeConfigReaderProtocol: Sendable {
    func readEncryptedToken() -> String?
}
```

**Implementation:**
- Path: `~/Library/Application Support/Claude/config.json`
- Resolved via `getpwuid(getuid())` (real home, not sandbox container)
- Reads JSON, extracts `oauth:tokenCache` string
- No decryption — returns the raw encrypted base64 string

#### `TokenProvider` (replaces `KeychainService` + `CredentialsFileReader`)

Single entry point for obtaining the current OAuth token.

**Protocol:**
```swift
protocol TokenProviderProtocol: Sendable {
    func currentToken() -> String?
    var isBootstrapped: Bool { get }
    func bootstrap() throws
}
```

**Token resolution order:**
1. `~/.claude/.credentials.json` — plain text file (future-proof, when Anthropic implements it on macOS per issue #22144)
2. `config.json` decryption — decrypt with cached AES key, parse JSON, extract `accessToken`
3. Keychain `Claude Code-credentials` silent read — last resort fallback

**Dependencies:** `CredentialsFileReaderProtocol`, `ClaudeConfigReaderProtocol`, `ElectronDecryptionServiceProtocol`

### Files

| Action | File | Notes |
|--------|------|-------|
| Create | `Shared/Services/ElectronDecryptionService.swift` | ~80 lines, CommonCrypto |
| Create | `Shared/Services/ClaudeConfigReader.swift` | ~40 lines |
| Create | `Shared/Services/TokenProvider.swift` | ~60 lines |
| Create | `Shared/Services/Protocols/ElectronDecryptionServiceProtocol.swift` | |
| Create | `Shared/Services/Protocols/ClaudeConfigReaderProtocol.swift` | |
| Create | `Shared/Services/Protocols/TokenProviderProtocol.swift` | |
| Delete | `Shared/Services/KeychainService.swift` | |
| Delete | `Shared/Services/CredentialsFileReader.swift` | |
| Delete | `Shared/Services/Protocols/KeychainServiceProtocol.swift` | |
| Delete | `Shared/Services/Protocols/CredentialsFileReaderProtocol.swift` | |

### Entitlements Change

Add to `TokenEaterApp.entitlements` read-only array:
```xml
<string>/Library/Application Support/Claude/</string>
```

**Sandbox verification required:** The entitlement uses `temporary-exception.files.home-relative-path.read-only`, which resolves to the real home directory (same mechanism as the existing `/.claude/` exception). Must be tested in a real sandbox build to confirm access to `~/Library/Application Support/Claude/config.json` works. The existing `CredentialsFileReader` uses the same `getpwuid(getuid())` approach successfully for `~/.claude/`, so this should work identically.

No widget entitlement change needed (widget never reads config.json).

### Thread Safety

All new services are `@unchecked Sendable` (same pattern as existing services). `TokenProvider` and `ElectronDecryptionService` are called exclusively from the main actor (UsageStore, OnboardingViewModel) so no concurrent access occurs. The Keychain operations for the cached key use TokenEater's own Keychain entry with no ACL complications.

---

## Section 2: File Monitoring (FSEvents)

### New Service: `TokenFileMonitor`

Watches credential source files for changes and emits notifications when a token refresh is detected.

**Protocol:**
```swift
protocol TokenFileMonitorProtocol {
    func startMonitoring()
    func stopMonitoring()
    var tokenChanged: AnyPublisher<Void, Never> { get }
}
```

**Watched files:**
1. `~/Library/Application Support/Claude/config.json` — primary (exists today)
2. `~/.claude/.credentials.json` — secondary (future-proof)

**Implementation:**
- `DispatchSource.makeFileSystemObjectSource` on the **parent directory** (`~/Library/Application Support/Claude/`) with `.write` event mask — NOT on the file directly. Monitoring the directory avoids two problems: (1) Claude Code writes atomically via rename, which breaks file-level DispatchSource (old inode), and (2) sandbox may block `open()` on the file but allow it on the directory
- After directory event fires, check if `config.json` modification date changed before triggering refresh
- 2-second debounce (Claude Code may write the file multiple times during a refresh)
- For `~/.claude/.credentials.json`: monitor `~/.claude/` directory similarly
- If the directory doesn't exist, skip silently — no error, no retry
- Publishes on `tokenChanged` subject when a relevant file change is detected

**Integration:**
- `UsageStore` subscribes to `tokenChanged`
- On event: calls `refresh()` immediately (bypasses timer)
- This is the primary refresh trigger; the backup timer is secondary

### Files

| Action | File |
|--------|------|
| Create | `Shared/Services/TokenFileMonitor.swift` |
| Create | `Shared/Services/Protocols/TokenFileMonitorProtocol.swift` |

---

## Section 3: Simplified UsageStore & Rate Limiting

### Refresh Pipeline (new)

```swift
func refresh(force: Bool = false) async {
    guard !isLoading else { return }

    // 1. Get token
    guard let token = tokenProvider.currentToken() else {
        errorState = .tokenUnavailable
        return
    }

    // 2. Interval check — use currentSpeed as the minimum interval
    if !force, let last = lastUpdate,
       Date().timeIntervalSince(last) < currentSpeed.rawValue { return }

    isLoading = true
    defer { isLoading = false }

    do {
        let usage = try await repository.refreshUsage(token: token, proxyConfig: proxyConfig)
        updateUI(from: usage)
        errorState = .none
        if currentSpeed == .slow { currentSpeed = .normal }
        lastUpdate = Date()
        WidgetReloader.scheduleReload()
        notificationService.checkThresholds(...) // existing signature unchanged
    } catch APIError.tokenExpired {
        // Try once more with a fresh token read
        if let freshToken = tokenProvider.currentToken(), freshToken != token {
            // Token was refreshed — retry
            do {
                let usage = try await repository.refreshUsage(token: freshToken, proxyConfig: proxyConfig)
                updateUI(from: usage)
                errorState = .none
                if currentSpeed == .slow { currentSpeed = .normal }
                lastUpdate = Date()
                WidgetReloader.scheduleReload()
                notificationService.checkThresholds(...) // existing signature unchanged
            } catch { errorState = .tokenUnavailable }
        } else {
            errorState = .tokenUnavailable
        }
    } catch APIError.rateLimited(let retryAfter) {
        currentSpeed = .slow
        retryAfterDate = Date().addingTimeInterval(retryAfter ?? RefreshSpeed.slow.rawValue)
        errorState = .rateLimited
    } catch {
        errorState = .networkError
    }
}
```

### Adaptive Refresh Speeds

```swift
enum RefreshSpeed: TimeInterval {
    case fast = 120      // After FSEvents token change — 2min
    case normal = 600    // Steady state — 10min
    case slow = 1200     // After 429 — 20min
}
```

**Transitions:**
- FSEvents fires → immediate refresh, then `currentSpeed = .fast` for 10 minutes
- After 10 min in `.fast` with no new FSEvents → `currentSpeed = .normal`
- After 429 → `currentSpeed = .slow`, respect `Retry-After` header if present
- After success in `.slow` → `currentSpeed = .normal`

### Profile Fetch

`fetchProfile()` is called once on first successful refresh (deferred from startup to save API quota, same as current behavior). It populates `planType`, `rateLimitTier`, and `organizationName`. The profile is re-fetched on reconnection (after token change) since the user/org might differ.

### Simplified Error States

```swift
enum AppErrorState: Equatable {
    case none
    case tokenUnavailable  // No token from any source, or 401 from API
    case rateLimited       // 429, shows countdown to next retry
    case networkError      // Timeout, DNS, connection refused
}
```

Replaces the current 5-state enum. User action is always the same for `tokenUnavailable`: check Claude Code is running, click "Reconnect".

**`isDisconnected` computed property** (used by views for banner/reconnect button): maps to `errorState == .tokenUnavailable`. Replaces the current check against `.tokenExpired`, `.keychainLocked`, `.needsReauth`.

**Claude Code not installed:** When `config.json` doesn't exist and no credentials file is found, `tokenProvider.currentToken()` returns nil. The app enters `tokenUnavailable` state. The backup timer still runs but each iteration returns immediately (no token). When the user eventually installs Claude Code and `config.json` appears, the FSEvents directory monitor detects it and triggers a refresh. No user action needed beyond installing Claude Code.

### Simplified UsageRepository

```swift
protocol UsageRepositoryProtocol {
    func refreshUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse
    func fetchProfile(token: String, proxyConfig: ProxyConfig?) async throws -> ProfileResponse
}
```

The repository no longer manages tokens, does token recovery, or syncs credential sources. It receives a token and makes an API call. Period.

### Files

| Action | File | Notes |
|--------|------|-------|
| Rewrite | `Shared/Stores/UsageStore.swift` | 276 → ~150 lines |
| Rewrite | `Shared/Repositories/UsageRepository.swift` | 106 → ~40 lines |
| Modify | `Shared/Models/MetricModels.swift` | New `AppErrorState` (3 cases vs 5) |
| Modify | `Shared/Services/APIClient.swift` | Remove `APIError.keychainLocked`, simplify |

---

## Section 4: Widget Refresh

### What Changes

The widget architecture stays the same (shared.json + WidgetReloader). Changes:

1. **OAuth token removed from shared.json** — security improvement, widget never needed it
2. **Wake handler** — `NSWorkspace.screensDidWakeNotification` triggers `refreshIfStale()`
3. **Better stale message** — "Last update X min ago" instead of just wifi.slash icon

### SharedData (updated)

```swift
// BEFORE:
struct SharedData: Codable {
    var oauthToken: String?        // REMOVED — security risk, widget never uses it
    var cachedUsage: CachedUsage?
    var lastSyncDate: Date?
    var theme: ThemeColors?
    var thresholds: UsageThresholds?
}

// AFTER:
struct SharedData: Codable {
    var cachedUsage: CachedUsage?
    var lastSyncDate: Date?
    var theme: ThemeColors?
    var thresholds: UsageThresholds?
}
```

### Widget Refresh Triggers (complete list)

| Trigger | Source | Condition |
|---------|--------|-----------|
| FSEvents | config.json changed | Token changed → API success → write shared.json → WidgetReloader |
| Backup timer | Every 10min | Normal speed; 2min in fast mode; 20min after 429 |
| Wake from sleep | `screensDidWakeNotification` | Only if lastSync > 2min |
| App activation | `didActivateApplicationNotification` | Already exists, just triggers WidgetReloader |
| Theme change | ThemeStore | Already exists |

### Files

| Action | File | Notes |
|--------|------|-------|
| Modify | `Shared/Services/SharedFileService.swift` | Remove `oauthToken` from SharedData |
| Modify | `TokenEaterApp/StatusBarController.swift` | Add wake handler, inject TokenFileMonitor |
| Modify | `TokenEaterWidget/UsageWidgetView.swift` | Better stale message text |

---

## Section 5: Onboarding

### Updated Connection Step

The 5-step onboarding flow remains (welcome → prerequisites → notifications → agent watchers → connection). The connection step changes:

**New flow:**
1. Check `~/Library/Application Support/Claude/config.json` exists
2. If missing → "Install and launch Claude Code first" (same as today)
3. If present → show explanation: "TokenEater needs one-time access to read Claude Code's encryption key. Click 'Always Allow' when prompted."
4. Call `tokenProvider.bootstrap()` → reads Keychain `Claude Safe Storage` → derives AES key → caches in TokenEater's own Keychain
5. Decrypt config.json → extract token
6. Test API call with extracted token
7. On success → write shared.json, start auto-refresh + FSEvents monitor

**One modal, explained in advance.** The user knows what to expect and why.

### Reconnection Flow (post-onboarding)

Triggered by "Reconnect" button in error banner:
1. `tokenProvider.currentToken()` — tries all sources with cached key
2. If token found → test API → success → clear error
3. If decryption fails (key invalid) → `tokenProvider.bootstrap()` → one Keychain modal → new key → retry
4. If config.json missing → "Claude Code not detected"

The Keychain modal only reappears if Claude Code was reinstalled (new encryption key). This is rare and justified.

### Files

| Action | File |
|--------|------|
| Rewrite | `TokenEaterApp/OnboardingViewModel.swift` |
| Modify | `TokenEaterApp/OnboardingSteps/ConnectionStep.swift` |

---

## Section 6: What Doesn't Change

The following components are not modified:

- **Agent watchers:** `SessionMonitorService`, `ProcessResolver`, `OverlayWindowController`, `SessionStore`, `AgentWatchersSectionView`
- **Stores:** `ThemeStore`, `SettingsStore`, `UpdateStore`, `SessionStore`
- **Views:** `MenuBarView`, `DashboardView`, `MainAppView`, all onboarding steps except ConnectionStep
- **Services:** `NotificationService`, `BrewMigrationService`, `UpdateService`
- **Helpers:** `PacingCalculator`, `MenuBarRenderer`, `WidgetReloader`, `JSONLParser`
- **Models:** `UsageResponse`, `ThemeColors`, `PacingModels`, `SessionModels`, `ProfileModels`
- **Widget:** `Provider.swift`, `PacingWidgetView.swift`, `TokenEaterWidget.swift`, `RefreshIntent.swift`

---

## Testing Strategy

### New Tests

| Test Suite | Covers |
|-----------|--------|
| `ElectronDecryptionServiceTests` | v10 prefix parsing, AES-128-CBC decryption, PKCS7 unpadding, key derivation, invalid data handling |
| `TokenProviderTests` | Source cascade (credentials file → config.json → keychain), bootstrap flow, key invalidation |
| `TokenFileMonitorTests` | File change detection, debounce behavior, non-existent file handling |
| `UsageStoreTests` (rewrite) | New refresh pipeline, 3-speed adaptive rate limiting, error state transitions, wake/stale logic |
| `UsageRepositoryTests` (rewrite) | Simple token-in → API call → result-out, no recovery logic |

### Existing Tests (unchanged)

- Pacing calculator tests
- Notification threshold tests
- Theme/settings tests
- Menu bar renderer tests

### Manual Testing

After implementation, full nuke + install cycle required (per CLAUDE.md):
- Build Release with Xcode 16.4
- Mega nuke (kill processes, clear caches, deregister plugin)
- Install, add widget, verify:
  - Onboarding shows one Keychain modal at connection step
  - Widget displays data after onboarding
  - Sleep/wake → widget updates within ~2min
  - No Keychain modals after onboarding
  - Kill Claude Code → relaunch → token auto-recovered via config.json
  - Rate limit simulation (manual 429 injection) → slow mode → recovery

---

## Migration

### SharedData Backward Compatibility

The `oauthToken` field is removed from `SharedData`. Since `SharedData` is `Codable`, old JSON files containing `oauthToken` will still decode correctly — `Codable` ignores unknown keys by default when using the compiler-synthesized init. No migration code needed.

### Existing Users

`hasCompletedOnboarding` is stored in `UserDefaults.standard` (not in shared.json), so it survives nuke cycles.

On first launch after update:
1. App checks `tokenProvider.isBootstrapped` → no cached key in TokenEater's Keychain → not bootstrapped
2. App shows reconnection prompt (not full onboarding — `hasCompletedOnboarding` is still true in UserDefaults)
3. User clicks "Reconnect" → bootstrap() → one Keychain modal → key cached in own Keychain → done forever

### CI

No CI changes needed. The build process is the same. New files use only Foundation + CommonCrypto (system frameworks, no new dependencies).

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Electron safeStorage format changes | Very low (Chromium standard, stable 10+ years) | Token unreadable | Fallback to Keychain silent read; detect and re-bootstrap |
| Claude Code reinstalled (new encryption key) | Low | One extra Keychain modal | Detect decryption failure → prompt user → re-bootstrap |
| `config.json` path changes in future Claude Code versions | Low | Token unreadable | Monitor Claude Code releases; path is an init parameter, easy to update |
| Anthropic implements `~/.claude/.credentials.json` on macOS | Medium (issue #22144) | Positive — pipeline picks it up automatically as source #1 | Already handled in TokenProvider cascade |
| FSEvents misses a write event | Very low | Stale data for up to 10min | Backup timer catches it |

---

## Summary of File Changes

### Created (8 files)
- `Shared/Services/ElectronDecryptionService.swift`
- `Shared/Services/ClaudeConfigReader.swift`
- `Shared/Services/TokenProvider.swift`
- `Shared/Services/TokenFileMonitor.swift`
- `Shared/Services/Protocols/ElectronDecryptionServiceProtocol.swift`
- `Shared/Services/Protocols/ClaudeConfigReaderProtocol.swift`
- `Shared/Services/Protocols/TokenProviderProtocol.swift`
- `Shared/Services/Protocols/TokenFileMonitorProtocol.swift`

### Deleted (4 files)
- `Shared/Services/KeychainService.swift`
- `Shared/Services/CredentialsFileReader.swift`
- `Shared/Services/Protocols/KeychainServiceProtocol.swift`
- `Shared/Services/Protocols/CredentialsFileReaderProtocol.swift`

### Rewritten (4 files)
- `Shared/Stores/UsageStore.swift` (276 → ~150 lines)
- `Shared/Repositories/UsageRepository.swift` (106 → ~40 lines)
- `TokenEaterApp/OnboardingViewModel.swift`
- Test files for UsageStore and UsageRepository

### Modified (7 files)
- `Shared/Services/SharedFileService.swift` (remove oauthToken)
- `Shared/Services/APIClient.swift` (remove keychainLocked error)
- `Shared/Models/MetricModels.swift` (simplified AppErrorState)
- `TokenEaterApp/StatusBarController.swift` (wake handler, monitor injection)
- `TokenEaterApp/OnboardingSteps/ConnectionStep.swift` (modal explanation UI)
- `TokenEaterApp/TokenEaterApp.entitlements` (add Claude/ read-only)
- `TokenEaterWidget/UsageWidgetView.swift` (better stale message)
