# Design: App Group Shared Container (Issue #7)

## Problem

The widget extension directly accesses the macOS Keychain to read the Claude Code OAuth token. macOS displays a password prompt modal every time because:
- The Keychain item was created by Claude Code CLI (different process)
- Claude Code recreates the item on token refresh, resetting ACLs
- The widget calls `SecItemCopyMatching` twice per 15-min cycle
- macOS kills/relaunches widget extensions frequently

## Solution

Introduce an App Group (`group.com.claudeusagewidget.shared`) so only the main app touches the Keychain and API. The widget reads exclusively from the shared container.

## Approach: UserDefaults via App Group

Use `UserDefaults(suiteName: "group.com.claudeusagewidget.shared")` to share:
- OAuth token
- Cached usage data (`CachedUsage`)
- Last sync date

**Why UserDefaults over alternatives:**
- Simple API, automatic cross-process sync
- Appropriate for small data (token + JSON)
- Sandboxed in `~/Library/Group Containers/` — only group members can access
- Keychain sharing doesn't solve the ACL problem (item created by external CLI)

## SharedContainer API

```swift
enum SharedContainer {
    static let suiteName = "group.com.claudeusagewidget.shared"

    var oauthToken: String? { get/set }
    var cachedUsage: CachedUsage? { get/set }
    var lastSyncDate: Date? { get/set }
    var isConfigured: Bool { get }  // token != nil
    func clear()                    // wipe all shared data
}
```

Replaces `LocalCache` entirely.

## Data Flow

```
MAIN APP (menu bar)
  Keychain -> Token -> API Call -> UsageResponse
                |                      |
                +-> SharedContainer <--+
                    (token + cache + lastSync)
                          |
            WidgetCenter.reloadAllTimelines()

                   App Group boundary

WIDGET
  SharedContainer.cachedUsage -> UsageEntry
  SharedContainer.isConfigured -> unconfigured state
  SharedContainer.lastSyncDate -> "Last update"

  No Keychain access
  No API calls
  No ProxyIntent
```

### App refresh cycle (MenuBarViewModel, every 5 min)

1. Read Keychain (Claude Code credentials)
2. Sync token to `SharedContainer.oauthToken`
3. Call API with Bearer token
4. Write result to `SharedContainer.cachedUsage`
5. Update `SharedContainer.lastSyncDate`
6. Call `WidgetCenter.shared.reloadAllTimelines()`

### Widget timeline (Provider, every 15 min)

1. Read `SharedContainer.cachedUsage`
2. If no data -> show unconfigured state
3. Determine `isStale` from `SharedContainer.lastSyncDate`
4. Return `UsageEntry`

## Files Changed

| File | Action | Description |
|------|--------|-------------|
| `Shared/SharedContainer.swift` | Create | UserDefaults App Group wrapper |
| `Shared/UsageModels.swift` | Modify | Remove `LocalCache` enum |
| `Shared/ClaudeAPIClient.swift` | Modify | Replace LocalCache with SharedContainer |
| `ClaudeUsageApp/MenuBarView.swift` | Modify | Sync token + usage to SharedContainer |
| `ClaudeUsageApp/SettingsView.swift` | Modify | Sync token after Keychain read |
| `ClaudeUsageApp/ClaudeUsageApp.entitlements` | Modify | Add application-groups entitlement |
| `ClaudeUsageWidget/ClaudeUsageWidget.entitlements` | Modify | Add application-groups entitlement |
| `ClaudeUsageWidget/Provider.swift` | Modify | Read from SharedContainer only |
| `ClaudeUsageWidget/ProxyIntent.swift` | Delete | No network calls in widget |
| `ClaudeUsageWidget/RefreshIntent.swift` | Delete | Refresh button removed |
| `ClaudeUsageWidget/UsageWidgetView.swift` | Modify | Remove refresh button, adapt stale display |
| `project.yml` | Modify | Declare App Group on both targets |
| `README.md` | Modify | Add Security & Data Flow section |

## Decisions

- **Proxy config**: Stays in the main app's SettingsView. Widget no longer needs proxy since it doesn't make API calls.
- **Refresh button**: Removed from widget. The widget displays whatever the app last pushed.
- **Security**: Token stored in plaintext in App Group UserDefaults. Acceptable because the container is sandboxed and only accessible by the two group members. Documented in README.
