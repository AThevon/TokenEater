# App Group Shared Container — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace direct Keychain access and API calls in the widget with an App Group shared container, so only the main app touches the Keychain and API.

**Architecture:** The main app reads Keychain, calls the API, and pushes token + usage data to a shared UserDefaults (`group.com.claudeusagewidget.shared`). The widget reads only from that shared container. This eliminates the macOS password prompt caused by cross-process Keychain access.

**Tech Stack:** Swift 5.9, macOS 14+, WidgetKit, UserDefaults App Group, XcodeGen

---

### Task 1: Add App Group entitlements to both targets

**Files:**
- Modify: `ClaudeUsageApp/ClaudeUsageApp.entitlements`
- Modify: `ClaudeUsageWidget/ClaudeUsageWidget.entitlements`
- Modify: `project.yml`

**Step 1: Add App Group to app entitlements**

Replace `ClaudeUsageApp/ClaudeUsageApp.entitlements` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.claudeusagewidget.shared</string>
    </array>
</dict>
</plist>
```

**Step 2: Add App Group to widget entitlements**

Replace `ClaudeUsageWidget/ClaudeUsageWidget.entitlements` with the same content (identical entitlements).

**Step 3: Remove network.client from widget entitlements**

The widget no longer makes network calls. Replace `ClaudeUsageWidget/ClaudeUsageWidget.entitlements` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.claudeusagewidget.shared</string>
    </array>
</dict>
</plist>
```

**Step 4: Verify project.yml needs no App Group declaration**

XcodeGen reads entitlements from the `.entitlements` files. The `project.yml` already references them via `CODE_SIGN_ENTITLEMENTS`. No change needed in `project.yml` for the App Group itself.

**Step 5: Commit**

```bash
git add ClaudeUsageApp/ClaudeUsageApp.entitlements ClaudeUsageWidget/ClaudeUsageWidget.entitlements
git commit -m "feat: add App Group entitlement to both targets (#7)"
```

---

### Task 2: Create SharedContainer

**Files:**
- Create: `Shared/SharedContainer.swift`

**Step 1: Create SharedContainer.swift**

```swift
import Foundation

enum SharedContainer {
    static let suiteName = "group.com.claudeusagewidget.shared"

    private static let tokenKey = "oauthToken"
    private static let cachedUsageKey = "cachedUsage"
    private static let lastSyncDateKey = "lastSyncDate"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    // MARK: - OAuth Token

    static var oauthToken: String? {
        get { defaults?.string(forKey: tokenKey) }
        set { defaults?.set(newValue, forKey: tokenKey) }
    }

    // MARK: - Cached Usage

    static var cachedUsage: CachedUsage? {
        get {
            guard let data = defaults?.data(forKey: cachedUsageKey) else { return nil }
            return try? JSONDecoder().decode(CachedUsage.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults?.set(data, forKey: cachedUsageKey)
            } else {
                defaults?.removeObject(forKey: cachedUsageKey)
            }
        }
    }

    // MARK: - Last Sync Date

    static var lastSyncDate: Date? {
        get { defaults?.object(forKey: lastSyncDateKey) as? Date }
        set { defaults?.set(newValue, forKey: lastSyncDateKey) }
    }

    // MARK: - Convenience

    static var isConfigured: Bool {
        oauthToken != nil
    }

    static func clear() {
        defaults?.removeObject(forKey: tokenKey)
        defaults?.removeObject(forKey: cachedUsageKey)
        defaults?.removeObject(forKey: lastSyncDateKey)
    }
}
```

**Step 2: Commit**

```bash
git add Shared/SharedContainer.swift
git commit -m "feat: add SharedContainer for App Group UserDefaults (#7)"
```

---

### Task 3: Migrate ClaudeAPIClient to use SharedContainer

**Files:**
- Modify: `Shared/ClaudeAPIClient.swift`
- Modify: `Shared/UsageModels.swift`

**Step 1: Update ClaudeAPIClient to use SharedContainer instead of Keychain and LocalCache**

In `ClaudeAPIClient.swift`:

1. Change `isConfigured` to read from `SharedContainer`:
```swift
var isConfigured: Bool {
    SharedContainer.isConfigured
}
```

2. Change `fetchUsage()` to read token from `SharedContainer` and write cache to `SharedContainer`:
```swift
func fetchUsage() async throws -> UsageResponse {
    guard let token = SharedContainer.oauthToken else {
        throw ClaudeAPIError.noToken
    }

    var request = URLRequest(url: oauthURL)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

    let (data, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw ClaudeAPIError.invalidResponse
    }

    switch httpResponse.statusCode {
    case 200:
        let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
        let cached = CachedUsage(usage: usage, fetchDate: Date())
        SharedContainer.cachedUsage = cached
        SharedContainer.lastSyncDate = Date()
        return usage
    case 401, 403:
        throw ClaudeAPIError.tokenExpired
    default:
        throw ClaudeAPIError.httpError(httpResponse.statusCode)
    }
}
```

3. Change `testConnection()` to read token from `SharedContainer`:
```swift
func testConnection() async -> ConnectionTestResult {
    guard let token = SharedContainer.oauthToken else {
        return ConnectionTestResult(success: false, message: String(localized: "error.notoken"))
    }

    var request = URLRequest(url: oauthURL)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

    // ... rest unchanged
}
```

4. Change `loadCachedUsage()` to read from `SharedContainer`:
```swift
func loadCachedUsage() -> CachedUsage? {
    SharedContainer.cachedUsage
}
```

**Step 2: Remove LocalCache from UsageModels.swift**

Delete the entire `LocalCache` enum (lines 87-106 in `Shared/UsageModels.swift`):
```swift
// DELETE THIS ENTIRE BLOCK:
// MARK: - Local Cache (each target writes to its own sandbox Application Support)

enum LocalCache { ... }
```

Also update the comment on `ProxyConfig` (line 73) from:
```swift
// MARK: - Proxy Config (injectable — app uses UserDefaults, widget uses AppIntent)
```
to:
```swift
// MARK: - Proxy Config
```

**Step 3: Verify build compiles**

Run: `cd /Users/adrienthevon/projects/tokeneater-feat-7-use-app-group-shared-container && xcodegen generate && xcodebuild -scheme ClaudeUsageApp -configuration Debug build 2>&1 | tail -20`

Expected: Build may fail because widget still references `ProxyIntent`, `RefreshIntent`, `ClaudeAPIClient.fetchUsage()`. That's OK — we'll fix it in Task 5.

**Step 4: Commit**

```bash
git add Shared/ClaudeAPIClient.swift Shared/UsageModels.swift
git commit -m "feat: migrate ClaudeAPIClient to SharedContainer, remove LocalCache (#7)"
```

---

### Task 4: Update main app to sync token to SharedContainer

**Files:**
- Modify: `ClaudeUsageApp/MenuBarView.swift`
- Modify: `ClaudeUsageApp/SettingsView.swift`

**Step 1: Update MenuBarViewModel.refresh() to sync token before API call**

In `MenuBarView.swift`, update the `refresh()` method:

```swift
func refresh() async {
    // Sync Keychain token to SharedContainer
    if let oauth = KeychainOAuthReader.readClaudeCodeToken() {
        SharedContainer.oauthToken = oauth.accessToken
    }

    guard ClaudeAPIClient.shared.isConfigured else {
        hasConfig = false
        return
    }
    hasConfig = true
    isLoading = true
    defer { isLoading = false }
    do {
        let usage = try await ClaudeAPIClient.shared.fetchUsage()
        update(from: usage)
        hasError = false
        lastUpdate = Date()
        UsageNotificationManager.checkThresholds(
            fiveHour: fiveHourPct,
            sevenDay: sevenDayPct,
            sonnet: sonnetPct
        )
    } catch {
        hasError = true
    }
}
```

**Step 2: Update MenuBarViewModel.init() hasConfig check**

Change line 66:
```swift
// Before:
hasConfig = ClaudeAPIClient.shared.isConfigured
// After:
if let oauth = KeychainOAuthReader.readClaudeCodeToken() {
    SharedContainer.oauthToken = oauth.accessToken
}
hasConfig = SharedContainer.isConfigured
```

**Step 3: Update MenuBarViewModel.reloadConfig()**

```swift
func reloadConfig() {
    if let oauth = KeychainOAuthReader.readClaudeCodeToken() {
        SharedContainer.oauthToken = oauth.accessToken
    }
    hasConfig = SharedContainer.isConfigured
    Task { await refresh() }
}
```

**Step 4: Update SettingsView.connectAutoDetect()**

In `SettingsView.swift`, update `connectAutoDetect()` to sync token to SharedContainer:

```swift
private func connectAutoDetect() {
    isImporting = true
    importMessage = nil

    guard let oauth = KeychainOAuthReader.readClaudeCodeToken() else {
        isImporting = false
        importMessage = String(localized: "connect.noclaudecode")
        importSuccess = false
        return
    }

    // Sync token to SharedContainer
    SharedContainer.oauthToken = oauth.accessToken

    Task {
        let result = await ClaudeAPIClient.shared.testConnection()
        await MainActor.run {
            isImporting = false
            if result.success {
                authMethodLabel = String(localized: "connect.method.oauth")
                importMessage = String(localized: "connect.oauth.success")
                importSuccess = true
                onConfigSaved?()
            } else {
                importMessage = result.message
                importSuccess = false
            }
        }
    }
}
```

**Step 5: Update SettingsView.loadConfig()**

```swift
private func loadConfig() {
    loadPinnedMetrics()
    if let oauth = KeychainOAuthReader.readClaudeCodeToken() {
        SharedContainer.oauthToken = oauth.accessToken
        authMethodLabel = String(localized: "connect.method.oauth")
    }
}
```

**Step 6: Commit**

```bash
git add ClaudeUsageApp/MenuBarView.swift ClaudeUsageApp/SettingsView.swift
git commit -m "feat: sync Keychain token to SharedContainer in main app (#7)"
```

---

### Task 5: Rewrite widget to read from SharedContainer only

**Files:**
- Modify: `ClaudeUsageWidget/Provider.swift`
- Modify: `ClaudeUsageWidget/ClaudeUsageWidget.swift`
- Delete: `ClaudeUsageWidget/ProxyIntent.swift`
- Delete: `ClaudeUsageWidget/RefreshIntent.swift`
- Modify: `ClaudeUsageWidget/UsageWidgetView.swift`
- Modify: `ClaudeUsageWidget/PacingWidgetView.swift`

**Step 1: Rewrite Provider.swift**

Replace the entire file with:

```swift
import WidgetKit
import Foundation

struct Provider: TimelineProvider {
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
        guard SharedContainer.isConfigured else {
            return .unconfigured
        }

        if let cached = SharedContainer.cachedUsage {
            let isStale: Bool
            if let lastSync = SharedContainer.lastSyncDate {
                isStale = Date().timeIntervalSince(lastSync) > 600 // 10 minutes
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

**Note:** The provider switches from `AppIntentTimelineProvider` to `TimelineProvider` since there's no more `ProxyIntent` configuration.

**Step 2: Delete ProxyIntent.swift**

```bash
rm ClaudeUsageWidget/ProxyIntent.swift
```

**Step 3: Delete RefreshIntent.swift**

```bash
rm ClaudeUsageWidget/RefreshIntent.swift
```

**Step 4: Update ClaudeUsageWidget.swift**

Replace `AppIntentConfiguration` with `StaticConfiguration` since there's no more intent:

```swift
import WidgetKit
import SwiftUI

struct ClaudeUsageWidget: Widget {
    let kind: String = "ClaudeUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("TokenEater")
        .description(String(localized: "widget.description.usage"))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct PacingWidget: Widget {
    let kind: String = "PacingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PacingWidgetView(entry: entry)
        }
        .configurationDisplayName("TokenEater Pacing")
        .description(String(localized: "widget.description.pacing"))
        .supportedFamilies([.systemSmall])
    }
}

@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudeUsageWidget()
        PacingWidget()
    }
}
```

**Step 5: Remove refresh buttons from UsageWidgetView.swift**

In `UsageWidgetView.swift`, make these changes:

1. Remove the `import AppIntents` line (line 1).

2. In `mediumUsageContent`, replace the footer HStack (lines 91-103):
```swift
// Before (remove):
HStack {
    Text(...)
    Spacer()
    Button(intent: RefreshIntent()) { ... }
}

// After:
HStack {
    Text(String(format: String(localized: "widget.updated"), entry.date.relativeFormatted))
        .font(.system(size: 8, design: .rounded))
        .foregroundStyle(.white.opacity(0.3))
    Spacer()
    if entry.isStale {
        Image(systemName: "wifi.slash")
            .font(.system(size: 8))
            .foregroundStyle(.white.opacity(0.4))
    }
}
```

Note: Remove the duplicate stale indicator from the header since it's now in the footer.

3. In `largeUsageContent`, replace the footer (lines 199-219):
```swift
HStack {
    Text(String(format: String(localized: "widget.updated"), entry.date.relativeFormatted))
        .font(.system(size: 9, design: .rounded))
        .foregroundStyle(.white.opacity(0.3))
    Spacer()
    if entry.isStale {
        HStack(spacing: 3) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 9))
            Text("widget.offline")
                .font(.system(size: 9, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.4))
    } else {
        HStack(spacing: 3) {
            Circle()
                .fill(.green.opacity(0.6))
                .frame(width: 4, height: 4)
            Text(String(localized: "widget.refresh.interval"))
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.white.opacity(0.25))
        }
    }
}
```

4. Replace `errorView` to remove the refresh button:
```swift
private func errorView(_ message: String) -> some View {
    VStack(spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.title2)
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(hex: "#F97316"), Color(hex: "#EF4444")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        Text(message)
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
            .multilineTextAlignment(.center)
    }
    .padding()
}
```

5. Replace `placeholderView` to remove the refresh button:
```swift
private var placeholderView: some View {
    VStack(spacing: 8) {
        ProgressView()
            .tint(.orange)
        Text("widget.loading")
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(.white.opacity(0.4))
    }
}
```

**Step 6: Remove refresh button from PacingWidgetView.swift**

In `PacingWidgetView.swift`:

1. Remove the `import AppIntents` line.

2. In `pacingContent`, replace the header HStack (lines 22-38):
```swift
HStack(spacing: 4) {
    Circle()
        .fill(colorForZone(pacing.zone))
        .frame(width: 5, height: 5)
    Text("pacing.label")
        .font(.system(size: 9, weight: .heavy))
        .tracking(0.3)
        .foregroundStyle(.white.opacity(0.5))
    Spacer()
}
```

3. In `placeholderContent`, remove the refresh button (lines 94-100):
```swift
private var placeholderContent: some View {
    VStack(spacing: 6) {
        Image(systemName: "gauge.with.needle")
            .font(.system(size: 24))
            .foregroundStyle(.white.opacity(0.3))
        Text("widget.loading")
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.4))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

**Step 7: Build and verify**

Run: `xcodegen generate && xcodebuild -scheme ClaudeUsageApp -configuration Debug build 2>&1 | tail -30`

Expected: Build succeeds.

**Step 8: Commit**

```bash
git add -A
git commit -m "feat: rewrite widget to read from SharedContainer, remove ProxyIntent and RefreshIntent (#7)"
```

---

### Task 6: Update README with Security & Data Flow section

**Files:**
- Modify: `README.md`

**Step 1: Read current README**

Read `README.md` to understand the current structure.

**Step 2: Add Security & Data Flow section**

Add a section after the existing content that explains:

```markdown
## Security & Data Flow

TokenEater uses an **App Group shared container** to safely pass data between the menu bar app and the desktop widget.

### How it works

1. **Menu bar app** reads the Claude Code OAuth token from the macOS Keychain
2. The token and API responses are stored in a sandboxed App Group container (`group.com.claudeusagewidget.shared`)
3. **Widget** reads cached data from the shared container — it never touches the Keychain or makes API calls

### Why this architecture?

The Claude Code CLI creates its OAuth token in the macOS Keychain. When a different process (like a widget extension) tries to read it, macOS shows a password prompt. Since Claude Code recreates the token on refresh (resetting Keychain ACLs), this prompt would appear repeatedly.

By routing all Keychain access and API calls through the main app, only one process needs authorization — and the widget gets its data through the sandboxed shared container instead.

### Token storage

The OAuth token is stored in the App Group's `UserDefaults`, located in `~/Library/Group Containers/group.com.claudeusagewidget.shared/`. This directory is:
- **Sandboxed** — only the two app group members (menu bar app + widget) can access it
- **User-scoped** — stored in the user's Library, not system-wide
- **Not synced** — not backed up to iCloud or shared across devices
```

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add Security & Data Flow section to README (#7)"
```

---

### Task 7: Clean up — remove widget network entitlement from project.yml if needed

**Files:**
- Modify: `project.yml` (if needed)

**Step 1: Verify project.yml**

Check if `project.yml` has any network-related settings for the widget target that should be removed. Based on current reading, the entitlements are fully managed by the `.entitlements` files, so `project.yml` likely needs no changes.

**Step 2: Regenerate Xcode project and do final build**

```bash
xcodegen generate && xcodebuild -scheme ClaudeUsageApp -configuration Debug build 2>&1 | tail -30
```

Expected: Clean build with no warnings related to our changes.

**Step 3: Commit if any changes**

Only commit if `project.yml` needed changes.
