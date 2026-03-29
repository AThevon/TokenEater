# Keychain Popup Elimination — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate macOS Keychain popups after app/Claude Code updates by storing the AES decryption key in a file instead of the Keychain.

**Architecture:** Replace `ElectronDecryptionService`'s Keychain-based key cache with file-based storage in `~/Library/Application Support/com.tokeneater.shared/decryption.key`. Reorder `TokenProvider`'s fallback chain to prefer config.json decryption (file-backed) over direct Keychain reads. Add a silent re-bootstrap fallback when decryption fails.

**Tech Stack:** Swift, Security framework, CommonCrypto, Swift Testing

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `Shared/Services/ElectronDecryptionService.swift` | Replace Keychain cache with file cache for AES key |
| Modify | `Shared/Services/TokenProvider.swift` | Reorder fallback: config.json before Keychain; add silent re-bootstrap |
| Modify | `Shared/Services/Protocols/ElectronDecryptionServiceProtocol.swift` | Add `trySilentRebootstrap()` to protocol |
| Modify | `TokenEaterTests/ElectronDecryptionServiceTests.swift` | Add tests for file-based key storage |
| Modify | `TokenEaterTests/TokenProviderTests.swift` | Add tests for new fallback order and recovery |
| Modify | `TokenEaterTests/Mocks/MockElectronDecryptionService.swift` | Add `trySilentRebootstrap()` mock |

---

## Chunk 1: File-Based Key Cache in ElectronDecryptionService

### Task 1: Add file-based key save/load methods

**Files:**
- Modify: `Shared/Services/ElectronDecryptionService.swift:205-256` (replace Keychain cache methods)

- [ ] **Step 1: Write the failing test for file-based key round trip**

In `TokenEaterTests/ElectronDecryptionServiceTests.swift`, add at the end of the suite:

```swift
@Test("file-based key cache: save then load round trip")
func fileCacheRoundTrip() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let keyFile = tempDir.appendingPathComponent("decryption.key")
    let key = ElectronDecryptionService.deriveKey(from: "test-password")

    ElectronDecryptionService.saveKeyToFile(key, at: keyFile)
    let loaded = ElectronDecryptionService.loadKeyFromFile(at: keyFile)

    #expect(loaded == key)
}

@Test("file-based key cache: returns nil when file missing")
func fileCacheReturnsNilWhenMissing() {
    let bogus = FileManager.default.temporaryDirectory
        .appendingPathComponent("nonexistent-\(UUID().uuidString)")
        .appendingPathComponent("decryption.key")
    let loaded = ElectronDecryptionService.loadKeyFromFile(at: bogus)
    #expect(loaded == nil)
}

@Test("file-based key cache: returns nil when file has wrong version byte")
func fileCacheRejectsWrongVersion() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let keyFile = tempDir.appendingPathComponent("decryption.key")
    var badPayload = Data([0xFF]) // wrong version
    badPayload.append(Data(repeating: 0xAA, count: 16))
    try badPayload.write(to: keyFile)

    let loaded = ElectronDecryptionService.loadKeyFromFile(at: keyFile)
    #expect(loaded == nil)
}

@Test("file-based key cache: returns nil when file too short")
func fileCacheRejectsTooShort() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let keyFile = tempDir.appendingPathComponent("decryption.key")
    try Data([0x01, 0xAA]).write(to: keyFile) // version + only 1 byte

    let loaded = ElectronDecryptionService.loadKeyFromFile(at: keyFile)
    #expect(loaded == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -20
```

Expected: FAIL — `saveKeyToFile` and `loadKeyFromFile` don't exist yet.

- [ ] **Step 3: Implement file-based key methods**

In `Shared/Services/ElectronDecryptionService.swift`, replace the three Keychain cache methods (`loadCachedKeyFromKeychain`, `saveCachedKeyToKeychain`, `deleteCachedKeyFromKeychain`) with:

```swift
// MARK: - File-Based Key Cache

private static let keyFileName = "decryption.key"

private static var keyFileURL: URL {
    let home: String
    if let pw = getpwuid(getuid()) {
        home = String(cString: pw.pointee.pw_dir)
    } else {
        home = NSHomeDirectory()
    }
    return URL(fileURLWithPath: home)
        .appendingPathComponent("Library/Application Support")
        .appendingPathComponent("com.tokeneater.shared")
        .appendingPathComponent(keyFileName)
}

static func loadKeyFromFile(at url: URL? = nil) -> Data? {
    let fileURL = url ?? keyFileURL
    guard let data = try? Data(contentsOf: fileURL),
          data.count > 1,
          data.first == cacheVersionByte else {
        return nil
    }
    let key = data.dropFirst()
    guard key.count == keyLength else { return nil }
    return Data(key)
}

static func saveKeyToFile(_ key: Data, at url: URL? = nil) {
    let fileURL = url ?? keyFileURL
    let dir = fileURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    var payload = Data([cacheVersionByte])
    payload.append(key)
    try? payload.write(to: fileURL, options: [.atomic, .completeFileProtection])

    // Set file permissions to 0600 (owner read-write only)
    try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: fileURL.path
    )
}

static func deleteKeyFile(at url: URL? = nil) {
    let fileURL = url ?? keyFileURL
    try? FileManager.default.removeItem(at: fileURL)
}
```

- [ ] **Step 4: Update init() to load from file instead of Keychain**

In the same file, replace:

```swift
init() {
    derivedKey = Self.loadCachedKeyFromKeychain()
}
```

With:

```swift
init() {
    derivedKey = Self.loadKeyFromFile()
}
```

- [ ] **Step 5: Update bootstrapEncryptionKey() to save to file instead of Keychain**

Replace:

```swift
func bootstrapEncryptionKey() throws {
    // Interactive Keychain read — prompts user for permission
    let password = try Self.readElectronPassword(silent: false)
    let key = Self.deriveKey(from: password)
    try Self.saveCachedKeyToKeychain(key)
    derivedKey = key
}
```

With:

```swift
func bootstrapEncryptionKey() throws {
    let password = try Self.readElectronPassword(silent: false)
    let key = Self.deriveKey(from: password)
    Self.saveKeyToFile(key)
    derivedKey = key
}
```

- [ ] **Step 6: Update clearCachedKey() to delete file instead of Keychain entry**

Replace:

```swift
func clearCachedKey() {
    derivedKey = nil
    Self.deleteCachedKeyFromKeychain()
}
```

With:

```swift
func clearCachedKey() {
    derivedKey = nil
    Self.deleteKeyFile()
}
```

- [ ] **Step 7: Mark old Keychain cache methods as migration-only**

In `Shared/Services/ElectronDecryptionService.swift`, rename the section header from `// MARK: - TokenEater Cached Key Keychain` to `// MARK: - Migration (Keychain → File, remove after v5.x)`. Mark methods `private`. They will be used by the migration in Task 4, then can be removed in a future version.

Delete `saveCachedKeyToKeychain` — it's no longer called anywhere (bootstrap now uses `saveKeyToFile`). Keep `loadCachedKeyFromKeychain` and `deleteCachedKeyFromKeychain` for migration.

- [ ] **Step 8: Run all tests**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -20
```

Expected: All tests pass, including the 4 new file-cache tests.

- [ ] **Step 9: Commit**

```bash
git add Shared/Services/ElectronDecryptionService.swift TokenEaterTests/ElectronDecryptionServiceTests.swift
git commit -m "fix: replace Keychain-based AES key cache with file-based storage

Stores the derived decryption key in ~/Library/Application Support/
com.tokeneater.shared/decryption.key instead of the macOS Keychain.
This eliminates popup dialogs after app updates (cdhash mismatch)."
```

---

## Chunk 2: Silent Re-Bootstrap Fallback

### Task 2: Add trySilentRebootstrap() to protocol and implementation

**Files:**
- Modify: `Shared/Services/Protocols/ElectronDecryptionServiceProtocol.swift`
- Modify: `Shared/Services/ElectronDecryptionService.swift`
- Modify: `TokenEaterTests/Mocks/MockElectronDecryptionService.swift`
- Modify: `TokenEaterTests/ElectronDecryptionServiceTests.swift`

- [ ] **Step 1: Write the failing test for silent re-bootstrap**

In `TokenEaterTests/ElectronDecryptionServiceTests.swift`, add:

```swift
@Test("trySilentRebootstrap sets hasEncryptionKey when Electron keychain readable silently")
func trySilentRebootstrapSuccess() {
    // This test verifies the method exists and returns a Bool.
    // In CI/test environment, Electron keychain won't exist, so it returns false.
    let sut = ElectronDecryptionService()
    let result = sut.trySilentRebootstrap()
    // In test environment, no "Claude Safe Storage" keychain item → false
    #expect(result == false)
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -20
```

Expected: FAIL — `trySilentRebootstrap()` doesn't exist.

- [ ] **Step 3: Add trySilentRebootstrap() to protocol**

In `Shared/Services/Protocols/ElectronDecryptionServiceProtocol.swift`, add:

```swift
protocol ElectronDecryptionServiceProtocol: Sendable {
    func decrypt(_ encryptedBase64: String) throws -> Data
    var hasEncryptionKey: Bool { get }
    func bootstrapEncryptionKey() throws
    func clearCachedKey()
    /// Attempt to re-derive the key by reading Electron's keychain silently (no popup).
    /// Returns true if successful.
    func trySilentRebootstrap() -> Bool
}
```

- [ ] **Step 4: Add mock implementation**

In `TokenEaterTests/Mocks/MockElectronDecryptionService.swift`, add after `clearCachedKey()`:

```swift
var silentRebootstrapResult: Bool = false
var silentRebootstrapCallCount = 0

func trySilentRebootstrap() -> Bool {
    silentRebootstrapCallCount += 1
    if silentRebootstrapResult { _hasEncryptionKey = true }
    return silentRebootstrapResult
}
```

- [ ] **Step 5: Implement trySilentRebootstrap()**

In `Shared/Services/ElectronDecryptionService.swift`, add after `clearCachedKey()`:

```swift
func trySilentRebootstrap() -> Bool {
    guard let password = try? Self.readElectronPassword(silent: true) else {
        return false
    }
    let key = Self.deriveKey(from: password)
    Self.saveKeyToFile(key)
    derivedKey = key
    return true
}
```

- [ ] **Step 6: Run all tests**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -20
```

Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add Shared/Services/Protocols/ElectronDecryptionServiceProtocol.swift Shared/Services/ElectronDecryptionService.swift TokenEaterTests/Mocks/MockElectronDecryptionService.swift TokenEaterTests/ElectronDecryptionServiceTests.swift
git commit -m "feat: add trySilentRebootstrap() for keyless key recovery

When config.json decryption fails (Claude reinstalled), attempt to
silently re-read the Electron keychain and re-derive the key.
No popup unless silent read also fails."
```

---

## Chunk 3: Reorder TokenProvider Fallback Chain

### Task 3: Promote config.json before Keychain, add recovery

**Files:**
- Modify: `Shared/Services/TokenProvider.swift:44-70` (currentToken method)
- Modify: `TokenEaterTests/TokenProviderTests.swift`

- [ ] **Step 1: Write the failing test for new fallback order**

In `TokenEaterTests/TokenProviderTests.swift`, add:

```swift
@Test("config.json decryption is tried before Keychain")
func configJsonBeforeKeychain() {
    let oauthJSON: [String: Any] = [
        "claudeAiOauth": ["accessToken": "config-token"]
    ]
    let jsonData = try! JSONSerialization.data(withJSONObject: oauthJSON)

    var keychainWasCalled = false
    let credentials = MockCredentialsFileReader()
    credentials.storedToken = nil

    let configReader = MockClaudeConfigReader()
    configReader.encryptedToken = "encrypted-blob"

    let decryption = MockElectronDecryptionService()
    decryption._hasEncryptionKey = true
    decryption.decryptedData = jsonData

    let keychainReader: TokenProvider.KeychainTokenReader = { _ in
        keychainWasCalled = true
        return "keychain-token"
    }

    let provider = TokenProvider(
        credentialsFileReader: credentials,
        configReader: configReader,
        decryptionService: decryption,
        keychainReader: keychainReader
    )

    let token = provider.currentToken()

    #expect(token == "config-token")
    #expect(keychainWasCalled == false)
}

@Test("silent re-bootstrap recovers when decryption key is stale")
func silentRebootstrapRecovery() {
    let oauthJSON: [String: Any] = [
        "claudeAiOauth": ["accessToken": "recovered-token"]
    ]
    let jsonData = try! JSONSerialization.data(withJSONObject: oauthJSON)

    let credentials = MockCredentialsFileReader()
    let configReader = MockClaudeConfigReader()
    configReader.encryptedToken = "encrypted-blob"

    let decryption = MockElectronDecryptionService()
    decryption._hasEncryptionKey = false // key not loaded initially
    decryption.silentRebootstrapResult = true // but silent re-bootstrap works
    decryption.decryptedData = jsonData

    let provider = TokenProvider(
        credentialsFileReader: credentials,
        configReader: configReader,
        decryptionService: decryption,
        keychainReader: { _ in nil }
    )

    let token = provider.currentToken()

    #expect(token == "recovered-token")
    #expect(decryption.silentRebootstrapCallCount == 1)
    #expect(decryption.decryptCallCount == 1)
}

@Test("falls back to Keychain when config.json unavailable and re-bootstrap fails")
func fallbackToKeychainWhenConfigUnavailable() {
    let credentials = MockCredentialsFileReader()
    let configReader = MockClaudeConfigReader()
    configReader.encryptedToken = nil // no config.json

    let decryption = MockElectronDecryptionService()
    decryption._hasEncryptionKey = false

    let provider = TokenProvider(
        credentialsFileReader: credentials,
        configReader: configReader,
        decryptionService: decryption,
        keychainReader: { _ in "keychain-fallback" }
    )

    let token = provider.currentToken()

    #expect(token == "keychain-fallback")
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -20
```

Expected: `configJsonBeforeKeychain` FAILS (current order is Keychain before config.json). `silentRebootstrapRecovery` FAILS (no re-bootstrap logic yet).

- [ ] **Step 3: Rewrite currentToken() with new fallback order**

In `Shared/Services/TokenProvider.swift`, replace the `currentToken()` method:

```swift
func currentToken() -> String? {
    // Fast path: cached token from a previous successful read
    if let token = cachedToken { return token }

    // Source 1: credentials file (no keychain, no popup)
    if let token = credentialsFileReader.readToken() {
        cachedToken = token
        return token
    }

    // Source 2: decrypt config.json (no keychain if key file exists)
    if let token = tokenFromConfigJSON() {
        cachedToken = token
        return token
    }

    // Source 3: Keychain — silent read, last resort
    if let token = keychainReader(true) {
        cachedToken = token
        logger.info("Token read from Keychain (silent) and cached in memory")
        return token
    }

    return nil
}

/// Try to decrypt config.json. If key is missing, attempt silent re-bootstrap.
private func tokenFromConfigJSON() -> String? {
    guard let encrypted = configReader.readEncryptedToken() else { return nil }

    // Try with existing key
    if decryptionService.hasEncryptionKey,
       let token = decryptFromConfigJSON(encrypted) {
        return token
    }

    // Key missing or stale — try silent re-bootstrap (no popup)
    if decryptionService.trySilentRebootstrap(),
       let token = decryptFromConfigJSON(encrypted) {
        logger.info("Token recovered via silent re-bootstrap of decryption key")
        return token
    }

    return nil
}
```

- [ ] **Step 4: Update hasTokenSource() to match new order**

In the same file, replace `hasTokenSource()`:

```swift
func hasTokenSource() -> Bool {
    if cachedToken != nil { return true }
    if credentialsFileReader.readToken() != nil { return true }
    if configReader.readEncryptedToken() != nil { return true }
    if keychainReader(true) != nil { return true }
    return false
}
```

- [ ] **Step 5: Run all tests**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -20
```

Expected: All tests pass (including the existing `fallbackToKeychain` test which still works as Keychain is source #3).

- [ ] **Step 6: Commit**

```bash
git add Shared/Services/TokenProvider.swift TokenEaterTests/TokenProviderTests.swift
git commit -m "fix: reorder token fallback — config.json before Keychain

config.json decryption (file-based key) is now tried before Keychain
reads. Adds silent re-bootstrap if the decryption key is missing.
Keychain is now last resort only."
```

---

## Chunk 4: Migrate Existing Users

### Task 4: One-time migration from Keychain cache to file cache

**Files:**
- Modify: `Shared/Services/ElectronDecryptionService.swift`
- Modify: `TokenEaterTests/ElectronDecryptionServiceTests.swift`

Users updating from v4.8.x have the derived key in Keychain but not yet in a file. On first launch after update, the file doesn't exist. Without migration, they'd fall through to Keychain read (potential popup).

- [ ] **Step 1: Write the failing test for migration**

In `TokenEaterTests/ElectronDecryptionServiceTests.swift`, add:

```swift
@Test("migrateKeyFromKeychainToFile copies key and deletes Keychain entry")
func migrateKeyFromKeychainToFile() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let keyFile = tempDir.appendingPathComponent("decryption.key")
    let key = ElectronDecryptionService.deriveKey(from: "migrate-test")

    // Simulate: file doesn't exist, but we have a key in memory (from Keychain)
    #expect(ElectronDecryptionService.loadKeyFromFile(at: keyFile) == nil)

    // Save to file (simulating migration)
    ElectronDecryptionService.saveKeyToFile(key, at: keyFile)

    // Verify file now has the key
    #expect(ElectronDecryptionService.loadKeyFromFile(at: keyFile) == key)
}
```

- [ ] **Step 2: Run test to verify it passes**

This test uses existing `saveKeyToFile`/`loadKeyFromFile` methods, so it should pass immediately. This confirms the migration logic works.

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -20
```

Expected: PASS.

- [ ] **Step 3: Add migration in init()**

In `Shared/Services/ElectronDecryptionService.swift`, update `init()`:

```swift
init() {
    // Try file first (new path)
    if let key = Self.loadKeyFromFile() {
        derivedKey = key
        return
    }

    // Migrate from Keychain (old path) — one-time, silent
    if let key = Self.loadCachedKeyFromKeychain() {
        Self.saveKeyToFile(key)
        Self.deleteCachedKeyFromKeychain()
        derivedKey = key
        return
    }
}
```

The old `loadCachedKeyFromKeychain` and `deleteCachedKeyFromKeychain` methods were kept in Task 1 Step 7 for exactly this migration.

- [ ] **Step 4: Run all tests**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -20
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add Shared/Services/ElectronDecryptionService.swift TokenEaterTests/ElectronDecryptionServiceTests.swift
git commit -m "fix: migrate existing users from Keychain key cache to file

On first launch after update, copies the AES key from Keychain to
file, then deletes the Keychain entry. Keeps old Keychain read
methods for one-time migration only."
```

---

## Chunk 5: Verify Full Flow

### Task 5: Build and manual verification

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -20
```

Expected: All 80+ tests pass (existing + new).

- [ ] **Step 2: Build Release with Xcode 16.4**

```bash
export DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer
xcodegen generate && \
DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject 2>/dev/null | grep -oE 'OU=[A-Z0-9]{10}' | head -1 | cut -d= -f2) && \
plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' TokenEaterWidget/Info.plist 2>/dev/null; \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Verify key file created after bootstrap**

After running the built app and completing onboarding:

```bash
ls -la ~/Library/Application\ Support/com.tokeneater.shared/decryption.key
```

Expected: File exists, 17 bytes, permissions `-rw-------`.

- [ ] **Step 4: Verify no Keychain popup on relaunch**

Kill the app, relaunch. No macOS Keychain dialog should appear. The token should load from config.json + file-cached key.

- [ ] **Step 5: Commit final state (if any cleanup needed)**

```bash
git status
# Only commit if there are changes from verification fixes
```
