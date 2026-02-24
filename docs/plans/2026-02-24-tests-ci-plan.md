# Tests & CI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add unit tests for the core business logic and a GitHub Actions CI pipeline that builds and tests on every PR.

**Architecture:** Swift Testing framework (Xcode 16+) with protocol-based mocks. No third-party dependencies. CI on GitHub Actions `macos-15` runner.

**Tech Stack:** Swift Testing, XcodeGen, GitHub Actions

---

## Task 1: Add test target to project.yml

**Files:**
- Modify: `project.yml`

**Step 1: Add TokenEaterTests target**

Add a test target in `project.yml`:

```yaml
  TokenEaterTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: TokenEaterTests
    dependencies:
      - target: TokenEaterApp
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.tokeneater.tests
        CODE_SIGN_IDENTITY: ""
        CODE_SIGNING_REQUIRED: "NO"
        TEST_HOST: ""
        BUNDLE_LOADER: ""
```

Note: `TEST_HOST` and `BUNDLE_LOADER` are empty because we test the Shared/ code directly (linked into the test target), not the app host process.

**Step 2: Create test directory + placeholder**

Create `TokenEaterTests/SmokeTest.swift`:

```swift
import Testing

@Suite("Smoke")
struct SmokeTests {
    @Test("project compiles and test target runs")
    func smokeTest() {
        #expect(true)
    }
}
```

**Step 3: Verify**

```bash
xcodegen generate
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -10
```

Expected: `** TEST SUCCEEDED **`

**Step 4: Commit**

```bash
git add project.yml TokenEaterTests/
git commit -m "test: add test target and smoke test"
```

---

## Task 2: Add mock services

**Files:**
- Create: `TokenEaterTests/Mocks/MockAPIClient.swift`
- Create: `TokenEaterTests/Mocks/MockKeychainService.swift`
- Create: `TokenEaterTests/Mocks/MockSharedFileService.swift`
- Create: `TokenEaterTests/Mocks/MockNotificationService.swift`

Create one mock per protocol. Each mock records calls and returns configurable results.

**Step 1: MockAPIClient**

```swift
import Foundation
@testable import TokenEaterApp

final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
    var stubbedUsage: UsageResponse?
    var stubbedError: Error?
    var fetchCallCount = 0

    func fetchUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        fetchCallCount += 1
        if let error = stubbedError { throw error }
        return stubbedUsage ?? .empty
    }
}
```

**Step 2: MockKeychainService**

```swift
@testable import TokenEaterApp

final class MockKeychainService: KeychainServiceProtocol {
    var storedToken: String?

    func readToken() -> String? { storedToken }
    func tokenExists() -> Bool { storedToken != nil }
}
```

**Step 3: MockSharedFileService**

```swift
@testable import TokenEaterApp

final class MockSharedFileService: SharedFileServiceProtocol {
    var savedUsage: CachedUsage?
    var savedTheme: ThemeColors?
    var savedThresholds: UsageThresholds?
    var writeCallCount = 0

    var cachedUsage: CachedUsage? { savedUsage }
    var theme: ThemeColors { savedTheme ?? .default }
    var thresholds: UsageThresholds { savedThresholds ?? .default }

    func writeUsage(_ usage: UsageResponse) {
        writeCallCount += 1
        savedUsage = CachedUsage(usage: usage, fetchDate: Date())
    }

    func updateTheme(_ theme: ThemeColors, thresholds: UsageThresholds) {
        savedTheme = theme
        savedThresholds = thresholds
    }
}
```

**Step 4: MockNotificationService**

```swift
@testable import TokenEaterApp

final class MockNotificationService: NotificationServiceProtocol {
    var permissionRequested = false
    var lastThresholdCheck: (fiveHour: Int, sevenDay: Int, sonnet: Int)?
    var stubbedAuthStatus: UNAuthorizationStatus = .notDetermined

    func requestPermission() { permissionRequested = true }

    func checkThresholds(fiveHour: Int, sevenDay: Int, sonnet: Int, thresholds: UsageThresholds) {
        lastThresholdCheck = (fiveHour, sevenDay, sonnet)
    }

    func checkAuthorizationStatus() async -> UNAuthorizationStatus { stubbedAuthStatus }
    func sendTest() {}
    func setupDelegate() {}
}
```

**Step 5: Verify build**

```bash
xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

**Step 6: Commit**

```bash
git add TokenEaterTests/Mocks/
git commit -m "test: add mock services for all protocols"
```

---

## Task 3: Test PacingCalculator (pure function)

**Files:**
- Create: `TokenEaterTests/PacingCalculatorTests.swift`

**Step 1: Write tests**

```swift
import Testing
@testable import TokenEaterApp

@Suite("PacingCalculator")
struct PacingCalculatorTests {

    @Test("returns nil when sevenDay bucket is missing")
    func nilWhenNoSevenDay() {
        let usage = UsageResponse(fiveHour: nil, sevenDay: nil, sevenDaySonnet: nil)
        #expect(PacingCalculator.calculate(from: usage) == nil)
    }

    @Test("on track when utilization matches elapsed time", arguments: [
        (utilization: 50.0, elapsed: 50.0, PacingZone.onTrack),
        (utilization: 10.0, elapsed: 80.0, PacingZone.underPacing),
        (utilization: 90.0, elapsed: 20.0, PacingZone.overPacing),
    ])
    func pacingZones(utilization: Double, elapsed: Double, expected: PacingZone) {
        // Build a UsageResponse with sevenDay bucket that produces the expected pacing
        // The exact construction depends on how PacingCalculator reads the data
    }

    @Test("delta is positive when over-pacing")
    func deltaPositive() {
        // Construct usage where utilization > elapsed proportion
        // #expect(result.delta > 0)
    }

    @Test("delta is negative when under-pacing")
    func deltaNegative() {
        // Construct usage where utilization < elapsed proportion
        // #expect(result.delta < 0)
    }
}
```

Note: The exact test data construction depends on `UsageResponse.Bucket` fields. The implementer should read `PacingCalculator.swift` and `PacingModels.swift` to build accurate test fixtures.

**Step 2: Run tests**

```bash
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | tail -10
```

Expected: `** TEST SUCCEEDED **`

**Step 3: Commit**

```bash
git add TokenEaterTests/PacingCalculatorTests.swift
git commit -m "test: add PacingCalculator unit tests"
```

---

## Task 4: Test UsageRepository

**Files:**
- Create: `TokenEaterTests/UsageRepositoryTests.swift`

**Step 1: Write tests**

```swift
import Testing
@testable import TokenEaterApp

@Suite("UsageRepository")
struct UsageRepositoryTests {

    @Test("refreshUsage fetches from API and writes to shared file")
    func refreshWritesToFile() async throws {
        let api = MockAPIClient()
        let keychain = MockKeychainService()
        let sharedFile = MockSharedFileService()
        keychain.storedToken = "test-token"
        api.stubbedUsage = UsageResponse.fixture()

        let repo = UsageRepository(apiClient: api, keychainService: keychain, sharedFileService: sharedFile)
        repo.syncKeychainToken()
        let usage = try await repo.refreshUsage(proxyConfig: nil)

        #expect(api.fetchCallCount == 1)
        #expect(sharedFile.writeCallCount == 1)
        #expect(usage.fiveHour?.utilization == api.stubbedUsage?.fiveHour?.utilization)
    }

    @Test("isConfigured returns false when no token")
    func notConfiguredWithoutToken() {
        let repo = UsageRepository(
            apiClient: MockAPIClient(),
            keychainService: MockKeychainService(),
            sharedFileService: MockSharedFileService()
        )
        repo.syncKeychainToken()
        #expect(!repo.isConfigured)
    }

    @Test("isConfigured returns true when token exists")
    func configuredWithToken() {
        let keychain = MockKeychainService()
        keychain.storedToken = "token"
        let repo = UsageRepository(
            apiClient: MockAPIClient(),
            keychainService: keychain,
            sharedFileService: MockSharedFileService()
        )
        repo.syncKeychainToken()
        #expect(repo.isConfigured)
    }

    @Test("cachedUsage returns what shared file has")
    func cachedUsageDelegates() {
        let sharedFile = MockSharedFileService()
        let repo = UsageRepository(
            apiClient: MockAPIClient(),
            keychainService: MockKeychainService(),
            sharedFileService: sharedFile
        )
        #expect(repo.cachedUsage == nil)
    }
}
```

**Step 2: Add test fixture helper**

Create `TokenEaterTests/Fixtures/UsageResponse+Fixture.swift`:

```swift
@testable import TokenEaterApp

extension UsageResponse {
    static func fixture(
        fiveHourUtil: Double = 42,
        sevenDayUtil: Double = 65,
        sonnetUtil: Double = 30
    ) -> UsageResponse {
        // Build a valid UsageResponse with the given utilization values
        // Implementer: read UsageModels.swift to construct this correctly
    }
}
```

**Step 3: Run, verify, commit**

```bash
xcodebuild test ... | tail -10
git add TokenEaterTests/
git commit -m "test: add UsageRepository unit tests"
```

---

## Task 5: Test UsageStore

**Files:**
- Create: `TokenEaterTests/UsageStoreTests.swift`

**Step 1: Write tests**

```swift
import Testing
@testable import TokenEaterApp

@Suite("UsageStore")
struct UsageStoreTests {

    @Test("refresh updates percentages from API response")
    @MainActor
    func refreshUpdatesState() async {
        let repo = MockUsageRepository()
        repo.stubbedUsage = UsageResponse.fixture(fiveHourUtil: 42, sevenDayUtil: 65, sonnetUtil: 30)
        repo.isConfiguredValue = true

        let store = UsageStore(repository: repo, notificationService: MockNotificationService())
        await store.refresh()

        #expect(store.fiveHourPct == 42)
        #expect(store.sevenDayPct == 65)
        #expect(store.sonnetPct == 30)
        #expect(!store.hasError)
    }

    @Test("refresh sets hasError on failure")
    @MainActor
    func refreshSetsError() async {
        let repo = MockUsageRepository()
        repo.isConfiguredValue = true
        repo.shouldFail = true

        let store = UsageStore(repository: repo, notificationService: MockNotificationService())
        await store.refresh()

        #expect(store.hasError)
    }

    @Test("refresh checks notification thresholds")
    @MainActor
    func refreshChecksThresholds() async {
        let repo = MockUsageRepository()
        repo.stubbedUsage = UsageResponse.fixture(fiveHourUtil: 90, sevenDayUtil: 50, sonnetUtil: 30)
        repo.isConfiguredValue = true
        let notif = MockNotificationService()

        let store = UsageStore(repository: repo, notificationService: notif)
        await store.refresh()

        #expect(notif.lastThresholdCheck?.fiveHour == 90)
    }

    @Test("loadCached reads from repository cache")
    @MainActor
    func loadCachedReadsRepo() {
        let repo = MockUsageRepository()
        repo.cachedValue = CachedUsage(usage: .fixture(), fetchDate: Date())

        let store = UsageStore(repository: repo, notificationService: MockNotificationService())
        store.loadCached()

        #expect(store.fiveHourPct == 42)
        #expect(store.lastUpdate != nil)
    }
}
```

Note: This task requires creating `MockUsageRepository` implementing `UsageRepositoryProtocol`.

**Step 2: Create MockUsageRepository**

Create `TokenEaterTests/Mocks/MockUsageRepository.swift`.

**Step 3: Run, verify, commit**

```bash
git add TokenEaterTests/
git commit -m "test: add UsageStore unit tests"
```

---

## Task 6: Test ThemeStore

**Files:**
- Create: `TokenEaterTests/ThemeStoreTests.swift`

**Step 1: Write tests**

```swift
import Testing
@testable import TokenEaterApp

@Suite("ThemeStore")
struct ThemeStoreTests {

    @Test("default preset returns default colors")
    @MainActor
    func defaultPreset() {
        let store = ThemeStore(sharedFileService: MockSharedFileService())
        #expect(store.selectedPreset == "default")
        #expect(store.current == ThemeColors.default)
    }

    @Test("changing preset triggers sync to shared file")
    @MainActor
    func presetChangeTriggersSync() async throws {
        let sharedFile = MockSharedFileService()
        let store = ThemeStore(sharedFileService: sharedFile)
        store.selectedPreset = "ocean"

        // Wait for debounce (0.3s)
        try await Task.sleep(for: .milliseconds(500))

        #expect(sharedFile.savedTheme != nil)
    }

    @Test("resetToDefaults restores all values")
    @MainActor
    func resetToDefaults() {
        let store = ThemeStore(sharedFileService: MockSharedFileService())
        store.warningThreshold = 99
        store.criticalThreshold = 100
        store.selectedPreset = "ocean"

        store.resetToDefaults()

        #expect(store.warningThreshold == 60)
        #expect(store.criticalThreshold == 85)
        #expect(store.selectedPreset == "default")
    }

    @Test("thresholds returns correct struct")
    @MainActor
    func thresholdsStruct() {
        let store = ThemeStore(sharedFileService: MockSharedFileService())
        store.warningThreshold = 70
        store.criticalThreshold = 90

        #expect(store.thresholds.warningPercent == 70)
        #expect(store.thresholds.criticalPercent == 90)
    }
}
```

**Step 2: Run, verify, commit**

```bash
git add TokenEaterTests/ThemeStoreTests.swift
git commit -m "test: add ThemeStore unit tests"
```

---

## Task 7: Test SettingsStore

**Files:**
- Create: `TokenEaterTests/SettingsStoreTests.swift`

**Step 1: Write tests**

Test with isolated UserDefaults (suiteName) to avoid polluting real prefs.

```swift
import Testing
@testable import TokenEaterApp

@Suite("SettingsStore")
struct SettingsStoreTests {

    @Test("default values are correct")
    @MainActor
    func defaults() {
        let store = SettingsStore()
        #expect(store.showMenuBar == true)
        #expect(store.hasCompletedOnboarding == false)
        #expect(store.refreshInterval == 300)
    }

    @Test("proxy config returns nil when not enabled")
    @MainActor
    func proxyDisabledReturnsNil() {
        let store = SettingsStore()
        store.proxyEnabled = false
        #expect(store.proxyConfig == nil)
    }

    @Test("proxy config returns value when enabled with host and port")
    @MainActor
    func proxyEnabledReturnsConfig() {
        let store = SettingsStore()
        store.proxyEnabled = true
        store.proxyHost = "localhost"
        store.proxyPort = "8080"

        let config = store.proxyConfig
        #expect(config != nil)
        #expect(config?.host == "localhost")
        #expect(config?.port == 8080)
    }
}
```

**Step 2: Run, verify, commit**

```bash
git add TokenEaterTests/SettingsStoreTests.swift
git commit -m "test: add SettingsStore unit tests"
```

---

## Task 8: GitHub Actions CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Step 1: Write CI workflow**

```yaml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-and-test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.2.app

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate project
        run: |
          xcodegen generate
          plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' TokenEaterWidget/Info.plist 2>/dev/null || true

      - name: Build
        run: |
          xcodebuild -project TokenEater.xcodeproj \
            -scheme TokenEaterApp \
            -configuration Release \
            -derivedDataPath build \
            -destination 'platform=macOS' \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            build

      - name: Test
        run: |
          xcodebuild -project TokenEater.xcodeproj \
            -scheme TokenEaterTests \
            -configuration Debug \
            -derivedDataPath build \
            -destination 'platform=macOS' \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            test
```

**Step 2: Verify YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"
```

**Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add build and test workflow"
```

---

## Task 9: Verify full test suite

**Step 1: Run all tests locally**

```bash
xcodegen generate
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test 2>&1 | grep -E "(Test Suite|Test Case|Executed|SUCCEEDED|FAILED)"
```

Expected: All tests pass, `** TEST SUCCEEDED **`

**Step 2: Commit any final fixes, verify clean build**

```bash
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`
