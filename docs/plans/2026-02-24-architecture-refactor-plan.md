# TokenEater Architecture Refactor — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor TokenEater to MV + Repository pattern with @Observable, rename all "ClaudeUsage" → "TokenEater", and add shared file path migration.

**Architecture:** Layered architecture (Models → Services → Repository → Stores) with protocol-based services for testability, @Observable stores injected via SwiftUI @Environment, and a Strategy pattern for themes. See `docs/plans/2026-02-24-architecture-refactor-design.md` for full design.

**Tech Stack:** Swift 5.9+, SwiftUI, WidgetKit, macOS 14+, XcodeGen

**Important context:**
- No test target exists — verification = `xcodegen generate && xcodebuild build`
- `project.yml` uses `path: Shared` for sources — XcodeGen auto-discovers all .swift files in subdirectories
- Both app and widget targets include `Shared/` — all new Shared/ files are available to both
- Old and new files can coexist during transition (different type names)
- The `Notification.Name.displaySettingsDidChange` pattern will be removed (replaced by @Observable reactivity)

---

### Task 1: Rename folders, types, bundle IDs, and project config

**Files:**
- Rename: `ClaudeUsageApp/` → `TokenEaterApp/`
- Rename: `ClaudeUsageWidget/` → `TokenEaterWidget/`
- Rename: `TokenEaterApp/ClaudeUsageApp.swift` → `TokenEaterApp/TokenEaterApp.swift`
- Rename: `TokenEaterApp/ClaudeUsageApp.entitlements` → `TokenEaterApp/TokenEaterApp.entitlements`
- Rename: `TokenEaterWidget/ClaudeUsageWidget.entitlements` → `TokenEaterWidget/TokenEaterWidget.entitlements`
- Modify: `project.yml`
- Modify: `TokenEaterApp/TokenEaterApp.swift` (type name)
- Modify: `TokenEaterWidget/ClaudeUsageWidget.swift` (type names + widget kind)
- Modify: `TokenEaterApp/TokenEaterApp.entitlements` (add both old + new paths for migration)
- Modify: `TokenEaterWidget/TokenEaterWidget.entitlements` (new path only)
- Modify: `.github/workflows/release.yml` (references to old paths)
- Modify: `build.sh` (references to old project name)

**Step 1: Rename folders with git mv**

```bash
cd /Users/athevon/projects/TokenEater-refac-mv-pattern
git mv ClaudeUsageApp TokenEaterApp
git mv ClaudeUsageWidget TokenEaterWidget
```

**Step 2: Rename files within renamed folders**

```bash
git mv TokenEaterApp/ClaudeUsageApp.swift TokenEaterApp/TokenEaterApp.swift
git mv TokenEaterApp/ClaudeUsageApp.entitlements TokenEaterApp/TokenEaterApp.entitlements
git mv TokenEaterWidget/ClaudeUsageWidget.entitlements TokenEaterWidget/TokenEaterWidget.entitlements
```

**Step 3: Update project.yml**

Replace entire content with:

```yaml
name: TokenEater
options:
  bundleIdPrefix: com.tokeneater
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "15.0"
  groupSortPosition: top
  defaultLocalization: en

settings:
  base:
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    CODE_SIGN_STYLE: Automatic
    MARKETING_VERSION: "3.3.1"
    CURRENT_PROJECT_VERSION: "1"
    ARCHS: "arm64 x86_64"

targets:
  TokenEaterApp:
    type: application
    platform: macOS
    sources:
      - path: TokenEaterApp
      - path: Shared
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.tokeneater.app
        PRODUCT_NAME: TokenEater
        CODE_SIGN_ENTITLEMENTS: TokenEaterApp/TokenEaterApp.entitlements
        INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.utilities
        INFOPLIST_KEY_CFBundleDisplayName: TokenEater
        INFOPLIST_KEY_LSUIElement: YES
        GENERATE_INFOPLIST_FILE: YES
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    dependencies:
      - target: TokenEaterWidgetExtension
        embed: true

  TokenEaterWidgetExtension:
    type: app-extension
    platform: macOS
    sources:
      - path: TokenEaterWidget
        excludes:
          - Info.plist
      - path: Shared
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.tokeneater.app.widget
        PRODUCT_NAME: TokenEaterWidgetExtension
        CODE_SIGN_ENTITLEMENTS: TokenEaterWidget/TokenEaterWidget.entitlements
        LD_RUNPATH_SEARCH_PATHS: "$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks"
    info:
      path: TokenEaterWidget/Info.plist

schemes:
  TokenEaterApp:
    build:
      targets:
        TokenEaterApp: all
        TokenEaterWidgetExtension: all
    run:
      config: Debug
    archive:
      config: Release
```

**Step 4: Update type names in Swift files**

In `TokenEaterApp/TokenEaterApp.swift`, rename the struct:
```swift
// Change: struct ClaudeUsageApp: App
// To:
struct TokenEaterApp: App
```

In `TokenEaterWidget/ClaudeUsageWidget.swift`, rename types and widget kind:
```swift
struct TokenEaterWidget: Widget {
    let kind: String = "TokenEaterWidget"
    // ... rest stays the same
}

// PacingWidget stays as-is (no "ClaudeUsage" prefix)

@main
struct TokenEaterWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenEaterWidget()
        PacingWidget()
    }
}
```

**Step 5: Update entitlements — app gets both paths for migration**

`TokenEaterApp/TokenEaterApp.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key>
    <array>
        <string>/Library/Application Support/com.tokeneater.shared/</string>
        <string>/Library/Application Support/com.claudeusagewidget.shared/</string>
    </array>
</dict>
</plist>
```

`TokenEaterWidget/TokenEaterWidget.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key>
    <array>
        <string>/Library/Application Support/com.tokeneater.shared/</string>
    </array>
</dict>
</plist>
```

**Step 6: Update CI workflow and build.sh**

In `.github/workflows/release.yml`, update references:
- `ClaudeUsageWidget/Info.plist` → `TokenEaterWidget/Info.plist`
- `ClaudeUsageWidget.xcodeproj` → `TokenEater.xcodeproj`
- `-scheme ClaudeUsageApp` → `-scheme TokenEaterApp`

In `build.sh`, update:
- `ClaudeUsageWidget.xcodeproj` → `TokenEater.xcodeproj`
- `-scheme ClaudeUsageApp` → `-scheme TokenEaterApp`
- Echo text "Claude Usage Widget" → "TokenEater"

**Step 7: Update SharedContainer directory name constant**

In `Shared/SharedContainer.swift`, update the directory name so the app still builds and runs correctly during the transition. **For now**, keep the old name — we'll change this when we create SharedFileService with migration logic in Task 4.

No change needed here yet.

**Step 8: Verify build**

```bash
xcodegen generate && \
plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' TokenEaterWidget/Info.plist 2>/dev/null; \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 9: Commit**

```bash
git add -A && git commit -m "rename: ClaudeUsage → TokenEater (folders, types, bundle IDs, entitlements, CI)"
```

---

### Task 2: Create folder structure and extract Models

**Files:**
- Create: `Shared/Models/` directory
- Move: `Shared/UsageModels.swift` → `Shared/Models/UsageModels.swift` (remove ProxyConfig from it)
- Create: `Shared/Models/ProxyConfig.swift`
- Create: `Shared/Models/PacingModels.swift` (extract from PacingCalculator.swift)
- Create: `Shared/Models/ThemeModels.swift` (extract from ThemeColors.swift)
- Create: `Shared/Services/`, `Shared/Services/Protocols/`, `Shared/Repositories/`, `Shared/Stores/`, `Shared/Helpers/`
- Move: `Shared/PacingCalculator.swift` → `Shared/Helpers/PacingCalculator.swift` (remove model types)
- Move: `Shared/Extensions.swift` → `Shared/Extensions/Extensions.swift`

**Step 1: Create directory structure**

```bash
mkdir -p Shared/Models Shared/Services/Protocols Shared/Repositories Shared/Stores Shared/Helpers Shared/Extensions
```

**Step 2: Extract ProxyConfig from UsageModels.swift**

Remove ProxyConfig from `Shared/UsageModels.swift` and create `Shared/Models/ProxyConfig.swift`:

```swift
import Foundation

struct ProxyConfig {
    var enabled: Bool
    var host: String
    var port: Int

    init(enabled: Bool = false, host: String = "127.0.0.1", port: Int = 1080) {
        self.enabled = enabled
        self.host = host
        self.port = port
    }
}
```

**Step 3: Move UsageModels.swift to Models/ (without ProxyConfig)**

```bash
git mv Shared/UsageModels.swift Shared/Models/UsageModels.swift
```

Then edit to remove the ProxyConfig struct from the file.

**Step 4: Extract PacingModels.swift**

Create `Shared/Models/PacingModels.swift` with the model types currently at the top of PacingCalculator.swift:

```swift
import Foundation

enum PacingZone: String {
    case chill
    case onTrack
    case hot
}

struct PacingResult {
    let delta: Double
    let expectedUsage: Double
    let actualUsage: Double
    let zone: PacingZone
    let message: String
    let resetDate: Date?
}
```

Then move PacingCalculator.swift to Helpers/ and remove the model types from it:

```bash
git mv Shared/PacingCalculator.swift Shared/Helpers/PacingCalculator.swift
```

Edit `Shared/Helpers/PacingCalculator.swift` to remove `PacingZone` enum and `PacingResult` struct (they're now in Models/).

**Step 5: Extract ThemeModels.swift**

Create `Shared/Models/ThemeModels.swift` by moving ThemeColors and UsageThresholds from `Shared/ThemeColors.swift`:

```bash
git mv Shared/ThemeColors.swift Shared/Models/ThemeModels.swift
```

The file already contains exactly what we need (ThemeColors + UsageThresholds). No code changes needed.

**Step 6: Move Extensions.swift**

```bash
git mv Shared/Extensions.swift Shared/Extensions/Extensions.swift
```

**Step 7: Verify build**

```bash
xcodegen generate && \
plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' TokenEaterWidget/Info.plist 2>/dev/null; \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 8: Commit**

```bash
git add -A && git commit -m "refactor: reorganize Shared/ into Models/, Helpers/, Extensions/"
```

---

### Task 3: Create Service Protocols

**Files:**
- Create: `Shared/Services/Protocols/APIClientProtocol.swift`
- Create: `Shared/Services/Protocols/KeychainServiceProtocol.swift`
- Create: `Shared/Services/Protocols/SharedFileServiceProtocol.swift`
- Create: `Shared/Services/Protocols/NotificationServiceProtocol.swift`

**Step 1: Create APIClientProtocol**

`Shared/Services/Protocols/APIClientProtocol.swift`:

```swift
import Foundation

enum APIError: LocalizedError {
    case noToken
    case invalidResponse
    case tokenExpired
    case unsupportedPlan
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .noToken:
            return String(localized: "error.notoken")
        case .invalidResponse:
            return String(localized: "error.invalidresponse")
        case .tokenExpired:
            return String(localized: "error.tokenexpired")
        case .unsupportedPlan:
            return String(localized: "error.unsupportedplan")
        case .httpError(let code):
            return String(format: String(localized: "error.http"), code)
        }
    }
}

struct ConnectionTestResult {
    let success: Bool
    let message: String
}

protocol APIClientProtocol: Sendable {
    func fetchUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse
    func testConnection(token: String, proxyConfig: ProxyConfig?) async -> ConnectionTestResult
}
```

**Step 2: Create KeychainServiceProtocol**

`Shared/Services/Protocols/KeychainServiceProtocol.swift`:

```swift
import Foundation

protocol KeychainServiceProtocol: Sendable {
    func readOAuthToken() -> String?
    func tokenExists() -> Bool
}
```

**Step 3: Create SharedFileServiceProtocol**

`Shared/Services/Protocols/SharedFileServiceProtocol.swift`:

```swift
import Foundation

protocol SharedFileServiceProtocol: Sendable {
    var isConfigured: Bool { get }
    var oauthToken: String? { get set }
    var cachedUsage: CachedUsage? { get }
    var lastSyncDate: Date? { get }
    var theme: ThemeColors { get }
    var thresholds: UsageThresholds { get }

    func updateAfterSync(usage: CachedUsage, syncDate: Date)
    func updateTheme(_ theme: ThemeColors, thresholds: UsageThresholds)
    func clear()
}
```

**Step 4: Create NotificationServiceProtocol**

`Shared/Services/Protocols/NotificationServiceProtocol.swift`:

```swift
import Foundation
import UserNotifications

protocol NotificationServiceProtocol {
    func setupDelegate()
    func requestPermission()
    func checkAuthorizationStatus() async -> UNAuthorizationStatus
    func sendTest()
    func checkThresholds(fiveHour: Int, sevenDay: Int, sonnet: Int, thresholds: UsageThresholds)
}
```

**Step 5: Verify build**

```bash
xcodegen generate && \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED (protocols are just declarations, no conflicts with existing code)

**Step 6: Commit**

```bash
git add -A && git commit -m "refactor: add service protocols (APIClient, Keychain, SharedFile, Notification)"
```

---

### Task 4: Create Service Implementations

Old files (`ClaudeAPIClient.swift`, `KeychainOAuthReader.swift`, `SharedContainer.swift`, `UsageNotificationManager.swift`) stay during this task — they're still used by existing views. They'll be removed in Task 7.

**Files:**
- Create: `Shared/Services/APIClient.swift`
- Create: `Shared/Services/KeychainService.swift`
- Create: `Shared/Services/SharedFileService.swift` (with migration)
- Create: `Shared/Services/NotificationService.swift`

**Step 1: Create KeychainService**

`Shared/Services/KeychainService.swift`:

```swift
import Foundation
import Security

final class KeychainService: KeychainServiceProtocol, @unchecked Sendable {
    func readOAuthToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else {
            return nil
        }

        return token
    }

    func tokenExists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
    }
}
```

**Step 2: Create SharedFileService (with migration)**

`Shared/Services/SharedFileService.swift`:

```swift
import Foundation

final class SharedFileService: SharedFileServiceProtocol, @unchecked Sendable {
    private let newDirectoryName = "com.tokeneater.shared"
    private let oldDirectoryName = "com.claudeusagewidget.shared"
    private let fileName = "shared.json"

    private var realHomeDirectory: String {
        guard let pw = getpwuid(getuid()) else { return NSHomeDirectory() }
        return String(cString: pw.pointee.pw_dir)
    }

    private var sharedFileURL: URL {
        URL(fileURLWithPath: realHomeDirectory)
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(newDirectoryName)
            .appendingPathComponent(fileName)
    }

    private var oldSharedFileURL: URL {
        URL(fileURLWithPath: realHomeDirectory)
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(oldDirectoryName)
            .appendingPathComponent(fileName)
    }

    init() {
        migrateIfNeeded()
    }

    /// One-shot migration: copy data from old path to new path, then delete old directory.
    /// Kept forever — costs nothing, protects late updaters on Homebrew.
    private func migrateIfNeeded() {
        let fm = FileManager.default
        let oldDir = oldSharedFileURL.deletingLastPathComponent()
        let newDir = sharedFileURL.deletingLastPathComponent()

        guard fm.fileExists(atPath: oldSharedFileURL.path) else { return }

        // Ensure new directory exists
        try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)

        // Copy old file to new location (don't overwrite if new already exists)
        if !fm.fileExists(atPath: sharedFileURL.path) {
            try? fm.copyItem(at: oldSharedFileURL, to: sharedFileURL)
        }

        // Remove old directory
        try? fm.removeItem(at: oldDir)
    }

    // MARK: - SharedData (same format as before for backward compat)

    private struct SharedData: Codable {
        var oauthToken: String?
        var cachedUsage: CachedUsage?
        var lastSyncDate: Date?
        var theme: ThemeColors?
        var thresholds: UsageThresholds?
    }

    private func load() -> SharedData {
        guard let data = try? Data(contentsOf: sharedFileURL) else {
            return SharedData()
        }
        return (try? JSONDecoder().decode(SharedData.self, from: data)) ?? SharedData()
    }

    private func save(_ shared: SharedData) {
        let dir = sharedFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(shared).write(to: sharedFileURL, options: .atomic)
    }

    // MARK: - SharedFileServiceProtocol

    var isConfigured: Bool { oauthToken != nil }

    var oauthToken: String? {
        get { load().oauthToken }
        set {
            var data = load()
            data.oauthToken = newValue
            save(data)
        }
    }

    var cachedUsage: CachedUsage? {
        load().cachedUsage
    }

    var lastSyncDate: Date? {
        load().lastSyncDate
    }

    var theme: ThemeColors {
        load().theme ?? .default
    }

    var thresholds: UsageThresholds {
        load().thresholds ?? .default
    }

    func updateAfterSync(usage: CachedUsage, syncDate: Date) {
        var data = load()
        data.cachedUsage = usage
        data.lastSyncDate = syncDate
        save(data)
    }

    func updateTheme(_ theme: ThemeColors, thresholds: UsageThresholds) {
        var data = load()
        data.theme = theme
        data.thresholds = thresholds
        save(data)
    }

    func clear() {
        save(SharedData())
    }
}
```

**Step 3: Create APIClient**

`Shared/Services/APIClient.swift`:

```swift
import Foundation

final class APIClient: APIClientProtocol, @unchecked Sendable {
    private let oauthURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private func session(proxyConfig: ProxyConfig?) -> URLSession {
        guard let proxy = proxyConfig, proxy.enabled else { return .shared }
        let c = URLSessionConfiguration.default
        c.connectionProxyDictionary = [
            kCFNetworkProxiesSOCKSEnable as String: true,
            kCFNetworkProxiesSOCKSProxy as String: proxy.host,
            kCFNetworkProxiesSOCKSPort as String: proxy.port,
        ]
        return URLSession(configuration: c)
    }

    private func makeRequest(token: String) -> URLRequest {
        var request = URLRequest(url: oauthURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        return request
    }

    func fetchUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        let request = makeRequest(token: token)
        let (data, response) = try await session(proxyConfig: proxyConfig).data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(UsageResponse.self, from: data)
        case 401, 403:
            throw APIError.tokenExpired
        default:
            throw APIError.httpError(httpResponse.statusCode)
        }
    }

    func testConnection(token: String, proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        let request = makeRequest(token: token)

        do {
            let (data, response) = try await session(proxyConfig: proxyConfig).data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return ConnectionTestResult(success: false, message: String(localized: "error.invalidresponse.short"))
            }

            if httpResponse.statusCode == 200 {
                guard let usage = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
                    return ConnectionTestResult(success: false, message: String(localized: "error.unsupportedplan"))
                }
                let sessionPct = usage.fiveHour?.utilization ?? 0
                return ConnectionTestResult(success: true, message: String(format: String(localized: "test.success"), Int(sessionPct)))
            } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return ConnectionTestResult(success: false, message: String(format: String(localized: "test.expired"), httpResponse.statusCode))
            } else {
                return ConnectionTestResult(success: false, message: String(format: String(localized: "test.http"), httpResponse.statusCode))
            }
        } catch {
            return ConnectionTestResult(success: false, message: String(format: String(localized: "error.network"), error.localizedDescription))
        }
    }
}
```

**Step 4: Create NotificationService**

`Shared/Services/NotificationService.swift`:

```swift
import Foundation
import UserNotifications

final class NotificationService: NotificationServiceProtocol {
    private let center = UNUserNotificationCenter.current()

    func setupDelegate() {
        center.delegate = NotificationDelegate.shared
    }

    func requestPermission() {
        setupDelegate()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "TokenEater"
        content.body = String(localized: "notif.test.body")
        content.sound = .default
        send(id: "test_\(Date().timeIntervalSince1970)", content: content)
    }

    func checkThresholds(fiveHour: Int, sevenDay: Int, sonnet: Int, thresholds: UsageThresholds) {
        check(metric: "fiveHour", label: String(localized: "metric.session"), pct: fiveHour, thresholds: thresholds)
        check(metric: "sevenDay", label: String(localized: "metric.weekly"), pct: sevenDay, thresholds: thresholds)
        check(metric: "sonnet", label: String(localized: "metric.sonnet"), pct: sonnet, thresholds: thresholds)
    }

    private func check(metric: String, label: String, pct: Int, thresholds: UsageThresholds) {
        let key = "lastLevel_\(metric)"
        let previousRaw = UserDefaults.standard.integer(forKey: key)
        let previous = UsageLevel(rawValue: previousRaw) ?? .green
        let current = UsageLevel.from(pct: pct, thresholds: thresholds)

        guard current != previous else { return }
        UserDefaults.standard.set(current.rawValue, forKey: key)

        if current > previous {
            notifyEscalation(metric: metric, label: label, pct: pct, level: current, thresholds: thresholds)
        } else if current == .green && previous > .green {
            notifyRecovery(metric: metric, label: label, pct: pct)
        }
    }

    private func notifyEscalation(metric: String, label: String, pct: Int, level: UsageLevel, thresholds: UsageThresholds) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch level {
        case .orange:
            content.title = "⚠️ \(label) — \(pct)%"
            content.body = String(format: String(localized: "notif.orange.body"), thresholds.warningPercent)
        case .red:
            content.title = "🔴 \(label) — \(pct)%"
            content.body = String(localized: "notif.red.body")
        case .green:
            return
        }

        send(id: "escalation_\(metric)", content: content)
    }

    private func notifyRecovery(metric: String, label: String, pct: Int) {
        let content = UNMutableNotificationContent()
        content.title = "🟢 \(label) — \(pct)%"
        content.body = String(localized: "notif.green.body")
        content.sound = .default
        send(id: "recovery_\(metric)", content: content)
    }

    private func send(id: String, content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request)
    }
}
```

**Note:** `UsageLevel` and `NotificationDelegate` stay in the old `UsageNotificationManager.swift` file for now. They'll be moved/inlined when we delete the old file in Task 7.

**Step 5: Verify build**

```bash
xcodegen generate && \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED. Both old and new implementations coexist. The new types have different names (`APIClient` vs `ClaudeAPIClient`, etc.) so no conflicts.

**Important**: If there's a conflict with `ConnectionTestResult` (defined in both old `ClaudeAPIClient.swift` and new `APIClientProtocol.swift`), remove the struct from the old `ClaudeAPIClient.swift` file since the protocol file defines it now. Same for `ClaudeAPIError` — keep only `APIError` in the protocol file, and update `ClaudeAPIClient.swift` to use `APIError` instead of `ClaudeAPIError`.

**Step 6: Commit**

```bash
git add -A && git commit -m "refactor: add service implementations (APIClient, Keychain, SharedFile, Notification)"
```

---

### Task 5: Create UsageRepository

**Files:**
- Create: `Shared/Repositories/UsageRepositoryProtocol.swift`
- Create: `Shared/Repositories/UsageRepository.swift`

**Step 1: Create UsageRepositoryProtocol**

`Shared/Repositories/UsageRepositoryProtocol.swift`:

```swift
import Foundation

protocol UsageRepositoryProtocol {
    func refreshUsage(proxyConfig: ProxyConfig?) async throws -> UsageResponse
    func testConnection(proxyConfig: ProxyConfig?) async -> ConnectionTestResult
    func syncKeychainToken()
    var isConfigured: Bool { get }
    var cachedUsage: CachedUsage? { get }
}
```

**Step 2: Create UsageRepository**

`Shared/Repositories/UsageRepository.swift`:

```swift
import Foundation

final class UsageRepository: UsageRepositoryProtocol {
    private let apiClient: APIClientProtocol
    private let keychainService: KeychainServiceProtocol
    private let sharedFileService: SharedFileServiceProtocol

    init(
        apiClient: APIClientProtocol = APIClient(),
        keychainService: KeychainServiceProtocol = KeychainService(),
        sharedFileService: SharedFileServiceProtocol = SharedFileService()
    ) {
        self.apiClient = apiClient
        self.keychainService = keychainService
        self.sharedFileService = sharedFileService
    }

    func syncKeychainToken() {
        if let token = keychainService.readOAuthToken() {
            sharedFileService.oauthToken = token
        }
    }

    var isConfigured: Bool {
        sharedFileService.isConfigured
    }

    var cachedUsage: CachedUsage? {
        sharedFileService.cachedUsage
    }

    func refreshUsage(proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        guard let token = sharedFileService.oauthToken else {
            throw APIError.noToken
        }

        let usage = try await apiClient.fetchUsage(token: token, proxyConfig: proxyConfig)
        sharedFileService.updateAfterSync(
            usage: CachedUsage(usage: usage, fetchDate: Date()),
            syncDate: Date()
        )
        return usage
    }

    func testConnection(proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        guard let token = sharedFileService.oauthToken else {
            return ConnectionTestResult(success: false, message: String(localized: "error.notoken"))
        }
        return await apiClient.testConnection(token: token, proxyConfig: proxyConfig)
    }
}
```

**Step 3: Verify build**

```bash
xcodegen generate && \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build build 2>&1 | tail -5
```

**Step 4: Commit**

```bash
git add -A && git commit -m "refactor: add UsageRepository (orchestrates Keychain → API → SharedFile)"
```

---

### Task 6: Create @Observable Stores and MenuBarRenderer

**Files:**
- Create: `Shared/Stores/UsageStore.swift`
- Create: `Shared/Stores/ThemeStore.swift`
- Create: `Shared/Stores/SettingsStore.swift`
- Create: `Shared/Helpers/MenuBarRenderer.swift`

**Step 1: Create UsageStore**

`Shared/Stores/UsageStore.swift`:

```swift
import SwiftUI
import WidgetKit

@MainActor
@Observable
final class UsageStore {
    var fiveHourPct: Int = 0
    var sevenDayPct: Int = 0
    var sonnetPct: Int = 0
    var fiveHourReset: String = ""
    var pacingDelta: Int = 0
    var pacingZone: PacingZone = .onTrack
    var pacingResult: PacingResult?
    var lastUpdate: Date?
    var isLoading = false
    var hasError = false
    var hasConfig = false

    private let repository: UsageRepositoryProtocol
    private let notificationService: NotificationServiceProtocol
    private var refreshTask: Task<Void, Never>?

    // Proxy config — set by SettingsStore changes, read by repository calls
    var proxyConfig: ProxyConfig?

    init(
        repository: UsageRepositoryProtocol = UsageRepository(),
        notificationService: NotificationServiceProtocol = NotificationService()
    ) {
        self.repository = repository
        self.notificationService = notificationService
    }

    func refresh(thresholds: UsageThresholds = .default) async {
        repository.syncKeychainToken()

        guard repository.isConfigured else {
            hasConfig = false
            return
        }
        hasConfig = true
        isLoading = true
        defer { isLoading = false }
        do {
            let usage = try await repository.refreshUsage(proxyConfig: proxyConfig)
            update(from: usage)
            hasError = false
            lastUpdate = Date()
            WidgetCenter.shared.reloadAllTimelines()
            notificationService.checkThresholds(
                fiveHour: fiveHourPct,
                sevenDay: sevenDayPct,
                sonnet: sonnetPct,
                thresholds: thresholds
            )
        } catch {
            hasError = true
        }
    }

    func loadCached() {
        if let cached = repository.cachedUsage {
            update(from: cached.usage)
            lastUpdate = cached.fetchDate
        }
    }

    func reloadConfig(thresholds: UsageThresholds = .default) {
        repository.syncKeychainToken()
        hasConfig = repository.isConfigured
        loadCached()
        notificationService.requestPermission()
        WidgetCenter.shared.reloadAllTimelines()
        Task { await refresh(thresholds: thresholds) }
    }

    func startAutoRefresh(interval: TimeInterval = 300, thresholds: UsageThresholds = .default) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(thresholds: thresholds)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
    }

    func testConnection() async -> ConnectionTestResult {
        await repository.testConnection(proxyConfig: proxyConfig)
    }

    func connectAutoDetect() async -> ConnectionTestResult {
        repository.syncKeychainToken()
        let result = await repository.testConnection(proxyConfig: proxyConfig)
        if result.success {
            hasConfig = true
        }
        return result
    }

    // MARK: - Private

    private func update(from usage: UsageResponse) {
        fiveHourPct = Int(usage.fiveHour?.utilization ?? 0)
        sevenDayPct = Int(usage.sevenDay?.utilization ?? 0)
        sonnetPct = Int(usage.sevenDaySonnet?.utilization ?? 0)

        if let reset = usage.fiveHour?.resetsAtDate {
            let diff = reset.timeIntervalSinceNow
            if diff > 0 {
                let h = Int(diff) / 3600
                let m = (Int(diff) % 3600) / 60
                fiveHourReset = h > 0 ? "\(h)h \(m)min" : "\(m)min"
            } else {
                fiveHourReset = String(localized: "relative.now")
            }
        } else {
            fiveHourReset = ""
        }

        if let pacing = PacingCalculator.calculate(from: usage) {
            pacingDelta = Int(pacing.delta)
            pacingZone = pacing.zone
            pacingResult = pacing
        }
    }
}
```

**Step 2: Create ThemeStore**

`Shared/Stores/ThemeStore.swift`:

```swift
import SwiftUI
import WidgetKit

@MainActor
@Observable
final class ThemeStore {
    var selectedPreset: String {
        didSet {
            UserDefaults.standard.set(selectedPreset, forKey: "selectedPreset")
            scheduleSync()
        }
    }

    var customTheme: ThemeColors {
        didSet {
            if let data = try? JSONEncoder().encode(customTheme),
               let json = String(data: data, encoding: .utf8) {
                UserDefaults.standard.set(json, forKey: "customThemeJSON")
            }
            scheduleSync()
        }
    }

    var warningThreshold: Int {
        didSet {
            UserDefaults.standard.set(warningThreshold, forKey: "warningThreshold")
            scheduleSync()
        }
    }

    var criticalThreshold: Int {
        didSet {
            UserDefaults.standard.set(criticalThreshold, forKey: "criticalThreshold")
            scheduleSync()
        }
    }

    var menuBarMonochrome: Bool {
        didSet {
            UserDefaults.standard.set(menuBarMonochrome, forKey: "menuBarMonochrome")
        }
    }

    private let sharedFileService: SharedFileServiceProtocol

    init(sharedFileService: SharedFileServiceProtocol = SharedFileService()) {
        self.sharedFileService = sharedFileService

        self.selectedPreset = UserDefaults.standard.string(forKey: "selectedPreset") ?? "default"
        self.warningThreshold = {
            let val = UserDefaults.standard.integer(forKey: "warningThreshold")
            return val > 0 ? val : 60
        }()
        self.criticalThreshold = {
            let val = UserDefaults.standard.integer(forKey: "criticalThreshold")
            return val > 0 ? val : 85
        }()
        self.menuBarMonochrome = UserDefaults.standard.bool(forKey: "menuBarMonochrome")

        if let json = UserDefaults.standard.string(forKey: "customThemeJSON"),
           let data = json.data(using: .utf8),
           let theme = try? JSONDecoder().decode(ThemeColors.self, from: data) {
            self.customTheme = theme
        } else {
            self.customTheme = .default
        }
    }

    // MARK: - Resolved

    var current: ThemeColors {
        if selectedPreset == "custom" { return customTheme }
        return ThemeColors.preset(for: selectedPreset) ?? .default
    }

    var thresholds: UsageThresholds {
        UsageThresholds(warningPercent: warningThreshold, criticalPercent: criticalThreshold)
    }

    // MARK: - Menu Bar Colors

    func menuBarNSColor(for pct: Int) -> NSColor {
        if menuBarMonochrome { return .labelColor }
        return current.gaugeNSColor(for: Double(pct), thresholds: thresholds)
    }

    func menuBarPacingNSColor(for zone: PacingZone) -> NSColor {
        if menuBarMonochrome { return .labelColor }
        return current.pacingNSColor(for: zone)
    }

    // MARK: - Reset

    func resetToDefaults() {
        selectedPreset = "default"
        customTheme = .default
        warningThreshold = 60
        criticalThreshold = 85
        menuBarMonochrome = false
        syncToSharedFile()
    }

    // MARK: - Sync (debounced)

    private var syncWorkItem: DispatchWorkItem?

    private func scheduleSync() {
        syncWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.syncToSharedFile()
            }
        }
        syncWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    func syncToSharedFile() {
        sharedFileService.updateTheme(current, thresholds: thresholds)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
```

**Step 3: Create SettingsStore**

`Shared/Stores/SettingsStore.swift`:

```swift
import SwiftUI
import UserNotifications

@MainActor
@Observable
final class SettingsStore {
    // Menu bar
    var showMenuBar: Bool {
        didSet { UserDefaults.standard.set(showMenuBar, forKey: "showMenuBar") }
    }
    var pinnedMetrics: Set<MetricID> {
        didSet { savePinnedMetrics() }
    }
    var pacingDisplayMode: PacingDisplayMode {
        didSet { UserDefaults.standard.set(pacingDisplayMode.rawValue, forKey: "pacingDisplayMode") }
    }
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    // Proxy
    var proxyEnabled: Bool {
        didSet { UserDefaults.standard.set(proxyEnabled, forKey: "proxyEnabled") }
    }
    var proxyHost: String {
        didSet { UserDefaults.standard.set(proxyHost, forKey: "proxyHost") }
    }
    var proxyPort: Int {
        didSet { UserDefaults.standard.set(proxyPort, forKey: "proxyPort") }
    }

    var proxyConfig: ProxyConfig {
        ProxyConfig(enabled: proxyEnabled, host: proxyHost, port: proxyPort)
    }

    // Notifications
    var notificationStatus: UNAuthorizationStatus = .notDetermined

    private let notificationService: NotificationServiceProtocol
    private let keychainService: KeychainServiceProtocol

    init(
        notificationService: NotificationServiceProtocol = NotificationService(),
        keychainService: KeychainServiceProtocol = KeychainService()
    ) {
        self.notificationService = notificationService
        self.keychainService = keychainService

        self.showMenuBar = UserDefaults.standard.object(forKey: "showMenuBar") as? Bool ?? true
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.proxyEnabled = UserDefaults.standard.bool(forKey: "proxyEnabled")
        self.proxyHost = UserDefaults.standard.string(forKey: "proxyHost") ?? "127.0.0.1"
        self.proxyPort = {
            let port = UserDefaults.standard.integer(forKey: "proxyPort")
            return port > 0 ? port : 1080
        }()
        self.pacingDisplayMode = PacingDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: "pacingDisplayMode") ?? "dotDelta"
        ) ?? .dotDelta

        if let saved = UserDefaults.standard.stringArray(forKey: "pinnedMetrics") {
            self.pinnedMetrics = Set(saved.compactMap { MetricID(rawValue: $0) })
        } else {
            self.pinnedMetrics = [.fiveHour, .sevenDay]
        }
    }

    // MARK: - Metrics

    func toggleMetric(_ metric: MetricID) {
        if pinnedMetrics.contains(metric) {
            if pinnedMetrics.count > 1 {
                pinnedMetrics.remove(metric)
            }
        } else {
            pinnedMetrics.insert(metric)
        }
    }

    private func savePinnedMetrics() {
        UserDefaults.standard.set(pinnedMetrics.map(\.rawValue), forKey: "pinnedMetrics")
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        notificationService.requestPermission()
    }

    func sendTestNotification() {
        notificationService.sendTest()
    }

    func refreshNotificationStatus() async {
        notificationStatus = await notificationService.checkAuthorizationStatus()
    }

    // MARK: - Keychain

    func keychainTokenExists() -> Bool {
        keychainService.tokenExists()
    }

    func readKeychainToken() -> String? {
        keychainService.readOAuthToken()
    }
}
```

**Step 4: Create MenuBarRenderer**

`Shared/Helpers/MenuBarRenderer.swift`:

```swift
import AppKit

enum MenuBarRenderer {
    struct RenderData {
        let pinnedMetrics: Set<MetricID>
        let fiveHourPct: Int
        let sevenDayPct: Int
        let sonnetPct: Int
        let pacingDelta: Int
        let pacingZone: PacingZone
        let pacingDisplayMode: PacingDisplayMode
        let hasConfig: Bool
        let hasError: Bool
        let colorForPct: (Int) -> NSColor
        let colorForZone: (PacingZone) -> NSColor
    }

    static func render(_ data: RenderData) -> NSImage {
        guard data.hasConfig, !data.hasError else {
            return renderText("--", color: .tertiaryLabelColor)
        }
        return renderPinnedMetrics(data)
    }

    private static func renderPinnedMetrics(_ data: RenderData) -> NSImage {
        let height: CGFloat = 22
        let str = NSMutableAttributedString()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let sepAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        let ordered: [MetricID] = [.fiveHour, .sevenDay, .sonnet, .pacing].filter { data.pinnedMetrics.contains($0) }
        for (i, metric) in ordered.enumerated() {
            if i > 0 {
                str.append(NSAttributedString(string: "  ", attributes: sepAttrs))
            }
            if metric == .pacing {
                let dotColor = data.colorForZone(data.pacingZone)
                let dotAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: dotColor,
                ]
                str.append(NSAttributedString(string: "\u{25CF}", attributes: dotAttrs))
                if data.pacingDisplayMode == .dotDelta {
                    let sign = data.pacingDelta >= 0 ? "+" : ""
                    let deltaAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
                        .foregroundColor: dotColor,
                    ]
                    str.append(NSAttributedString(string: " \(sign)\(data.pacingDelta)%", attributes: deltaAttrs))
                }
            } else {
                let value: Int
                switch metric {
                case .fiveHour: value = data.fiveHourPct
                case .sevenDay: value = data.sevenDayPct
                case .sonnet: value = data.sonnetPct
                case .pacing: value = 0 // handled above
                }
                str.append(NSAttributedString(string: "\(metric.shortLabel) ", attributes: labelAttrs))
                let pctAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: data.colorForPct(value),
                ]
                str.append(NSAttributedString(string: "\(value)%", attributes: pctAttrs))
            }
        }

        let size = str.size()
        let imgSize = NSSize(width: ceil(size.width) + 2, height: height)
        let img = NSImage(size: imgSize)
        img.lockFocus()
        str.draw(at: NSPoint(x: 1, y: (height - size.height) / 2))
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    private static func renderText(_ text: String, color: NSColor) -> NSImage {
        let height: CGFloat = 22
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: color,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let img = NSImage(size: NSSize(width: ceil(size.width) + 2, height: height))
        img.lockFocus()
        str.draw(at: NSPoint(x: 1, y: (height - size.height) / 2))
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}
```

**Step 5: Verify build**

```bash
xcodegen generate && \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED. New stores and renderer coexist with old code.

**Note:** `MetricID` and `PacingDisplayMode` are still defined in `MenuBarView.swift`. They need to be accessible by `SettingsStore` and `MenuBarRenderer`. Since both the app and widget share `Shared/`, move these enums to a file in `Shared/Models/` if the build fails due to the widget not seeing them. If the build succeeds (because the app target includes both `TokenEaterApp/` and `Shared/`), keep them in place for now and move them in Task 7.

**Step 6: Commit**

```bash
git add -A && git commit -m "refactor: add @Observable stores (Usage, Theme, Settings) + MenuBarRenderer"
```

---

### Task 7: Rewire App + Views to use new architecture

This is the biggest task. We replace all old patterns with the new ones and delete legacy files.

**Files:**
- Modify: `TokenEaterApp/TokenEaterApp.swift` (complete rewrite)
- Modify: `TokenEaterApp/MenuBarView.swift` (complete rewrite — remove MenuBarViewModel)
- Modify: `TokenEaterApp/SettingsView.swift` (replace all service references)
- Modify: `TokenEaterApp/OnboardingView.swift` (replace @StateObject with @State)
- Modify: `TokenEaterApp/OnboardingViewModel.swift` (replace to @Observable, use services)
- Modify: `TokenEaterApp/OnboardingSteps/ConnectionStep.swift` (replace @ObservedObject)
- Modify: `TokenEaterApp/OnboardingSteps/PrerequisiteStep.swift` (replace @ObservedObject)
- Modify: `TokenEaterApp/OnboardingSteps/NotificationStep.swift` (replace @ObservedObject)
- Modify: `TokenEaterApp/OnboardingSteps/WelcomeStep.swift` (replace @ObservedObject)
- Move: `MetricID`, `PacingDisplayMode` to `Shared/Models/` if not already
- Delete: `Shared/ClaudeAPIClient.swift`
- Delete: `Shared/KeychainOAuthReader.swift`
- Delete: `Shared/SharedContainer.swift`
- Delete: `Shared/ThemeManager.swift`
- Delete: `Shared/UsageNotificationManager.swift`

**Step 1: Move MetricID and PacingDisplayMode to Shared/Models/**

Create `Shared/Models/MetricModels.swift`:

```swift
import Foundation

enum MetricID: String, CaseIterable {
    case fiveHour = "fiveHour"
    case sevenDay = "sevenDay"
    case sonnet = "sonnet"
    case pacing = "pacing"

    var label: String {
        switch self {
        case .fiveHour: return String(localized: "metric.session")
        case .sevenDay: return String(localized: "metric.weekly")
        case .sonnet: return String(localized: "metric.sonnet")
        case .pacing: return String(localized: "pacing.label")
        }
    }

    var shortLabel: String {
        switch self {
        case .fiveHour: return "5h"
        case .sevenDay: return "7d"
        case .sonnet: return "S"
        case .pacing: return "P"
        }
    }
}

enum PacingDisplayMode: String {
    case dot
    case dotDelta
}
```

**Step 2: Rewrite TokenEaterApp.swift**

```swift
import SwiftUI

@main
struct TokenEaterApp: App {
    @State private var usageStore = UsageStore()
    @State private var themeStore = ThemeStore()
    @State private var settingsStore = SettingsStore()

    init() {
        NotificationService().setupDelegate()
    }

    var body: some Scene {
        WindowGroup(id: "settings") {
            if settingsStore.hasCompletedOnboarding {
                SettingsView()
            } else {
                OnboardingView()
            }
        }
        .environment(usageStore)
        .environment(themeStore)
        .environment(settingsStore)
        .onChange(of: settingsStore.hasCompletedOnboarding) { _, completed in
            if completed {
                usageStore.proxyConfig = settingsStore.proxyConfig
                usageStore.reloadConfig(thresholds: themeStore.thresholds)
                themeStore.syncToSharedFile()
            }
        }
        .windowResizability(.contentSize)

        MenuBarExtra(isInserted: Bindable(settingsStore).showMenuBar) {
            MenuBarPopoverView()
        } label: {
            Image(nsImage: menuBarImage)
        }
        .environment(usageStore)
        .environment(themeStore)
        .environment(settingsStore)
        .menuBarExtraStyle(.window)
    }

    private var menuBarImage: NSImage {
        MenuBarRenderer.render(MenuBarRenderer.RenderData(
            pinnedMetrics: settingsStore.pinnedMetrics,
            fiveHourPct: usageStore.fiveHourPct,
            sevenDayPct: usageStore.sevenDayPct,
            sonnetPct: usageStore.sonnetPct,
            pacingDelta: usageStore.pacingDelta,
            pacingZone: usageStore.pacingZone,
            pacingDisplayMode: settingsStore.pacingDisplayMode,
            hasConfig: usageStore.hasConfig,
            hasError: usageStore.hasError,
            colorForPct: { themeStore.menuBarNSColor(for: $0) },
            colorForZone: { themeStore.menuBarPacingNSColor(for: $0) }
        ))
    }
}
```

**Important:** The `Bindable(settingsStore).showMenuBar` pattern is needed to get a `Binding<Bool>` from an `@Observable` property for `isInserted:`. If Bindable doesn't work on `@State`, use `$settingsStore.showMenuBar` or store showMenuBar as an `@AppStorage` separately in the App struct and sync it.

**Step 3: Rewrite MenuBarView.swift**

Remove `MenuBarViewModel` entirely. Keep `MenuBarPopoverView` but use `@Environment`:

```swift
import SwiftUI
import WidgetKit

// MARK: - Popover View

struct MenuBarPopoverView: View {
    @Environment(UsageStore.self) private var usageStore
    @Environment(ThemeStore.self) private var themeStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TokenEater")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                if usageStore.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Metrics (same layout as before, but read from usageStore)
            VStack(spacing: 8) {
                metricRow(id: .fiveHour, label: String(localized: "metric.session"), pct: usageStore.fiveHourPct, reset: usageStore.fiveHourReset)
                metricRow(id: .sevenDay, label: String(localized: "metric.weekly"), pct: usageStore.sevenDayPct, reset: nil)
                metricRow(id: .sonnet, label: String(localized: "metric.sonnet"), pct: usageStore.sonnetPct, reset: nil)
            }
            .padding(.horizontal, 16)

            // Pacing section (same layout — use usageStore.pacingResult)
            if let pacing = usageStore.pacingResult {
                // ... same pacing section as before, replace viewModel references:
                // viewModel.pinnedMetrics → settingsStore.pinnedMetrics
                // viewModel.toggleMetric → settingsStore.toggleMetric
                // theme.current → themeStore.current
                // theme.thresholds → themeStore.thresholds
            }

            // Last update
            if let date = usageStore.lastUpdate {
                let formattedDate = date.formatted(.relative(presentation: .named))
                Text(String(format: String(localized: "menubar.updated"), formattedDate))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, 10)
            }

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.top, 10)

            // Actions
            HStack(spacing: 0) {
                actionButton(icon: "arrow.clockwise", label: String(localized: "menubar.refresh")) {
                    Task { await usageStore.refresh(thresholds: themeStore.thresholds) }
                }
                actionButton(icon: "gear", label: String(localized: "menubar.settings")) {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: {
                        ($0.identifier?.rawValue ?? "").contains("settings")
                    }) {
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        openWindow(id: "settings")
                    }
                }
                actionButton(icon: "power", label: String(localized: "menubar.quit")) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(width: 260)
        .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)))
        .onAppear {
            if settingsStore.hasCompletedOnboarding && usageStore.lastUpdate == nil {
                usageStore.proxyConfig = settingsStore.proxyConfig
                usageStore.reloadConfig(thresholds: themeStore.thresholds)
                usageStore.startAutoRefresh(thresholds: themeStore.thresholds)
            }
        }
    }

    // ... keep actionButton, metricRow helper functions
    // Replace all `viewModel.xxx` with `usageStore.xxx` or `settingsStore.xxx`
    // Replace all `theme.current.xxx` with `themeStore.current.xxx`
    // Replace all `theme.thresholds` with `themeStore.thresholds`
}
```

**Step 4: Update SettingsView.swift**

Replace all service references:
- `@ObservedObject private var themeManager = ThemeManager.shared` → `@Environment(ThemeStore.self) private var themeStore`
- `@Environment(UsageStore.self) private var usageStore`
- `@Environment(SettingsStore.self) private var settingsStore`
- Remove `var onConfigSaved: (() -> Void)?` — no longer needed
- `ClaudeAPIClient.shared.testConnection()` → `usageStore.testConnection()`
- `KeychainOAuthReader.readClaudeCodeToken()` → `settingsStore.readKeychainToken()`
- `SharedContainer.oauthToken = oauth.accessToken` → removed (handled by repository)
- `UsageNotificationManager.*` → `settingsStore.requestNotificationPermission()` etc.
- `themeManager.*` → `themeStore.*`
- `@AppStorage` properties → read from `settingsStore`
- Remove `Notification.Name.displaySettingsDidChange` entirely

**Step 5: Update OnboardingViewModel to @Observable**

```swift
import SwiftUI
import WidgetKit

// Keep OnboardingStep, ClaudeCodeStatus, ConnectionStatus, NotificationStatus enums as-is

@MainActor
@Observable
final class OnboardingViewModel {
    var currentStep: OnboardingStep = .welcome
    var isDetailedMode = false
    var claudeCodeStatus: ClaudeCodeStatus = .checking
    var connectionStatus: ConnectionStatus = .idle
    var notificationStatus: NotificationStatus = .unknown

    private let keychainService: KeychainServiceProtocol
    private let repository: UsageRepositoryProtocol
    private let notificationService: NotificationServiceProtocol

    init(
        keychainService: KeychainServiceProtocol = KeychainService(),
        repository: UsageRepositoryProtocol = UsageRepository(),
        notificationService: NotificationServiceProtocol = NotificationService()
    ) {
        self.keychainService = keychainService
        self.repository = repository
        self.notificationService = notificationService
    }

    func checkClaudeCode() {
        claudeCodeStatus = .checking
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.claudeCodeStatus = self?.keychainService.tokenExists() == true ? .detected : .notFound
        }
    }

    func checkNotificationStatus() {
        Task {
            let status = await notificationService.checkAuthorizationStatus()
            switch status {
            case .authorized, .provisional, .ephemeral:
                notificationStatus = .authorized
            case .denied:
                notificationStatus = .denied
            case .notDetermined:
                notificationStatus = .notYetAsked
            @unknown default:
                notificationStatus = .unknown
            }
        }
    }

    func requestNotifications() {
        notificationService.requestPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkNotificationStatus()
        }
    }

    func connect() {
        connectionStatus = .connecting
        repository.syncKeychainToken()
        guard repository.isConfigured else {
            connectionStatus = .failed(String(localized: "onboarding.connection.failed.notoken"))
            return
        }

        Task {
            do {
                let usage = try await repository.refreshUsage(proxyConfig: nil)
                connectionStatus = .success(usage)
            } catch {
                connectionStatus = .failed(error.localizedDescription)
            }
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        WidgetCenter.shared.reloadAllTimelines()
    }

    func goNext() { /* same as before */ }
    func goBack() { /* same as before */ }
}
```

**Step 6: Update OnboardingView and all steps**

In `OnboardingView.swift`:
- `@StateObject private var viewModel = OnboardingViewModel()` → `@State private var viewModel = OnboardingViewModel()`

In all step views (`WelcomeStep`, `PrerequisiteStep`, `NotificationStep`, `ConnectionStep`):
- `@ObservedObject var viewModel: OnboardingViewModel` → `@Bindable var viewModel: OnboardingViewModel`

**Note:** With @Observable, you use `@Bindable` when you need bindings to the object's properties (like `$viewModel.isDetailedMode`). For read-only access, a plain `var viewModel: OnboardingViewModel` works.

**Step 7: Delete old files**

```bash
rm Shared/ClaudeAPIClient.swift
rm Shared/KeychainOAuthReader.swift
rm Shared/SharedContainer.swift
rm Shared/ThemeManager.swift
rm Shared/UsageNotificationManager.swift
```

**Note:** Before deleting `UsageNotificationManager.swift`, move `UsageLevel` enum and `NotificationDelegate` class to `Shared/Services/NotificationService.swift` (add them at the bottom of that file).

**Step 8: Verify build**

```bash
xcodegen generate && \
plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' TokenEaterWidget/Info.plist 2>/dev/null; \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build build 2>&1 | tail -5
```

This will likely require several iterations to fix compilation errors. Common issues:
- Missing imports
- `@Bindable` vs `@ObservedObject` syntax differences
- `Bindable()` wrapper for creating bindings from @Observable
- Access to stores in views that don't have `@Environment` set up

**Step 9: Commit**

```bash
git add -A && git commit -m "refactor: rewire app + views to @Observable stores, remove legacy services"
```

---

### Task 8: Rewire Widget to use new services

**Files:**
- Modify: `TokenEaterWidget/Provider.swift`
- Modify: `TokenEaterWidget/UsageWidgetView.swift`
- Modify: `TokenEaterWidget/PacingWidgetView.swift`

**Step 1: Update Provider.swift**

The widget uses `SharedContainer` for read-only access. Replace with `SharedFileService`:

```swift
import WidgetKit
import Foundation

struct Provider: TimelineProvider {
    private let sharedFileService = SharedFileService()

    func placeholder(in context: Context) -> UsageEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        completion(fetchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = fetchEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func fetchEntry() -> UsageEntry {
        guard sharedFileService.isConfigured else {
            return .unconfigured
        }

        if let cached = sharedFileService.cachedUsage {
            let isStale: Bool
            if let lastSync = sharedFileService.lastSyncDate {
                isStale = Date().timeIntervalSince(lastSync) > 600
            } else {
                isStale = true
            }
            return UsageEntry(
                date: Date(),
                usage: cached.usage,
                isStale: isStale
            )
        }

        return UsageEntry(date: Date(), usage: nil, error: String(localized: "error.nodata"))
    }
}
```

**Step 2: Update UsageWidgetView.swift**

Replace all `SharedContainer.theme` and `SharedContainer.thresholds` with a local `SharedFileService` instance:

```swift
// At the top of UsageWidgetView and sub-views:
private let sharedFileService = SharedFileService()
private var theme: ThemeColors { sharedFileService.theme }
private var thresholds: UsageThresholds { sharedFileService.thresholds }
```

Also update `WidgetBackgroundModifier`:
```swift
struct WidgetBackgroundModifier: ViewModifier {
    var backgroundColor: Color = Color(hex: SharedFileService().theme.widgetBackground).opacity(0.85)
    // ... rest same
}
```

Similarly for `CircularUsageView`, `CircularPacingView`, `LargeUsageBarView` — replace default parameter values `SharedContainer.theme` with `SharedFileService().theme`.

**Step 3: Update PacingWidgetView.swift**

Same pattern — replace `SharedContainer.theme` with `SharedFileService().theme`.

**Step 4: Verify build**

```bash
xcodegen generate && \
plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' TokenEaterWidget/Info.plist 2>/dev/null; \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build build 2>&1 | tail -5
```

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rewire widget to use SharedFileService instead of SharedContainer"
```

---

### Task 9: Update CLAUDE.md and final cleanup

**Files:**
- Modify: `CLAUDE.md`
- Verify: full clean build

**Step 1: Update CLAUDE.md**

Add an **Architecture** section after the existing "Notes techniques" section:

```markdown
## Architecture

The codebase follows **MV Pattern + Repository Pattern + Protocol-Oriented Design** with `@Observable` (Swift 5.9+):

### Layers
- **Models** (`Shared/Models/`): Pure Codable structs (UsageResponse, ThemeColors, ProxyConfig, etc.)
- **Services** (`Shared/Services/`): Single-responsibility I/O with protocol-based design (APIClient, KeychainService, SharedFileService, NotificationService)
- **Repository** (`Shared/Repositories/`): Orchestrates Keychain → API → SharedFile pipeline
- **Stores** (`Shared/Stores/`): `@Observable` state containers injected via `@Environment` (UsageStore, ThemeStore, SettingsStore)
- **Helpers** (`Shared/Helpers/`): Pure functions (PacingCalculator, MenuBarRenderer)

### Key Patterns
- **No singletons** — all dependencies are injected
- **@Environment DI** — stores are passed through SwiftUI environment
- **Protocol-based services** — every service has a protocol for testability
- **Strategy pattern for themes** — ThemeColors presets + custom theme support
```

Also update all references to old file/folder names in CLAUDE.md.

Update the build commands — replace `ClaudeUsageWidget.xcodeproj` with `TokenEater.xcodeproj`, `-scheme ClaudeUsageApp` with `-scheme TokenEaterApp`.

Update the entitlement reference paths.

**Step 2: Full clean build**

```bash
rm -rf build && \
xcodegen generate && \
plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' TokenEaterWidget/Info.plist 2>/dev/null; \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add -A && git commit -m "docs: update CLAUDE.md with new architecture + final cleanup"
```

---

## Summary

| Task | What | Commit message |
|------|------|----------------|
| 1 | Rename folders/types/bundle IDs/entitlements/CI | `rename: ClaudeUsage → TokenEater (...)` |
| 2 | Create folder structure + extract Models | `refactor: reorganize Shared/ into Models/, Helpers/, Extensions/` |
| 3 | Create Service Protocols | `refactor: add service protocols (...)` |
| 4 | Create Service Implementations (with migration) | `refactor: add service implementations (...)` |
| 5 | Create UsageRepository | `refactor: add UsageRepository (...)` |
| 6 | Create @Observable Stores + MenuBarRenderer | `refactor: add @Observable stores (...) + MenuBarRenderer` |
| 7 | Rewire App + Views (delete old files) | `refactor: rewire app + views to @Observable stores, remove legacy` |
| 8 | Rewire Widget | `refactor: rewire widget to use SharedFileService` |
| 9 | Update CLAUDE.md + final build | `docs: update CLAUDE.md with new architecture + final cleanup` |

**Build verification after EVERY task.** If a build fails, fix before committing.
