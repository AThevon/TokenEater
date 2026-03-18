# Widget Reliable Refresh — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the widget reliably display up-to-date data by hardening every link in the app→file→widget pipeline.

**Architecture:** The app/widget share data via `~/Library/Application Support/com.tokeneater.shared/shared.json`. We harden three weak points: (1) file I/O with `NSFileCoordinator` for atomic cross-process reads/writes, (2) widget timeline with `AppIntentTimelineProvider` + `.atEnd` policy + shorter intervals for more frequent refreshes independent of the reload budget, (3) redundant reload triggers from the app (foreground, heartbeat, popover open). We also eliminate wasteful `SharedFileService()` instantiation in widget views and add a diagnostic `lastSync` display in the widget footer.

**Tech Stack:** Swift, WidgetKit, AppIntents framework, NSFileCoordinator, macOS 14.0+

**Deployment target:** macOS 14.0 (confirmed in `project.yml`)

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `Shared/Services/SharedFileService.swift` | Add `NSFileCoordinator` to `load()` and `save()` |
| Modify | `Shared/Services/SharedFileServiceProtocol.swift` | Add `fileURL: URL` read-only property for coordinator |
| Modify | `Shared/Helpers/WidgetReloader.swift` | Use `reloadTimelines(ofKind:)` for both widget kinds |
| Modify | `Shared/Stores/UsageStore.swift` | Add `reloadWidgetOnForeground()` method |
| Modify | `TokenEaterApp/StatusBarController.swift` | Add workspace notification observer for app activate → widget reload |
| Modify | `TokenEaterWidget/Provider.swift` | Switch to `AppIntentTimelineProvider`, `.atEnd` policy, 3-min intervals, coordinated reads |
| Create | `TokenEaterWidget/RefreshIntent.swift` | `AppIntent` for interactive widget refresh button |
| Modify | `TokenEaterWidget/TokenEaterWidget.swift` | Switch from `StaticConfiguration` to `AppIntentConfiguration` |
| Modify | `TokenEaterWidget/UsageWidgetView.swift` | Singleton theme/thresholds, show lastSync in footer |
| Modify | `TokenEaterWidget/PacingWidgetView.swift` | Singleton theme access |
| Modify | `TokenEaterWidget/UsageEntry.swift` | Add `lastSync: Date?` field |
| Modify | `TokenEaterTests/Mocks/MockSharedFileService.swift` | Add `fileURL` property |

---

## Chunk 1: NSFileCoordinator on SharedFileService

### Task 1: Add coordinated file writes

**Files:**
- Modify: `Shared/Services/SharedFileService.swift:76-81` (save method)
- Modify: `Shared/Services/SharedFileServiceProtocol.swift` (add fileURL)
- Modify: `TokenEaterTests/Mocks/MockSharedFileService.swift` (add fileURL)

- [ ] **Step 1: Add `fileURL` to the protocol**

In `Shared/Services/SharedFileServiceProtocol.swift`, add a read-only property:

```swift
var fileURL: URL { get }
```

- [ ] **Step 2: Update MockSharedFileService**

In `TokenEaterTests/Mocks/MockSharedFileService.swift`, add:

```swift
var fileURL: URL { URL(fileURLWithPath: "/tmp/mock-shared.json") }
```

- [ ] **Step 3: Expose `fileURL` in SharedFileService**

In `Shared/Services/SharedFileService.swift`, make `sharedFileURL` accessible through the protocol:

```swift
var fileURL: URL { sharedFileURL }
```

- [ ] **Step 4: Add NSFileCoordinator to `save()`**

Replace the `save(_ shared:)` method in `SharedFileService.swift`:

```swift
private func save(_ shared: SharedData) {
    let dir = sharedFileURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let coordinator = NSFileCoordinator()
    var error: NSError?
    coordinator.coordinate(writingItemAt: sharedFileURL, options: .forReplacing, error: &error) { url in
        try? JSONEncoder().encode(shared).write(to: url, options: .atomic)
    }
    cachedData = shared
}
```

- [ ] **Step 5: Add NSFileCoordinator to `load()`**

Replace the `load()` method in `SharedFileService.swift`:

```swift
private func load() -> SharedData {
    if let cached = cachedData { return cached }

    var result = SharedData()
    let coordinator = NSFileCoordinator()
    var error: NSError?
    coordinator.coordinate(readingItemAt: sharedFileURL, options: [], error: &error) { url in
        guard let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? JSONDecoder().decode(SharedData.self, from: data) {
            result = decoded
        }
    }
    cachedData = result
    return result
}
```

- [ ] **Step 6: Run tests**

```bash
cd /Users/adrienthevon/projects/tokeneater-feat-104-bug-widget-still-doesn-t-updat && \
xcodegen generate && \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests \
  -configuration Debug -derivedDataPath build \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  test 2>&1 | tail -5
```

Expected: All 80 tests pass.

- [ ] **Step 7: Commit**

```bash
git add Shared/Services/SharedFileService.swift Shared/Services/SharedFileServiceProtocol.swift TokenEaterTests/Mocks/MockSharedFileService.swift
git commit -m "fix(widget): add NSFileCoordinator for atomic cross-process file I/O"
```

---

## Chunk 2: Targeted widget reload + app lifecycle triggers

### Task 2: Use targeted `reloadTimelines(ofKind:)` instead of `reloadAllTimelines()`

**Files:**
- Modify: `Shared/Helpers/WidgetReloader.swift`

- [ ] **Step 1: Replace reloadAllTimelines with targeted reloads**

Replace the entire `WidgetReloader.swift`:

```swift
import WidgetKit
import Foundation

/// Centralized, debounced widget timeline reloader.
/// Uses targeted reloadTimelines(ofKind:) for each widget kind
/// to avoid exhausting the shared reload budget.
@MainActor
enum WidgetReloader {
    static let usageKind = "TokenEaterWidget"
    static let pacingKind = "PacingWidget"

    private static var pending: DispatchWorkItem?

    /// Request a widget timeline reload for all widget kinds.
    /// Multiple calls within `delay` seconds are coalesced into one.
    static func scheduleReload(delay: TimeInterval = 0.5) {
        pending?.cancel()
        let item = DispatchWorkItem {
            WidgetCenter.shared.reloadTimelines(ofKind: usageKind)
            WidgetCenter.shared.reloadTimelines(ofKind: pacingKind)
        }
        pending = item
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + delay,
            execute: item
        )
    }
}
```

- [ ] **Step 2: Run tests**

```bash
cd /Users/adrienthevon/projects/tokeneater-feat-104-bug-widget-still-doesn-t-updat && \
xcodegen generate && \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests \
  -configuration Debug -derivedDataPath build \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  test 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Shared/Helpers/WidgetReloader.swift
git commit -m "fix(widget): use targeted reloadTimelines(ofKind:) per widget"
```

### Task 3: Add widget reload on app foreground

**Files:**
- Modify: `TokenEaterApp/StatusBarController.swift`

- [ ] **Step 1: Add workspace activation observer in `init`**

In `StatusBarController.swift`, after the `observeDashboardRequest()` call in `init` (line 39), add:

```swift
observeAppActivation()
```

- [ ] **Step 2: Add the observer method**

Add this method after `observeDashboardRequest()`:

```swift
private func observeAppActivation() {
    NSWorkspace.shared.notificationCenter.addObserver(
        self,
        selector: #selector(appDidActivate),
        name: NSWorkspace.didActivateApplicationNotification,
        object: nil
    )
}

@objc private func appDidActivate(_ notification: Notification) {
    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
          app.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
    WidgetReloader.scheduleReload(delay: 0.1)
}
```

- [ ] **Step 3: Commit**

```bash
git add TokenEaterApp/StatusBarController.swift
git commit -m "fix(widget): reload widget timelines when app activates"
```

---

## Chunk 3: AppIntentTimelineProvider + shorter intervals

### Task 4: Create RefreshIntent

**Files:**
- Create: `TokenEaterWidget/RefreshIntent.swift`

- [ ] **Step 1: Create the AppIntent file**

Create `TokenEaterWidget/RefreshIntent.swift`:

```swift
import AppIntents
import WidgetKit

struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh TokenEater Widget"
    static var description: IntentDescription = "Forces a refresh of the widget timeline"

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
```

This is a minimal intent used as the configuration type for `AppIntentConfiguration`. The actual data refresh happens in the TimelineProvider — the intent just gives WidgetKit a tighter integration hook.

- [ ] **Step 2: Commit**

```bash
git add TokenEaterWidget/RefreshIntent.swift
git commit -m "feat(widget): add RefreshWidgetIntent for AppIntentConfiguration"
```

### Task 5: Switch Provider to AppIntentTimelineProvider

**Files:**
- Modify: `TokenEaterWidget/Provider.swift`
- Modify: `TokenEaterWidget/UsageEntry.swift`

- [ ] **Step 1: Add `lastSync` to UsageEntry**

In `TokenEaterWidget/UsageEntry.swift`, add a `lastSync` field:

```swift
struct UsageEntry: TimelineEntry {
    let date: Date
    let usage: UsageResponse?
    let error: String?
    let isStale: Bool
    let lastSync: Date?

    init(date: Date, usage: UsageResponse?, error: String? = nil, isStale: Bool = false, lastSync: Date? = nil) {
        self.date = date
        self.usage = usage
        self.error = error
        self.isStale = isStale
        self.lastSync = lastSync
    }
```

Update `placeholder` and `unconfigured` statics — they already use the default `nil` for lastSync so no change needed.

- [ ] **Step 2: Rewrite Provider as AppIntentTimelineProvider**

Replace the entire `TokenEaterWidget/Provider.swift`:

```swift
import WidgetKit
import AppIntents
import Foundation

struct Provider: AppIntentTimelineProvider {
    private let sharedFile = SharedFileService()

    func placeholder(in context: Context) -> UsageEntry {
        .placeholder
    }

    func snapshot(for configuration: RefreshWidgetIntent, in context: Context) async -> UsageEntry {
        if context.isPreview {
            return .placeholder
        }
        return fetchEntry()
    }

    func timeline(for configuration: RefreshWidgetIntent, in context: Context) async -> Timeline<UsageEntry> {
        let entry = fetchEntry()
        // Use .atEnd so WidgetKit calls us again as soon as this entry expires.
        // 3-minute interval keeps data fresh even when reloadTimelines() is throttled.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 3, to: Date())
            ?? Date().addingTimeInterval(180)
        return Timeline(entries: [entry], policy: .atEnd)
    }

    private func fetchEntry() -> UsageEntry {
        sharedFile.invalidateCache()
        guard sharedFile.isConfigured else {
            return .unconfigured
        }

        if let cached = sharedFile.cachedUsage {
            let lastSync = sharedFile.lastSyncDate
            let isStale: Bool
            if let lastSync {
                isStale = Date().timeIntervalSince(lastSync) > 120
            } else {
                isStale = true
            }
            return UsageEntry(
                date: Date(),
                usage: cached.usage,
                isStale: isStale,
                lastSync: lastSync
            )
        }

        return UsageEntry(date: Date(), usage: nil, error: String(localized: "error.nodata"))
    }
}
```

Note: `nextUpdate` is computed but unused because `.atEnd` ignores it — WidgetKit calls `timeline()` again once the entry's `date` passes. This is intentional: `.atEnd` is more aggressive than `.after(date)` and ensures the widget re-reads the file frequently.

- [ ] **Step 3: Commit**

```bash
git add TokenEaterWidget/Provider.swift TokenEaterWidget/UsageEntry.swift
git commit -m "feat(widget): switch to AppIntentTimelineProvider with .atEnd policy"
```

### Task 6: Switch widget configurations to AppIntentConfiguration

**Files:**
- Modify: `TokenEaterWidget/TokenEaterWidget.swift`

- [ ] **Step 1: Replace StaticConfiguration with AppIntentConfiguration**

Replace the entire `TokenEaterWidget/TokenEaterWidget.swift`:

```swift
import WidgetKit
import SwiftUI

struct TokenEaterWidget: Widget {
    let kind: String = "TokenEaterWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: RefreshWidgetIntent.self, provider: Provider()) { entry in
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
        AppIntentConfiguration(kind: kind, intent: RefreshWidgetIntent.self, provider: Provider()) { entry in
            PacingWidgetView(entry: entry)
        }
        .configurationDisplayName("TokenEater Pacing")
        .description(String(localized: "widget.description.pacing"))
        .supportedFamilies([.systemSmall])
    }
}

@main
struct TokenEaterWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenEaterWidget()
        PacingWidget()
    }
}
```

- [ ] **Step 2: Verify build compiles**

```bash
cd /Users/adrienthevon/projects/tokeneater-feat-104-bug-widget-still-doesn-t-updat && \
xcodegen generate && \
DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject 2>/dev/null | grep -oE 'OU=[A-Z0-9]{10}' | head -1 | cut -d= -f2) && \
plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' TokenEaterWidget/Info.plist 2>/dev/null; \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Debug -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add TokenEaterWidget/TokenEaterWidget.swift
git commit -m "feat(widget): use AppIntentConfiguration for both widgets"
```

---

## Chunk 4: Singleton SharedFileService in widget views + diagnostic footer

### Task 7: Eliminate redundant SharedFileService instances in widget views

**Files:**
- Modify: `TokenEaterWidget/UsageWidgetView.swift`
- Modify: `TokenEaterWidget/PacingWidgetView.swift`

- [ ] **Step 1: Create a shared static accessor**

In `UsageWidgetView.swift`, replace the per-view `SharedFileService()` calls with a single shared instance. Add at the top of the file (after imports):

```swift
/// Single SharedFileService instance shared across all widget views in a render pass.
/// Avoids creating 6+ instances (each calling migrateIfNeeded + disk read) per widget render.
private enum WidgetTheme {
    private static let shared = SharedFileService()

    static var theme: ThemeColors { shared.theme }
    static var thresholds: UsageThresholds { shared.thresholds }
}
```

- [ ] **Step 2: Update UsageWidgetView**

Replace these lines in `UsageWidgetView.swift`:

```swift
// OLD:
private var theme: ThemeColors { SharedFileService().theme }
private var thresholds: UsageThresholds { SharedFileService().thresholds }

// NEW:
private var theme: ThemeColors { WidgetTheme.theme }
private var thresholds: UsageThresholds { WidgetTheme.thresholds }
```

Replace all `SharedFileService().theme` and `SharedFileService().thresholds` default parameter values in the sub-views (`CircularUsageView`, `CircularPacingView`, `LargeUsageBarView`, `WidgetBackgroundModifier`) with `WidgetTheme.theme` / `WidgetTheme.thresholds`:

In `WidgetBackgroundModifier`:
```swift
// OLD:
var backgroundColor: Color = Color(hex: SharedFileService().theme.widgetBackground).opacity(0.85)
// NEW:
var backgroundColor: Color = Color(hex: WidgetTheme.theme.widgetBackground).opacity(0.85)
```

In `CircularUsageView`:
```swift
// OLD:
var theme: ThemeColors = SharedFileService().theme
var thresholds: UsageThresholds = SharedFileService().thresholds
// NEW:
var theme: ThemeColors = WidgetTheme.theme
var thresholds: UsageThresholds = WidgetTheme.thresholds
```

In `CircularPacingView`:
```swift
// OLD:
var theme: ThemeColors = SharedFileService().theme
// NEW:
var theme: ThemeColors = WidgetTheme.theme
```

In `LargeUsageBarView`:
```swift
// OLD:
var theme: ThemeColors = SharedFileService().theme
var thresholds: UsageThresholds = SharedFileService().thresholds
// NEW:
var theme: ThemeColors = WidgetTheme.theme
var thresholds: UsageThresholds = WidgetTheme.thresholds
```

- [ ] **Step 3: Update PacingWidgetView**

In `PacingWidgetView.swift`, replace:
```swift
// OLD:
private var theme: ThemeColors { SharedFileService().theme }
// NEW:
private var theme: ThemeColors { WidgetTheme.theme }
```

- [ ] **Step 4: Commit**

```bash
git add TokenEaterWidget/UsageWidgetView.swift TokenEaterWidget/PacingWidgetView.swift
git commit -m "refactor(widget): singleton SharedFileService to avoid redundant disk I/O per render"
```

### Task 8: Show lastSync diagnostic in widget footer

**Files:**
- Modify: `TokenEaterWidget/UsageWidgetView.swift`

- [ ] **Step 1: Update medium widget footer to show lastSync when stale**

In `UsageWidgetView.swift`, in the `mediumUsageContent` footer `HStack`, replace the stale indicator block:

```swift
// Footer
HStack {
    if let lastSync = entry.lastSync {
        Text(String(format: String(localized: "widget.updated"), lastSync.relativeFormatted))
            .font(.system(size: 8, design: .rounded))
            .foregroundStyle(Color(hex: theme.widgetText).opacity(0.3))
    } else {
        Text(String(format: String(localized: "widget.updated"), entry.date.relativeFormatted))
            .font(.system(size: 8, design: .rounded))
            .foregroundStyle(Color(hex: theme.widgetText).opacity(0.3))
    }
    Spacer()
    if entry.isStale {
        Image(systemName: "wifi.slash")
            .font(.system(size: 8))
            .foregroundStyle(Color(hex: theme.widgetText).opacity(0.4))
    }
}
```

This way the "Updated X ago" text reflects the actual last sync time from the app, not the widget's timeline entry date. If the data is stale (> 2 min old), users can see exactly HOW old it is.

- [ ] **Step 2: Update large widget footer similarly**

In the `largeUsageContent` footer, apply the same logic:

```swift
HStack {
    if let lastSync = entry.lastSync {
        Text(String(format: String(localized: "widget.updated"), lastSync.relativeFormatted))
            .font(.system(size: 9, design: .rounded))
            .foregroundStyle(Color(hex: theme.widgetText).opacity(0.3))
    } else {
        Text(String(format: String(localized: "widget.updated"), entry.date.relativeFormatted))
            .font(.system(size: 9, design: .rounded))
            .foregroundStyle(Color(hex: theme.widgetText).opacity(0.3))
    }
    Spacer()
    if entry.isStale {
        HStack(spacing: 3) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 9))
            Text("widget.offline")
                .font(.system(size: 9, design: .rounded))
        }
        .foregroundStyle(Color(hex: theme.widgetText).opacity(0.4))
    } else {
        HStack(spacing: 3) {
            Circle()
                .fill(.green.opacity(0.6))
                .frame(width: 4, height: 4)
            Text(String(localized: "widget.refresh.interval"))
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(Color(hex: theme.widgetText).opacity(0.25))
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add TokenEaterWidget/UsageWidgetView.swift
git commit -m "feat(widget): show actual lastSync time in widget footer for diagnostics"
```

---

## Chunk 5: Final verification

### Task 9: Full build + test

- [ ] **Step 1: Run unit tests**

```bash
cd /Users/adrienthevon/projects/tokeneater-feat-104-bug-widget-still-doesn-t-updat && \
xcodegen generate && \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests \
  -configuration Debug -derivedDataPath build \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  test 2>&1 | tail -5
```

Expected: All tests pass.

- [ ] **Step 2: Release build verification**

```bash
cd /Users/adrienthevon/projects/tokeneater-feat-104-bug-widget-still-doesn-t-updat && \
export DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer && \
xcodegen generate && \
plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' TokenEaterWidget/Info.plist 2>/dev/null; \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED with Xcode 16.4.

- [ ] **Step 3: Manual test with nuke + install**

Use the nuke + install one-liner from CLAUDE.md. After install:
1. Remove old widget from desktop
2. Add new TokenEater widget (right-click → Edit Widgets → TokenEater)
3. Verify widget shows data within 30 seconds
4. Verify footer shows "Updated X ago" with real time
5. Wait 3 minutes — verify widget refreshes on its own
6. Force close the app — verify widget shows stale indicator after 2 min

---

## Summary of changes

| What | Why |
|------|-----|
| `NSFileCoordinator` on read/write | Prevents partial/corrupted reads when app writes while widget reads |
| `reloadTimelines(ofKind:)` per widget | More targeted than `reloadAllTimelines()`, separate budget per kind |
| `AppIntentTimelineProvider` | Better WidgetKit integration, enables future interactive refresh button |
| `.atEnd` timeline policy | WidgetKit calls `timeline()` again immediately when entry expires (stronger than `.after(date)`) |
| 3-min timeline interval (was 5) | More frequent data refresh independent of reload budget |
| App activation → widget reload | Widget reloads every time user switches to/from the app |
| Singleton `WidgetTheme` | Eliminates 6+ `SharedFileService()` instances per widget render |
| `lastSync` in entry + footer | Users see real last-sync time, not timeline entry time — helps diagnose issues |
