# Design: Unified Floating Window

**Issue:** #42
**Date:** 2026-02-26
**Branch:** `feat/42-enrich-displayed-data-with-add`

## Summary

Replace the three separate windows (popover, dashboard, settings) with a single borderless floating window hosting all app functionality. The popover remains unchanged. Onboarding takes over the full window on first launch.

## Window Architecture

### NSWindow (transparent, borderless)

- Size: ~900x600, non-resizable
- `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`
- `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`
- `isMovableByWindowBackground = true`
- No titlebar buttons (close with Esc or custom button)
- Managed by `StatusBarController` (replaces current dashboard NSWindow)

### Two floating panels with gap

- **Sidebar** (~60px wide): dark background `#0a0a1a`, `cornerRadius: 16`
- **Content** (remaining ~830px): dark background with AnimatedGradient (dashboard only) or static dark (other sections), `cornerRadius: 16`
- ~4px gap between panels
- Desktop visible around and between panels
- Both panels have subtle drop shadow

### Removed

- `WindowGroup("settings")` scene — deleted entirely
- Separate dashboard NSWindow — replaced by unified window
- Native macOS settings UI — replaced by dark premium sections

## Sidebar Navigation

4 SF Symbol icons, vertically stacked, centered:

| Icon | Section | SF Symbol |
|------|---------|-----------|
| Dashboard | Rings, pacing, profile | `chart.bar.fill` |
| Display | Click behavior, menu bar, pinned metrics | `display` |
| Themes | Presets, thresholds, custom colors | `paintpalette.fill` |
| Settings | Connection, proxy, notifications, about | `gearshape.fill` |

**Behavior:**
- Active icon: glow background (theme accent color) + opacity 1.0
- Inactive: opacity 0.4
- Hover: scale 1.1x + opacity 0.7
- Tooltip on hover with section name
- Default section on launch: Dashboard

**Bottom of sidebar:**
- Quit button (`power` icon), opacity 0.3, discreet

## Dashboard Section (landscape 2-column layout)

### Left column (~55%) — Metrics

- **Hero ring** (200px): Session (fiveHour) with ParticleField, GlowText percentage, reset time
- **Satellite rings** (80px) below: Weekly, Sonnet, Opus (if available), Cowork (if available)

### Right column (~45%) — Context

- **Header**: logo + "TokenEater" + plan badge + formatted tier + "Updated Xm ago" + refresh button
- **Pacing**: PacingBar full + delta GlowText + message + reset countdown
- **Profile**: name, email, organization (if available) — small, discreet

**Background:** AnimatedGradient (shifts based on pacing zone)

**No scroll** — everything fits in landscape layout.

## Display Section

Static dark background (no AnimatedGradient). Glass cards (`ultraThinMaterial.opacity(0.15)`, `cornerRadius: 12`).

- **Click Behavior**: segmented picker "Popover" | "Dashboard"
- **Menu Bar Icon**: monochrome toggle + live preview
- **Pinned Metrics**: toggle list for pin/unpin in menu bar (Session, Weekly, Sonnet, Pacing)

## Themes Section

Same static dark + glass cards style.

- **Presets grid**: horizontal preset cards with gradient preview, active has glow outline, hover scale 1.05x
- **Alert thresholds**: two dark premium sliders (Warning, Critical) with gradient preview bar
- **Custom colors**: color pickers (when custom theme enabled)

## Settings Section

Same static dark + glass cards style.

- **Connection**: green/red status dot, truncated token display, "Re-detect" button, proxy config (host + port)
- **Notifications**: global toggle, threshold settings, last notification preview
- **About**: version + build, "Check for updates" button, GitHub link — discreet, at bottom

All compact, single page, no scroll.

## Onboarding (first launch)

Same NSWindow, but content is a **full-window onboarding flow** — no sidebar visible.

Single floating rounded panel (~900x600) with AnimatedGradient background.

### 3 steps:

1. **Welcome**: large logo + title + "Get Started" glow button
2. **Connection**: auto-detect token, scan animation (pulsing ring), success shows account info (name, plan, org), failure shows retry
3. **Ready**: recap ("Connected as Name (Org, Plan)") + "Open Dashboard" button

After completion: `hasCompletedOnboarding = true`, sidebar + dashboard appear. Onboarding never shown again (unless reset).

## API Bug Fix: PlanType

Current bug: `has_claude_max` and `has_claude_pro` are `false` for Team/Enterprise plans → derives `.free` incorrectly.

### Fix

Derive `PlanType` from both account flags AND `organization.organization_type`:

```swift
enum PlanType: String, Codable {
    case pro, max, team, enterprise, free, unknown

    init(from account: AccountInfo, organization: OrganizationInfo?) {
        if account.hasClaudeMax { self = .max }
        else if account.hasClaudePro { self = .pro }
        else if let orgType = organization?.organizationType {
            switch orgType {
            case "claude_team": self = .team
            case "claude_enterprise": self = .enterprise
            default: self = .free
            }
        } else { self = .free }
    }
}
```

### Rate limit tier formatting

`"default_claude_max_5x"` → `"Max 5x"` (strip prefix, capitalize, replace underscores with spaces).

## Popover

**Unchanged.** Keeps current dark premium design with mini rings + pacing.

## Compatibility

- macOS 14.0+ target
- Xcode 16.4 / Swift 6.1.x
- No @Observable (ObservableObject + @Published)
- NSWindow transparent background APIs are stable since macOS 10.0+
