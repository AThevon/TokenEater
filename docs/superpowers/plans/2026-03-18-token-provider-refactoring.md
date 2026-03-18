# Token Provider Refactoring Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Keychain-based token reads with Electron safeStorage decryption to eliminate recurring macOS Keychain modals, and simplify the refresh pipeline with FSEvents-driven reactive updates.

**Architecture:** New `TokenProvider` service reads tokens by decrypting Claude Code's `config.json` using a cached AES key (derived once during onboarding from the stable `Claude Safe Storage` Keychain entry). `TokenFileMonitor` watches for file changes via FSEvents on the parent directory. `UsageStore` is simplified with 3-speed adaptive rate limiting.

**Tech Stack:** Swift 5.9, CommonCrypto (AES-128-CBC, PBKDF2), DispatchSource (FSEvents), Combine (publishers), Swift Testing framework

**Spec:** `docs/superpowers/specs/2026-03-18-token-provider-refactoring-design.md`

**Build command:** `xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -20`

**Important project rules (from CLAUDE.md):**
- No `@Observable` — use `ObservableObject` + `@Published`
- No `@StateObject` in App struct — use `private let`
- Protocol-based services, dependency injection via init
- Swift Testing framework (`import Testing`, `@Test`, `#expect`)
- Mocks in `TokenEaterTests/Mocks/`
- Stores are `@MainActor` → test suites must also be `@MainActor`
- GitHub content (commits, branches) in English

---

## File Map

### New Files
| File | Responsibility |
|------|---------------|
| `Shared/Services/ElectronDecryptionService.swift` | AES-128-CBC decryption of Electron safeStorage, PBKDF2 key derivation, key caching in TokenEater's own Keychain |
| `Shared/Services/ClaudeConfigReader.swift` | Read and parse `~/Library/Application Support/Claude/config.json`, extract `oauth:tokenCache` |
| `Shared/Services/TokenProvider.swift` | Single entry point for token resolution: credentials file → config.json decryption → Keychain fallback |
| `Shared/Services/TokenFileMonitor.swift` | FSEvents directory monitoring on Claude's config and credentials paths, Combine publisher |
| `Shared/Services/Protocols/ElectronDecryptionServiceProtocol.swift` | Protocol for decryption service |
| `Shared/Services/Protocols/ClaudeConfigReaderProtocol.swift` | Protocol for config reader |
| `Shared/Services/Protocols/TokenProviderProtocol.swift` | Protocol for token provider |
| `Shared/Services/Protocols/TokenFileMonitorProtocol.swift` | Protocol for file monitor |
| `TokenEaterTests/Mocks/MockElectronDecryptionService.swift` | Mock for tests |
| `TokenEaterTests/Mocks/MockClaudeConfigReader.swift` | Mock for tests |
| `TokenEaterTests/Mocks/MockTokenProvider.swift` | Mock for tests |
| `TokenEaterTests/Mocks/MockTokenFileMonitor.swift` | Mock for tests |
| `TokenEaterTests/ElectronDecryptionServiceTests.swift` | Decryption unit tests |
| `TokenEaterTests/TokenProviderTests.swift` | Token cascade unit tests |

### Deleted Files
| File | Reason |
|------|--------|
| `Shared/Services/KeychainService.swift` | Replaced by TokenProvider + ElectronDecryptionService |
| `Shared/Services/Protocols/KeychainServiceProtocol.swift` | Replaced |
| `TokenEaterTests/Mocks/MockKeychainService.swift` | Replaced by MockTokenProvider |
| `TokenEaterTests/CredentialsFileReaderTests.swift` | Replaced by TokenProviderTests |
| `TokenEaterTests/KeychainServiceTests.swift` | KeychainService deleted |

### Modified Files
| File | Change |
|------|--------|
| `Shared/Services/SharedFileService.swift` | Remove `oauthToken` from SharedData |
| `Shared/Models/MetricModels.swift` | Simplify `AppErrorState` to 3 cases |
| `Shared/Services/APIClient.swift` | Remove `APIError.keychainLocked` |
| `Shared/Repositories/UsageRepository.swift` | Rewrite: token-in → API call → result-out |
| `Shared/Stores/UsageStore.swift` | Rewrite: new refresh pipeline, adaptive speeds |
| `TokenEaterApp/TokenEaterApp.swift` | Replace KeychainService with TokenProvider + TokenFileMonitor in DI |
| `TokenEaterApp/StatusBarController.swift` | Add wake handler, inject monitor, subscribe to tokenChanged |
| `TokenEaterApp/OnboardingViewModel.swift` | New connection flow with bootstrap |
| `TokenEaterApp/OnboardingSteps/ConnectionStep.swift` | UI explaining the one-time Keychain modal |
| `TokenEaterApp/TokenEaterApp.entitlements` | Add `/Library/Application Support/Claude/` read-only |
| `TokenEaterWidget/UsageWidgetView.swift` | Better stale message |
| `Shared/Services/Protocols/SharedFileServiceProtocol.swift` | Remove oauthToken |
| `TokenEaterApp/MenuBarView.swift` | Update AppErrorState switch (old 5 cases → new 3) |
| `TokenEaterApp/SettingsSectionView.swift` | Update AppErrorState references |
| `TokenEaterTests/Mocks/MockAPIClient.swift` | Update for changed repository protocol |
| `TokenEaterTests/UsageStoreTests.swift` | Rewrite for new pipeline |
| `TokenEaterTests/UsageRepositoryTests.swift` | Rewrite for simplified repo |

### Kept As-Is (no changes needed)
- `CredentialsFileReader.swift` + protocol — kept as source #1 in TokenProvider cascade
- `MockCredentialsFileReader.swift` — still used by TokenProviderTests
- All agent watcher files, ThemeStore, SettingsStore, SessionStore, NotificationService, widget Provider/PacingWidgetView

---

## Task 1: Protocols & Mocks (foundation)

**Files:**
- Create: `Shared/Services/Protocols/ElectronDecryptionServiceProtocol.swift`
- Create: `Shared/Services/Protocols/ClaudeConfigReaderProtocol.swift`
- Create: `Shared/Services/Protocols/TokenProviderProtocol.swift`
- Create: `Shared/Services/Protocols/TokenFileMonitorProtocol.swift`
- Create: `TokenEaterTests/Mocks/MockElectronDecryptionService.swift`
- Create: `TokenEaterTests/Mocks/MockClaudeConfigReader.swift`
- Create: `TokenEaterTests/Mocks/MockTokenProvider.swift`
- Create: `TokenEaterTests/Mocks/MockTokenFileMonitor.swift`

- [ ] **Step 1: Create ElectronDecryptionServiceProtocol**

```swift
// Shared/Services/Protocols/ElectronDecryptionServiceProtocol.swift
import Foundation

protocol ElectronDecryptionServiceProtocol: Sendable {
    func decrypt(_ encryptedBase64: String) throws -> Data
    var hasEncryptionKey: Bool { get }
    func bootstrapEncryptionKey() throws
    func clearCachedKey()
}
```

- [ ] **Step 2: Create ClaudeConfigReaderProtocol**

```swift
// Shared/Services/Protocols/ClaudeConfigReaderProtocol.swift
import Foundation

protocol ClaudeConfigReaderProtocol: Sendable {
    func readEncryptedToken() -> String?
}
```

- [ ] **Step 3: Create TokenProviderProtocol**

```swift
// Shared/Services/Protocols/TokenProviderProtocol.swift
import Foundation

protocol TokenProviderProtocol: Sendable {
    func currentToken() -> String?
    var isBootstrapped: Bool { get }
    func bootstrap() throws
}
```

- [ ] **Step 4: Create TokenFileMonitorProtocol**

```swift
// Shared/Services/Protocols/TokenFileMonitorProtocol.swift
import Foundation
import Combine

protocol TokenFileMonitorProtocol {
    func startMonitoring()
    func stopMonitoring()
    var tokenChanged: AnyPublisher<Void, Never> { get }
}
```

- [ ] **Step 5: Create MockElectronDecryptionService**

```swift
// TokenEaterTests/Mocks/MockElectronDecryptionService.swift
import Foundation
@testable import TokenEaterApp

final class MockElectronDecryptionService: ElectronDecryptionServiceProtocol, @unchecked Sendable {
    var decryptedData: Data?
    var decryptError: Error?
    var _hasEncryptionKey: Bool = false
    var bootstrapError: Error?
    var bootstrapCallCount = 0
    var decryptCallCount = 0

    var hasEncryptionKey: Bool { _hasEncryptionKey }

    func decrypt(_ encryptedBase64: String) throws -> Data {
        decryptCallCount += 1
        if let error = decryptError { throw error }
        return decryptedData ?? Data()
    }

    func bootstrapEncryptionKey() throws {
        bootstrapCallCount += 1
        if let error = bootstrapError { throw error }
        _hasEncryptionKey = true
    }

    func clearCachedKey() {
        _hasEncryptionKey = false
    }
}
```

- [ ] **Step 6: Create MockClaudeConfigReader**

```swift
// TokenEaterTests/Mocks/MockClaudeConfigReader.swift
import Foundation
@testable import TokenEaterApp

final class MockClaudeConfigReader: ClaudeConfigReaderProtocol, @unchecked Sendable {
    var encryptedToken: String?

    func readEncryptedToken() -> String? {
        encryptedToken
    }
}
```

- [ ] **Step 7: Create MockTokenProvider**

```swift
// TokenEaterTests/Mocks/MockTokenProvider.swift
import Foundation
@testable import TokenEaterApp

final class MockTokenProvider: TokenProviderProtocol, @unchecked Sendable {
    var token: String?
    var _isBootstrapped: Bool = true
    var bootstrapError: Error?
    var bootstrapCallCount = 0
    var currentTokenCallCount = 0

    var isBootstrapped: Bool { _isBootstrapped }

    func currentToken() -> String? {
        currentTokenCallCount += 1
        return token
    }

    func bootstrap() throws {
        bootstrapCallCount += 1
        if let error = bootstrapError { throw error }
        _isBootstrapped = true
    }
}
```

- [ ] **Step 8: Create MockTokenFileMonitor**

```swift
// TokenEaterTests/Mocks/MockTokenFileMonitor.swift
import Foundation
import Combine
@testable import TokenEaterApp

final class MockTokenFileMonitor: TokenFileMonitorProtocol {
    private let subject = PassthroughSubject<Void, Never>()
    var startCallCount = 0
    var stopCallCount = 0

    var tokenChanged: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    func startMonitoring() { startCallCount += 1 }
    func stopMonitoring() { stopCallCount += 1 }

    func simulateTokenChange() { subject.send(()) }
}
```

- [ ] **Step 9: Verify build compiles**

Run: `xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 10: Commit**

```bash
git add Shared/Services/Protocols/ElectronDecryptionServiceProtocol.swift \
        Shared/Services/Protocols/ClaudeConfigReaderProtocol.swift \
        Shared/Services/Protocols/TokenProviderProtocol.swift \
        Shared/Services/Protocols/TokenFileMonitorProtocol.swift \
        TokenEaterTests/Mocks/MockElectronDecryptionService.swift \
        TokenEaterTests/Mocks/MockClaudeConfigReader.swift \
        TokenEaterTests/Mocks/MockTokenProvider.swift \
        TokenEaterTests/Mocks/MockTokenFileMonitor.swift
git commit -m "feat: add protocols and mocks for token provider refactoring"
```

---

## Task 2: ElectronDecryptionService (core crypto)

**Files:**
- Create: `Shared/Services/ElectronDecryptionService.swift`
- Create: `TokenEaterTests/ElectronDecryptionServiceTests.swift`

- [ ] **Step 1: Write failing tests for decryption**

```swift
// TokenEaterTests/ElectronDecryptionServiceTests.swift
import Testing
import Foundation
@testable import TokenEaterApp

@Suite("ElectronDecryptionService")
struct ElectronDecryptionServiceTests {

    // Known test vector: encrypt "hello" with key derived from password "testpass"
    // PBKDF2(password="testpass", salt="saltysalt", iterations=1003, keylen=16)
    // AES-128-CBC(key, iv=16spaces, plaintext="hello"+PKCS7padding)
    // Prepend "v10", base64 encode

    @Test("rejects data without v10 prefix")
    func rejectsInvalidPrefix() throws {
        let service = ElectronDecryptionService()
        // Manually set a dummy key for testing
        service.setDerivedKeyForTesting(Data(repeating: 0x42, count: 16))
        let invalidBase64 = ("xx" + String(repeating: "A", count: 16)).data(using: .utf8)!.base64EncodedString()
        #expect(throws: ElectronDecryptionError.self) {
            try service.decrypt(invalidBase64)
        }
    }

    @Test("rejects empty data")
    func rejectsEmpty() throws {
        let service = ElectronDecryptionService()
        service.setDerivedKeyForTesting(Data(repeating: 0x42, count: 16))
        #expect(throws: ElectronDecryptionError.self) {
            try service.decrypt("")
        }
    }

    @Test("hasEncryptionKey is false before bootstrap")
    func noKeyBeforeBootstrap() {
        let service = ElectronDecryptionService()
        #expect(!service.hasEncryptionKey)
    }

    @Test("clearCachedKey removes the key")
    func clearKey() {
        let service = ElectronDecryptionService()
        service.setDerivedKeyForTesting(Data(repeating: 0x42, count: 16))
        #expect(service.hasEncryptionKey)
        service.clearCachedKey()
        #expect(!service.hasEncryptionKey)
    }

    @Test("PBKDF2 key derivation produces correct length")
    func keyDerivation() throws {
        let key = ElectronDecryptionService.deriveKey(from: "testpassword")
        #expect(key.count == 16)
    }

    @Test("full decrypt round-trip with known ciphertext")
    func fullDecrypt() throws {
        // Generate a known ciphertext using the same algorithm
        // We'll test this with a real encrypted value from config.json in integration
        let service = ElectronDecryptionService()
        let password = "testpassword"
        let key = ElectronDecryptionService.deriveKey(from: password)
        service.setDerivedKeyForTesting(key)

        // Encrypt "hello world" manually for test vector
        let plaintext = "hello world".data(using: .utf8)!
        let encrypted = try ElectronDecryptionService.encryptForTesting(plaintext: plaintext, key: key)
        let base64 = encrypted.base64EncodedString()

        let decrypted = try service.decrypt(base64)
        let result = String(data: decrypted, encoding: .utf8)
        #expect(result == "hello world")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | grep -E "(FAIL|PASS|error:)" | head -10`
Expected: Compilation errors (ElectronDecryptionService not found)

- [ ] **Step 3: Implement ElectronDecryptionService**

```swift
// Shared/Services/ElectronDecryptionService.swift
import Foundation
import CommonCrypto
import Security

enum ElectronDecryptionError: Error {
    case invalidBase64
    case invalidPrefix
    case decryptionFailed
    case noEncryptionKey
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)
    case keyDerivationFailed
}

final class ElectronDecryptionService: ElectronDecryptionServiceProtocol, @unchecked Sendable {

    private static let v10Prefix = Data([0x76, 0x31, 0x30]) // "v10"
    private static let iv = Data(repeating: 0x20, count: 16)  // 16 spaces
    private static let salt = "saltysalt".data(using: .utf8)!
    private static let iterations: UInt32 = 1003
    private static let keyLength = 16 // AES-128

    // Keychain entry for cached derived key
    private static let keychainService = "TokenEater"
    private static let keychainAccount = "decryption-key"
    private static let keyVersion: UInt8 = 0x01

    // In-memory cache
    private var derivedKey: Data?

    var hasEncryptionKey: Bool { derivedKey != nil }

    init() {
        // Try to load cached key from TokenEater's own Keychain
        derivedKey = loadKeyFromKeychain()
    }

    func decrypt(_ encryptedBase64: String) throws -> Data {
        guard let key = derivedKey else { throw ElectronDecryptionError.noEncryptionKey }
        guard let rawData = Data(base64Encoded: encryptedBase64), rawData.count > 3 else {
            throw ElectronDecryptionError.invalidBase64
        }
        guard rawData.prefix(3) == Self.v10Prefix else {
            throw ElectronDecryptionError.invalidPrefix
        }
        let ciphertext = rawData.dropFirst(3)
        return try aesDecrypt(ciphertext: Data(ciphertext), key: key)
    }

    func bootstrapEncryptionKey() throws {
        // Read password from Claude Code's Keychain entry
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Safe Storage",
            kSecAttrAccount as String: "Claude Key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let passwordData = result as? Data else {
            throw ElectronDecryptionError.keychainReadFailed(status)
        }
        // The password is the raw base64 string from Keychain, used as-is
        let password = String(data: passwordData, encoding: .utf8) ?? passwordData.base64EncodedString()
        let key = Self.deriveKey(from: password)
        derivedKey = key
        try saveKeyToKeychain(key)
    }

    func clearCachedKey() {
        derivedKey = nil
        deleteKeyFromKeychain()
    }

    // MARK: - Key Derivation

    static func deriveKey(from password: String) -> Data {
        let passwordData = password.data(using: .utf8)!
        var derivedBytes = [UInt8](repeating: 0, count: keyLength)
        passwordData.withUnsafeBytes { passwordPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                    passwordData.count,
                    saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    iterations,
                    &derivedBytes,
                    keyLength
                )
            }
        }
        return Data(derivedBytes)
    }

    // MARK: - AES Decryption

    private func aesDecrypt(ciphertext: Data, key: Data) throws -> Data {
        let bufferSize = ciphertext.count + kCCBlockSizeAES128
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var numBytesDecrypted = 0

        let status = ciphertext.withUnsafeBytes { ciphertextPtr in
            key.withUnsafeBytes { keyPtr in
                Self.iv.withUnsafeBytes { ivPtr in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyPtr.baseAddress, key.count,
                        ivPtr.baseAddress,
                        ciphertextPtr.baseAddress, ciphertext.count,
                        &buffer, bufferSize,
                        &numBytesDecrypted
                    )
                }
            }
        }

        guard status == kCCSuccess else { throw ElectronDecryptionError.decryptionFailed }
        return Data(buffer.prefix(numBytesDecrypted))
    }

    // MARK: - Own Keychain (TokenEater's cached key)

    private func loadKeyFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, data.count > 1,
              data[0] == Self.keyVersion else { return nil }
        return data.dropFirst()
    }

    private func saveKeyToKeychain(_ key: Data) throws {
        deleteKeyFromKeychain() // Remove old entry if exists
        var versionedKey = Data([Self.keyVersion])
        versionedKey.append(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecValueData as String: versionedKey,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ElectronDecryptionError.keychainWriteFailed(status)
        }
    }

    private func deleteKeyFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Testing Helpers

    #if DEBUG
    func setDerivedKeyForTesting(_ key: Data) { derivedKey = key }

    static func encryptForTesting(plaintext: Data, key: Data) throws -> Data {
        let bufferSize = plaintext.count + kCCBlockSizeAES128
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var numBytesEncrypted = 0
        let status = plaintext.withUnsafeBytes { ptPtr in
            key.withUnsafeBytes { keyPtr in
                iv.withUnsafeBytes { ivPtr in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyPtr.baseAddress, key.count,
                        ivPtr.baseAddress,
                        ptPtr.baseAddress, plaintext.count,
                        &buffer, bufferSize,
                        &numBytesEncrypted
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw ElectronDecryptionError.decryptionFailed }
        var result = v10Prefix
        result.append(contentsOf: buffer.prefix(numBytesEncrypted))
        return result
    }
    #endif
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -10`
Expected: All ElectronDecryptionServiceTests pass

- [ ] **Step 5: Commit**

```bash
git add Shared/Services/ElectronDecryptionService.swift TokenEaterTests/ElectronDecryptionServiceTests.swift
git commit -m "feat: implement ElectronDecryptionService with AES-128-CBC decryption"
```

---

## Task 3: ClaudeConfigReader + TokenProvider

**Files:**
- Create: `Shared/Services/ClaudeConfigReader.swift`
- Create: `Shared/Services/TokenProvider.swift`
- Create: `TokenEaterTests/TokenProviderTests.swift`

- [ ] **Step 1: Write failing tests for TokenProvider cascade**

```swift
// TokenEaterTests/TokenProviderTests.swift
import Testing
import Foundation
@testable import TokenEaterApp

@Suite("TokenProvider")
struct TokenProviderTests {

    @Test("credentials file is tried first")
    func credentialsFileFirst() {
        let credReader = MockCredentialsFileReader()
        credReader.token = "cred-token"
        let configReader = MockClaudeConfigReader()
        let decryption = MockElectronDecryptionService()
        let provider = TokenProvider(
            credentialsFileReader: credReader,
            configReader: configReader,
            decryptionService: decryption
        )
        #expect(provider.currentToken() == "cred-token")
        #expect(decryption.decryptCallCount == 0) // didn't need decryption
    }

    @Test("falls back to config.json decryption when credentials file missing")
    func configJsonFallback() throws {
        let credReader = MockCredentialsFileReader()
        credReader.token = nil
        let configReader = MockClaudeConfigReader()
        configReader.encryptedToken = "encrypted-base64"
        let decryption = MockElectronDecryptionService()
        decryption._hasEncryptionKey = true
        let tokenJSON = """
        {"claudeAiOauth":{"accessToken":"decrypted-token"}}
        """.data(using: .utf8)!
        decryption.decryptedData = tokenJSON
        let provider = TokenProvider(
            credentialsFileReader: credReader,
            configReader: configReader,
            decryptionService: decryption
        )
        #expect(provider.currentToken() == "decrypted-token")
        #expect(decryption.decryptCallCount == 1)
    }

    @Test("returns nil when no source available")
    func noSource() {
        let credReader = MockCredentialsFileReader()
        let configReader = MockClaudeConfigReader()
        let decryption = MockElectronDecryptionService()
        let provider = TokenProvider(
            credentialsFileReader: credReader,
            configReader: configReader,
            decryptionService: decryption
        )
        #expect(provider.currentToken() == nil)
    }

    @Test("isBootstrapped reflects decryption service state")
    func bootstrapState() {
        let decryption = MockElectronDecryptionService()
        decryption._hasEncryptionKey = false
        let provider = TokenProvider(
            credentialsFileReader: MockCredentialsFileReader(),
            configReader: MockClaudeConfigReader(),
            decryptionService: decryption
        )
        #expect(!provider.isBootstrapped)
        decryption._hasEncryptionKey = true
        #expect(provider.isBootstrapped)
    }

    @Test("bootstrap delegates to decryption service")
    func bootstrapDelegates() throws {
        let decryption = MockElectronDecryptionService()
        let provider = TokenProvider(
            credentialsFileReader: MockCredentialsFileReader(),
            configReader: MockClaudeConfigReader(),
            decryptionService: decryption
        )
        try provider.bootstrap()
        #expect(decryption.bootstrapCallCount == 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: Compilation errors (TokenProvider not found)

- [ ] **Step 3: Implement ClaudeConfigReader**

```swift
// Shared/Services/ClaudeConfigReader.swift
import Foundation

final class ClaudeConfigReader: ClaudeConfigReaderProtocol, @unchecked Sendable {

    private let configPath: String

    init() {
        guard let pw = getpwuid(getuid()) else { configPath = ""; return }
        let home = String(cString: pw.pointee.pw_dir)
        configPath = home + "/Library/Application Support/Claude/config.json"
    }

    init(configPath: String) { self.configPath = configPath }

    func readEncryptedToken() -> String? {
        guard let data = FileManager.default.contents(atPath: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let encrypted = json["oauth:tokenCache"] as? String,
              !encrypted.isEmpty
        else { return nil }
        return encrypted
    }
}
```

- [ ] **Step 4: Implement TokenProvider**

```swift
// Shared/Services/TokenProvider.swift
import Foundation

final class TokenProvider: TokenProviderProtocol, @unchecked Sendable {

    private let credentialsFileReader: CredentialsFileReaderProtocol
    private let configReader: ClaudeConfigReaderProtocol
    private let decryptionService: ElectronDecryptionServiceProtocol

    init(
        credentialsFileReader: CredentialsFileReaderProtocol = CredentialsFileReader(),
        configReader: ClaudeConfigReaderProtocol = ClaudeConfigReader(),
        decryptionService: ElectronDecryptionServiceProtocol = ElectronDecryptionService()
    ) {
        self.credentialsFileReader = credentialsFileReader
        self.configReader = configReader
        self.decryptionService = decryptionService
    }

    var isBootstrapped: Bool { decryptionService.hasEncryptionKey }

    func currentToken() -> String? {
        // Source 1: credentials file (future-proof for macOS)
        if let token = credentialsFileReader.readToken() { return token }

        // Source 2: decrypt config.json
        if decryptionService.hasEncryptionKey,
           let encrypted = configReader.readEncryptedToken(),
           let data = try? decryptionService.decrypt(encrypted),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String,
           !token.isEmpty {
            return token
        }

        return nil
    }

    func bootstrap() throws {
        try decryptionService.bootstrapEncryptionKey()
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -10`
Expected: All TokenProviderTests pass

- [ ] **Step 6: Commit**

```bash
git add Shared/Services/ClaudeConfigReader.swift Shared/Services/TokenProvider.swift TokenEaterTests/TokenProviderTests.swift
git commit -m "feat: implement TokenProvider with credentials file + config.json decryption cascade"
```

---

## Task 4: TokenFileMonitor (FSEvents)

**Files:**
- Create: `Shared/Services/TokenFileMonitor.swift`

- [ ] **Step 1: Implement TokenFileMonitor**

```swift
// Shared/Services/TokenFileMonitor.swift
import Foundation
import Combine

final class TokenFileMonitor: TokenFileMonitorProtocol {

    private let subject = PassthroughSubject<Void, Never>()
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private let debounceInterval: TimeInterval
    private var lastEmit: Date = .distantPast
    private let queue = DispatchQueue(label: "com.tokeneater.filemonitor", qos: .utility)

    /// Directories to watch (not files — handles atomic renames)
    private let watchedDirectories: [String]
    /// Filenames within those directories to check modification dates
    private let watchedFilenames: [String: String] // directory -> filename
    /// Last known modification dates
    private var lastModDates: [String: Date] = [:]

    var tokenChanged: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    init(debounceInterval: TimeInterval = 2.0) {
        self.debounceInterval = debounceInterval
        guard let pw = getpwuid(getuid()) else {
            watchedDirectories = []
            watchedFilenames = [:]
            return
        }
        let home = String(cString: pw.pointee.pw_dir)
        let claudeDir = home + "/Library/Application Support/Claude"
        let dotClaudeDir = home + "/.claude"
        watchedDirectories = [claudeDir, dotClaudeDir]
        watchedFilenames = [
            claudeDir: "config.json",
            dotClaudeDir: ".credentials.json",
        ]
    }

    func startMonitoring() {
        stopMonitoring()
        for dir in watchedDirectories {
            let fd = open(dir, O_EVTONLY)
            guard fd >= 0 else { continue }
            fileDescriptors.append(fd)

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: .write,
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.handleDirectoryChange(dir)
            }
            source.setCancelHandler { close(fd) }
            sources.append(source)
            source.resume()

            // Record initial modification date
            if let filename = watchedFilenames[dir] {
                let path = dir + "/" + filename
                lastModDates[path] = modDate(path)
            }
        }
    }

    func stopMonitoring() {
        for source in sources { source.cancel() }
        sources.removeAll()
        fileDescriptors.removeAll()
    }

    private func handleDirectoryChange(_ dir: String) {
        guard let filename = watchedFilenames[dir] else { return }
        let path = dir + "/" + filename
        let newDate = modDate(path)
        guard let date = newDate, date != lastModDates[path] else { return }
        lastModDates[path] = date

        // Debounce
        let now = Date()
        guard now.timeIntervalSince(lastEmit) >= debounceInterval else { return }
        lastEmit = now
        subject.send(())
    }

    private func modDate(_ path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    deinit { stopMonitoring() }
}
```

- [ ] **Step 2: Verify build compiles**

Run: `xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Shared/Services/TokenFileMonitor.swift
git commit -m "feat: implement TokenFileMonitor with FSEvents directory watching"
```

---

## Task 5: Simplify MetricModels + APIClient + SharedFileService

**Files:**
- Modify: `Shared/Models/MetricModels.swift`
- Modify: `Shared/Services/APIClient.swift`
- Modify: `Shared/Services/SharedFileService.swift`
- Modify: `TokenEaterApp/TokenEaterApp.entitlements`

- [ ] **Step 1: Simplify AppErrorState in MetricModels.swift**

Replace the current `AppErrorState` enum with:
```swift
enum AppErrorState: Equatable {
    case none
    case tokenUnavailable
    case rateLimited
    case networkError
}
```

Remove the cases `tokenExpired`, `keychainLocked`, `needsReauth`, `apiUnavailable`, and `networkError(String)`.

- [ ] **Step 2: Remove keychainLocked from APIClient.swift**

In `APIClient.swift`, remove `APIError.keychainLocked` case if it exists. Keep `tokenExpired`, `rateLimited`, `httpError`, `noToken`.

- [ ] **Step 3: Remove oauthToken from SharedFileService.swift**

In the private `SharedData` struct, remove `var oauthToken: String?`. Remove the `oauthToken` getter/setter from the public interface and protocol. The `isConfigured` computed property should now check `cachedUsage != nil` instead of `oauthToken != nil`.

Also update `SharedFileServiceProtocol.swift` to remove `oauthToken`.

- [ ] **Step 4: Add Claude/ to entitlements**

In `TokenEaterApp/TokenEaterApp.entitlements`, add to the read-only array:
```xml
<string>/Library/Application Support/Claude/</string>
```

- [ ] **Step 5: Fix all compilation errors from the above changes**

Explicit mapping for `AppErrorState` migration:
- `.tokenExpired` → `.tokenUnavailable`
- `.keychainLocked` → `.tokenUnavailable`
- `.needsReauth` → `.tokenUnavailable`
- `.apiUnavailable` → `.rateLimited`
- `.networkError(String)` → `.networkError` (drop associated value)

Files that reference `AppErrorState` and must be updated:
- `Shared/Stores/UsageStore.swift` — will be rewritten in Task 7, for now just map old cases to new
- `TokenEaterApp/MenuBarView.swift` — has exhaustive switch on AppErrorState, update all cases
- `TokenEaterApp/OnboardingViewModel.swift` — references `.tokenExpired`, will be rewritten in Task 8, for now just map
- `TokenEaterApp/StatusBarController.swift` — may reference error states
- Any other views with `switch errorState` — find via grep and update

Files that reference `oauthToken`:
- `Shared/Services/SharedFileServiceProtocol.swift` — remove `oauthToken` property
- `Shared/Services/SharedFileService.swift` — remove from SharedData + accessors
- `TokenEaterTests/Mocks/MockSharedFileService.swift` — remove `oauthToken` property
- `Shared/Repositories/UsageRepository.swift` — remove `syncCredentialsFile`, `syncKeychainSilently`, references to `sharedFileService.oauthToken` → stub for now, rewrite in Task 6
- `TokenEaterApp/OnboardingViewModel.swift` — references to `sharedFileService.oauthToken` → stub, rewrite in Task 8

- [ ] **Step 6: Run tests to verify existing tests still pass**

Run: `xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -10`
Expected: Tests compile and run (some may fail due to mock changes — that's expected, will be fixed in later tasks)

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: simplify AppErrorState, remove oauthToken from SharedData, add Claude/ entitlement"
```

---

## Task 6: Rewrite UsageRepository

**Files:**
- Rewrite: `Shared/Repositories/UsageRepository.swift`
- Rewrite: `TokenEaterTests/UsageRepositoryTests.swift`
- Modify: `Shared/Repositories/UsageRepositoryProtocol.swift`
- Modify: `TokenEaterTests/Mocks/MockUsageRepository.swift`

- [ ] **Step 1: Rewrite UsageRepositoryProtocol**

```swift
// Shared/Repositories/UsageRepositoryProtocol.swift
import Foundation

protocol UsageRepositoryProtocol {
    func refreshUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse
    func fetchProfile(token: String, proxyConfig: ProxyConfig?) async throws -> ProfileResponse
    func testConnection(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse
}
```

- [ ] **Step 2: Rewrite UsageRepository**

```swift
// Shared/Repositories/UsageRepository.swift
import Foundation

final class UsageRepository: UsageRepositoryProtocol, @unchecked Sendable {

    private let apiClient: APIClientProtocol
    private let sharedFileService: SharedFileServiceProtocol

    init(apiClient: APIClientProtocol, sharedFileService: SharedFileServiceProtocol) {
        self.apiClient = apiClient
        self.sharedFileService = sharedFileService
    }

    func refreshUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        let usage = try await apiClient.fetchUsage(token: token, proxyConfig: proxyConfig)
        sharedFileService.updateAfterSync(
            usage: CachedUsage(usage: usage, fetchDate: Date()),
            syncDate: Date()
        )
        return usage
    }

    func fetchProfile(token: String, proxyConfig: ProxyConfig?) async throws -> ProfileResponse {
        try await apiClient.fetchProfile(token: token, proxyConfig: proxyConfig)
    }

    func testConnection(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        try await apiClient.fetchUsage(token: token, proxyConfig: proxyConfig)
    }
}
```

- [ ] **Step 3: Update MockUsageRepository**

Update mock to match new protocol (no more `syncCredentialsFile`, `syncKeychainSilently`, `isConfigured`, `currentToken` — just `refreshUsage(token:)`, `fetchProfile(token:)`, `testConnection(token:)`).

- [ ] **Step 4: Rewrite UsageRepositoryTests**

Write tests for the simple token-in → API → result-out flow. Test that `sharedFileService.updateAfterSync()` is called on success.

- [ ] **Step 5: Run tests**

Run: `xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -10`
Expected: UsageRepositoryTests pass

- [ ] **Step 6: Commit**

```bash
git add Shared/Repositories/ TokenEaterTests/UsageRepositoryTests.swift TokenEaterTests/Mocks/MockUsageRepository.swift
git commit -m "refactor: simplify UsageRepository to token-in API-out pattern"
```

---

## Task 7: Rewrite UsageStore

**Files:**
- Rewrite: `Shared/Stores/UsageStore.swift`
- Rewrite: `TokenEaterTests/UsageStoreTests.swift`

- [ ] **Step 1: Write key failing tests for new UsageStore**

Test the core behaviors:
- `refresh()` returns early if no token available (tokenProvider returns nil)
- `refresh()` returns early if interval not elapsed (speed-based throttle)
- `refresh()` calls API and updates UI on success
- `refresh()` retries once with fresh token on 401
- `refresh()` sets `.rateLimited` and switches to slow speed on 429
- `refresh()` sets `.networkError` on other errors
- `refreshIfStale()` only refreshes if lastUpdate > 120s

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement new UsageStore**

Key changes from current:
- Constructor takes `TokenProviderProtocol` instead of `UsageRepositoryProtocol` (old shape)
- `refresh()` uses the simplified pipeline from the spec (single interval check using `currentSpeed.rawValue`)
- `startAutoRefresh()` uses `currentSpeed` for delay instead of fixed 300s
- `RefreshSpeed` enum: `.fast(120)`, `.normal(600)`, `.slow(1200)`
- Remove `lastFailedToken`, `consecutive429Count`, `last429Date`, `retryAfterInterval`
- Add `currentSpeed`, `retryAfterDate`
- Add `refreshIfStale()` for wake handler
- Keep `updateUI(from:)`, `recalculatePacing()`, `refreshProfile()` (deferred)
- Call `notificationService.checkThresholds(...)` after each success (existing signature)

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Run ALL tests to check for regressions**

Run: full test suite
Expected: All tests pass (some old tests deleted, new tests pass)

- [ ] **Step 6: Commit**

```bash
git add Shared/Stores/UsageStore.swift TokenEaterTests/UsageStoreTests.swift
git commit -m "refactor: rewrite UsageStore with adaptive rate limiting and TokenProvider"
```

---

## Task 8: Update DI wiring + StatusBarController + Onboarding

**Files:**
- Modify: `TokenEaterApp/TokenEaterApp.swift`
- Modify: `TokenEaterApp/StatusBarController.swift`
- Rewrite: `TokenEaterApp/OnboardingViewModel.swift`
- Modify: `TokenEaterApp/OnboardingSteps/ConnectionStep.swift`
- Modify: `TokenEaterWidget/UsageWidgetView.swift`

- [ ] **Step 1: Update TokenEaterApp.swift DI**

Replace `KeychainService` creation with `TokenProvider` + `TokenFileMonitor`. Pass them to stores and controllers. Remove `KeychainService` and direct `CredentialsFileReader` usage from the app init.

- [ ] **Step 2: Update StatusBarController**

Add:
- Inject `TokenFileMonitor` and subscribe to `tokenChanged` → call `usageStore.refresh(force: true)`
- Start monitoring in `bootstrapRefresh()`
- Add wake handler: `NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification)` → call `usageStore.refreshIfStale()`

- [ ] **Step 3: Rewrite OnboardingViewModel**

New connection flow:
1. Check `config.json` exists (via `ClaudeConfigReader.readEncryptedToken() != nil`)
2. Call `tokenProvider.bootstrap()` — reads Keychain once
3. Get token via `tokenProvider.currentToken()`
4. Test API via `repository.testConnection(token:)`
5. On success → `sharedFileService.updateAfterSync()` → complete onboarding

- [ ] **Step 4: Update ConnectionStep UI**

Add explanation text before the "Authorize" button: "TokenEater needs one-time access to read Claude Code's encryption key. Click 'Always Allow' when macOS asks."

- [ ] **Step 5: Update UsageWidgetView stale message**

Replace the bare `wifi.slash` icon with a text like "Updated Xm ago" when stale.

- [ ] **Step 6: Delete old files**

Delete:
- `Shared/Services/KeychainService.swift`
- `Shared/Services/Protocols/KeychainServiceProtocol.swift`
- `TokenEaterTests/Mocks/MockKeychainService.swift`
- `TokenEaterTests/CredentialsFileReaderTests.swift`
- `TokenEaterTests/KeychainServiceTests.swift` (if exists)

- [ ] **Step 7: Run ALL tests**

Run: full test suite
Expected: All tests pass

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor: wire TokenProvider into app, rewrite onboarding, add wake handler"
```

---

## Task 9: Final verification + cleanup

- [ ] **Step 1: Run full test suite one last time**

Run: `xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -20`
Expected: All tests pass, zero failures

- [ ] **Step 2: Build Release with Xcode 16.4**

Run: `export DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer && xcodegen generate && DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject 2>/dev/null | grep -oE 'OU=[A-Z0-9]{10}' | head -1 | cut -d= -f2) && plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' TokenEaterWidget/Info.plist 2>/dev/null || true && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Grep for leftover references to removed code**

Search for: `KeychainService`, `keychainService`, `readOAuthToken`, `syncKeychainToken`, `keychainLocked`, `needsReauth`, `apiUnavailable` in Swift files.
Expected: Zero hits (except in test fixtures or comments)

- [ ] **Step 4: Commit any cleanup**

---

## Task 10: Mega nuke + iso-prod install

This task uses the `/nuke-isoprod` skill to build via CI, download DMG, mega nuke, and install.

- [ ] **Step 1: Push branch and trigger test-build CI**

```bash
git push origin feat/104-bug-widget-still-doesn-t-updat
gh workflow run test-build.yml -f branch=feat/104-bug-widget-still-doesn-t-updat
```

- [ ] **Step 2: Wait for CI to complete and download DMG**

- [ ] **Step 3: Mega nuke**

```bash
killall TokenEater NotificationCenter chronod cfprefsd 2>/dev/null; sleep 1
defaults delete com.tokeneater.app 2>/dev/null
defaults delete com.claudeusagewidget.app 2>/dev/null
rm -f ~/Library/Preferences/com.tokeneater.app.plist ~/Library/Preferences/com.claudeusagewidget.app.plist
for c in com.tokeneater.app com.tokeneater.app.widget com.claudeusagewidget.app com.claudeusagewidget.app.widget; do
    d="$HOME/Library/Containers/$c/Data"; [ -d "$d" ] && rm -rf "$d/Library/Preferences/"* "$d/Library/Caches/"* "$d/Library/Application Support/"* "$d/tmp/"* 2>/dev/null
done
rm -rf ~/Library/Application\ Support/com.tokeneater.shared ~/Library/Caches/com.tokeneater.app
rm -rf /Applications/TokenEater.app
# Also clear the cached decryption key from TokenEater's Keychain
security delete-generic-password -s "TokenEater" -a "decryption-key" 2>/dev/null
```

- [ ] **Step 4: Install from DMG and launch**

- [ ] **Step 5: Verify onboarding**
- One Keychain modal appears at connection step (for "Claude Safe Storage")
- Click "Always Allow"
- Connection succeeds, widget data appears

- [ ] **Step 6: Verify steady-state operation**
- Menu bar shows correct usage values
- Widget updates after each refresh
- No Keychain modals
- Sleep Mac for 30 seconds → wake → widget updates within 2 minutes
- Check Console.app for any TokenEater errors

- [ ] **Step 7: Verify edge cases**
- Force-quit Claude Code → relaunch → TokenEater recovers automatically
- Open another Claude Code session → verify agent watchers still work
