# Robust OAuth/Keychain flow

## Context

Multiple GitHub issues (#18, #19, #22, #24) report the same problems:
- macOS bombards users with Keychain password prompts
- Expired tokens stay cached and the app retries in a loop with a dead token
- No automatic recovery when Claude Code refreshes the token

Root cause: `refresh()` reads the Keychain every 5 minutes via `readClaudeCodeToken()` (with `kSecReturnData: true` which triggers macOS dialogs). On 401/403, there's no cleanup or intelligent retry.

## Plan

### 1. `Shared/KeychainOAuthReader.swift` — Silent keychain read

Add `readClaudeCodeTokenSilently()` using `kSecUseAuthenticationUISkip` to read the Keychain without ever triggering a dialog. Factor the logic into a private `readToken(authenticationUI:)` method.

- `readClaudeCodeToken()` → unchanged (interactive mode, for onboarding/settings)
- `readClaudeCodeTokenSilently()` → new (silent mode, for periodic refresh and 401/403 recovery)
- `tokenExists()` → unchanged

### 2. `Shared/SharedContainer.swift` — Token status tracking

Add a `TokenStatus` enum (`.valid`, `.expired`, `.none`) and a `tokenStatus` field to `SharedData`.

- The `oauthToken` setter automatically sets status to `.valid` when writing a new token
- `isConfigured` returns `false` if the token is marked `.expired` (stops retry loops)
- Add `hasToken: Bool` (true if a token exists, even if expired — useful for UI)
- Add `markTokenExpired()` — marks without deleting (keeps the token for comparison)
- Add `clearToken()` — fully clears

### 3. `Shared/ClaudeAPIClient.swift` — Automatic recovery on 401/403

Add `fetchUsageWithRecovery()` wrapping `fetchUsage()`:

1. Normal API call
2. On 401/403 → `attemptSilentTokenRecovery()`:
   - Read Keychain silently
   - **Different** token from cache → update SharedContainer → retry API **once**
   - **Same** token → `markTokenExpired()` → throw `.tokenExpired`
   - Keychain inaccessible (nil) → throw `.keychainLocked` (DO NOT mark expired — keychain may just be locked)
3. Network errors → propagate as-is (no token cleanup)

Add `ClaudeAPIError.keychainLocked` to distinguish from `.tokenExpired`.

### 4. `ClaudeUsageApp/MenuBarView.swift` — Refactor refresh()

**Remove Keychain read from `refresh()`** — this is the main fix against popups.

The token is read at launch (`init()`) and in `reloadConfig()` (user interaction). During periodic refresh, the cached token in SharedContainer is used. If it's dead, recovery in `fetchUsageWithRecovery()` silently tries the Keychain.

Replace `hasError: Bool` with an `AppErrorState` enum:
- `.none` — all good
- `.tokenExpired` — token confirmed expired, show "!" red in menu bar
- `.keychainLocked` — keychain inaccessible, show guidance
- `.networkError(String)` — network error, keep last known data, retry next cycle

Keep `hasError` as a computed property (`errorState != .none`) for backward compatibility.

Add a contextual error banner in the popover:
- Token expired → "Run /login in Claude Code, then click Refresh"
- Keychain locked → "Open Settings → Connect to re-authorize"
- Network error → error message

### 5. `ClaudeUsageWidget/Provider.swift` — Indirect impact

The widget uses `SharedContainer.isConfigured` (line 24). With the new definition excluding expired tokens, the widget will show `.unconfigured` when the token is dead — correct behavior.

### 6. Localization — New keys

Add to `en.lproj/Localizable.strings` and `fr.lproj/Localizable.strings`:
- `error.keychainlocked`
- `error.banner.expired` / `error.banner.expired.hint`
- `error.banner.keychain` / `error.banner.keychain.hint`

## Files to modify

| File | Change |
|------|--------|
| `Shared/KeychainOAuthReader.swift` | Add `readClaudeCodeTokenSilently()` + refactor |
| `Shared/SharedContainer.swift` | Add `TokenStatus`, `markTokenExpired()`, modify `isConfigured` |
| `Shared/ClaudeAPIClient.swift` | Add `fetchUsageWithRecovery()`, `.keychainLocked` |
| `ClaudeUsageApp/MenuBarView.swift` | Refactor `refresh()`, add `AppErrorState`, error banner |
| `Shared/en.lproj/Localizable.strings` | New keys |
| `Shared/fr.lproj/Localizable.strings` | New keys |

## Verification

1. Build with the CLAUDE.md command
2. Verify the app starts without extra Keychain popups (init does 1 interactive read, that's normal)
3. Wait 5 min → confirm no Keychain dialog appears during refresh
4. Simulate an expired token (manually edit shared.json) → verify the error banner shows and the menu bar shows "!"
5. Run `/login` in Claude Code → verify the next refresh automatically picks up the new token

## Related issues

- #18 — stale session problem
- #19 — Endless authentication
- #22 — Not picking up OAuth token for Claude Max
- #24 — Session expired or invalid (HTTP 401)
