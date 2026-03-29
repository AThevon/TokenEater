# Eliminate Keychain Popups — Design Spec

**Issue:** #104 (widget doesn't update) + repeated Keychain password prompts
**Goal:** Zero Keychain popups after initial onboarding, surviving app and Claude Code updates.
**Date:** 2026-03-29

---

## Problem

TokenEater reads the Claude OAuth token from macOS Keychain. After any binary update (TokenEater or Claude Code), the Keychain ACL's `cdhash` no longer matches the new binary → macOS blocks silent reads → popup appears. This affects:

- Every app restart after update
- Wake from sleep (if macOS killed the process during sleep)
- Background auto-refresh (fails silently → widget shows stale data)

Previous fixes (v4.8.0 token provider refactoring, v4.8.1 in-memory caching) didn't solve this because the fallback path (config.json decryption) stores its AES key in **another Keychain item** (`"TokenEater"/"decryption-key"`) — same cdhash problem.

## Solution

Store the derived AES decryption key in a **file** instead of the Keychain. The file survives binary updates without ACL issues.

### Token Resolution Chain (after fix)

```
currentToken()
  1. In-memory cache (cachedToken)          → fast path, no I/O
  2. ~/.claude/.credentials.json            → file read, no keychain
  3. config.json + file-cached AES key      → file read + decrypt, no keychain  ← NEW PRIMARY
  4. Keychain "Claude Code-credentials"     → silent read, may fail after update
  5. return nil                             → show "reconnect" in UI
```

### Key Cache Location

**File:** `~/Library/Application Support/com.tokeneater.shared/decryption.key`

- Same directory as `shared.json` (already has read-write entitlement)
- Binary format: `[version_byte: UInt8][derived_key: 16 bytes]` (17 bytes total)
- Version byte `0x01` for forward compatibility
- File permissions: `0600` (owner read-write only)

### Bootstrap Flow (first install only)

```
Onboarding
  → Interactive read of "Claude Safe Storage" Keychain    → 1 popup (unavoidable)
  → PBKDF2 derive AES-128 key
  → Save key to file (decryption.key)                     ← replaces Keychain write
  → Decrypt config.json → get token
  → Cache token in memory
```

### Normal Operation (all subsequent launches)

```
App start / wake / refresh
  → Read key from file (decryption.key)                   → no popup
  → Decrypt config.json → get token                       → no popup
  → Cache in memory
```

### Failure Recovery

If config.json decryption fails (key changed after Claude reinstall):

```
Decryption fails
  → Try silent re-bootstrap: read "Claude Safe Storage" silently
    → Success? → re-derive key → save to file → decrypt → done (no popup)
    → Fail?   → Try Keychain "Claude Code-credentials" silently
      → Success? → use token directly → done (no popup)
      → Fail?   → Set errorState = .tokenUnavailable → user must re-onboard (1 popup)
```

## Changes

### Files to Modify

| File | Change |
|------|--------|
| `Shared/Services/ElectronDecryptionService.swift` | Replace `loadCachedKeyFromKeychain` / `saveCachedKeyToKeychain` / `deleteCachedKeyFromKeychain` with file-based equivalents. Add silent re-bootstrap attempt on decryption failure. |
| `Shared/Services/TokenProvider.swift` | Promote config.json to source #3 (before Keychain). Add silent re-bootstrap fallback when decryption fails. |
| `TokenEaterTests/ElectronDecryptionServiceTests.swift` | Update tests to verify file-based key storage instead of Keychain. |
| `TokenEaterTests/TokenProviderTests.swift` | Update tests for new fallback order and recovery flow. |

### Files NOT Changed

- `TokenEaterWidget/` — Widget reads `shared.json` only, no token logic
- `Shared/Services/SharedFileService.swift` — Unchanged, key file is managed by ElectronDecryptionService directly
- Entitlements — App already has read-write to `com.tokeneater.shared/`

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Fresh install, no Claude Code | `currentToken()` returns nil → onboarding prompts user to install CC |
| Claude Code updates token | config.json updated by CC → next decrypt gets fresh token → no popup |
| Claude Code reinstalled (new encryption key) | Decryption fails → silent re-bootstrap attempt → if fails, 1 popup on next onboarding |
| TokenEater updated | File survives → decrypt works → no popup |
| `decryption.key` file deleted | Falls back to Keychain silent read → if works, re-cache key to file. If fails, re-onboard. |
| macOS kills app during sleep | On wake: no in-memory cache → read from file → decrypt → no popup |
| `.credentials.json` appears (future CC update) | Source #2 catches it before config.json → still no popup |

## Security

- The AES key in the file is equivalent to what was in the Keychain — same derived key, same protection level
- The app is sandboxed; only TokenEater and the widget extension can access the directory
- File permissions `0600` prevent other user accounts from reading
- The key alone is useless without Claude's `config.json` — it can only decrypt that specific file
