# Design: Enrich Displayed Data with Dashboard Window

**Issue:** #42
**Date:** 2026-02-26
**Branch:** `feat/42-enrich-displayed-data-with-add`

## Summary

Enrich TokenEater with additional Anthropic API data (Opus, Cowork, profile info) and create a premium dark-themed dashboard window alongside a redesigned popover. Users can choose whether clicking the menu bar icon opens the popover or the dashboard.

## Data Sources

### Existing endpoint: `GET /api/oauth/usage`

Currently decoded but **not displayed**:

| Field | Description |
|-------|-------------|
| `seven_day_opus` | Opus model 7-day usage (%) |
| `seven_day_cowork` | Cowork 7-day usage (%) |
| `seven_day_oauth_apps` | OAuth apps 7-day usage (%) |

These are optional buckets — displayed only when API returns non-nil.

### New endpoint: `GET /api/oauth/profile`

Same auth headers as `/api/oauth/usage`. Returns:

```json
{
  "account": {
    "uuid": "...",
    "full_name": "User Name",
    "display_name": "User",
    "email": "user@example.com",
    "has_claude_max": false,
    "has_claude_pro": true
  },
  "organization": {
    "uuid": "...",
    "name": "Org Name",
    "organization_type": "claude_enterprise",
    "billing_type": "stripe_subscription_contracted",
    "rate_limit_tier": "default_claude_max_5x"
  }
}
```

Fetched once at launch + on manual refresh (no polling needed).

## Architecture: NSStatusItem Approach

### Migration from MenuBarExtra

Replace `MenuBarExtra` SwiftUI scene with an AppKit-managed `NSStatusItem` for full control over click behavior.

```
TokenEaterApp (SwiftUI @main)
  private let statusBarController: StatusBarController  // NEW
  private let usageStore, themeStore, settingsStore...  // EXISTING
  Scene: Window("Settings") -> SettingsContentView      // EXISTING

StatusBarController (AppKit, NSObject)
  NSStatusItem              — menu bar icon (MenuBarRenderer)
  NSPopover                 — hosts PopoverView via NSHostingView
  NSWindow                  — hosts DashboardView via NSHostingView
  clickBehavior: enum       — .popover | .dashboard (from SettingsStore)
```

### Data flow additions

```
APIClient
  + fetchProfile(token:proxyConfig:) -> ProfileResponse   // NEW

UsageRepository
  + refreshProfile() alongside refreshUsage()             // NEW

UsageStore
  + @Published opusPct: Int
  + @Published coworkPct: Int
  + @Published oauthAppsPct: Int
  + @Published planType: PlanType (.pro, .max, .free, .unknown)
  + @Published rateLimitTier: String?
  + @Published organizationName: String?
```

### New models

```swift
struct ProfileResponse: Codable {
    let account: AccountInfo
    let organization: OrganizationInfo?
}

struct AccountInfo: Codable {
    let uuid: String
    let fullName: String
    let displayName: String
    let email: String
    let hasClaudeMax: Bool
    let hasClaudePro: Bool
}

struct OrganizationInfo: Codable {
    let uuid: String
    let name: String
    let organizationType: String
    let billingType: String
    let rateLimitTier: String
}

enum PlanType: String {
    case pro, max, free, unknown
}
```

## Visual Design: Dark Premium ("Power Station")

### Dashboard Window (~650x550px)

- Window style: `.hiddenTitleBar`, custom dark gradient background
- Background: `#0a0a1a` to `#141428`, with slow animated gradient shift (~30s loop)
- Background color shifts subtly based on pacing zone (blue/purple for chill, red/orange for hot)

**Hero element — Large ring gauge (~200px):**
- Displays Session (5h) usage as animated arc with gradient stroke (green -> orange -> red)
- Neon glow effect around the arc via `.shadow(color:radius:)`
- Orbiting particle dots (Canvas), speed based on usage level
- Large % text (32-48pt) centered with subtle depth effect

**Satellite rings (~80px each):**
- Weekly, Sonnet, Opus (+ Cowork if non-nil) displayed below the hero
- Same gradient arc style, smaller
- Hover: spring scale-up (1.02x) + glow boost + tooltip with reset time

**Models section:**
- Sonnet, Opus, Cowork as horizontal gradient progress bars
- Only shown when API returns non-nil values

**Pacing section:**
- Full-width horizontal bar with:
  - Pulsing dot for "actual" position
  - Static triangle for "ideal" position
  - Zone-colored gradient
  - Message text below
  - Reset countdown

**Header:**
- Logo + "TokenEater" + plan badge (Pro/Max) + tier + "Updated Xm ago"

**Micro-interactions:**
- Card hover: scale 1.02x + glow boost
- Value transitions: count-up animation (0 -> 78 with spring)
- Refresh: pulse animation on hero ring during loading
- Zone change: gradual background color transition

### Popover (~300px wide)

Same dark premium identity, compact layout:

- Mini hero ring (~100px) for Session with glow + reset time
- Inline mini-rings (~40px) for Weekly + Sonnet
- Compact pacing bar
- "Pro" / "Max" badge next to title
- Dashboard button (top-right) to open full window
- Static gradient background (no animation)
- No Opus/Cowork (too compact)

### Popover vs Dashboard differences

| Aspect | Popover | Dashboard |
|--------|---------|-----------|
| Session | Mini ring (~100px) | Hero ring (~200px) + particles |
| Weekly/Sonnet | Mini inline rings | Satellite rings |
| Opus/Cowork | Hidden | Shown if non-nil |
| Pacing | Compact bar | Full bar + message |
| Profile | Badge only | Badge + tier + org |
| Background | Static gradient | Animated gradient |

## Reusable Components (`Shared/Components/`)

| Component | Description | Sizes |
|-----------|-------------|-------|
| `RingGauge` | Animated circular arc with gradient stroke + glow | S(40px), M(80px), L(200px) |
| `PacingBar` | Horizontal bar with ideal/actual markers | Compact, Full |
| `MetricCard` | Glass card with ring + label + reset info | Compact, Full |
| `GlowText` | Text with subtle neon shadow | Customizable |
| `AnimatedGradient` | Slowly shifting background gradient | Window-size |
| `ParticleField` | Orbiting luminous particles (Canvas) | Dashboard only |

## Settings Changes

### New setting: Click Behavior

```
Menu Bar Click Behavior:
  - Popover (quick glance)     [default]
  - Dashboard (full window)
```

Stored in `SettingsStore.clickBehavior: ClickBehavior`.

### New metric toggles (Display tab)

- Show Opus usage (auto-disabled if unavailable)
- Show Cowork usage (auto-disabled if unavailable)

### Unchanged

Theme presets, proxy, notifications, connection — all remain as-is.

## Compatibility

- **macOS 14.0+ target**: all APIs available (Canvas, materials, Metal shaders)
- **Xcode 16.4 / Swift 6.1.x**: NSStatusItem, NSPopover, NSWindow are stable AppKit APIs. SwiftUI views use only macOS 14.0 APIs.
- **No @Observable**: continues using ObservableObject + @Published
- **Widget**: unchanged (reads from shared JSON file as before)
