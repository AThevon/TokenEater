# Design: Theming Tab with Color Customization & Threshold Controls

**Issue:** #8
**Date:** 2026-02-23
**Status:** Approved

## Overview

Add a Theming tab in the settings to centralize color management, provide preset/custom themes, configurable usage thresholds, and a monochrome menu bar toggle.

## Architecture: Centralized ThemeManager (Approach A)

A single `ThemeManager` singleton in `Shared/` replaces all hardcoded colors. The app persists via `@AppStorage`, and syncs to `shared.json` for the widget.

```
Settings UI → ThemeManager.shared → @AppStorage (app reactivity)
                                  → SharedContainer.syncTheme() → shared.json → Widget
```

## Data Model

### ThemeColors

```swift
struct ThemeColors: Codable, Equatable {
    var gaugeNormal: String      // hex — default: "#22C55E"
    var gaugeWarning: String     // hex — default: "#F97316"
    var gaugeCritical: String    // hex — default: "#EF4444"
    var pacingChill: String      // hex — default: "#32D74B"
    var pacingOnTrack: String    // hex — default: "#0A84FF"
    var pacingHot: String        // hex — default: "#FF453A"
    var widgetBackground: String // hex — default: "#000000"
    var widgetText: String       // hex — default: "#FFFFFF"
}
```

- Default preset = current hardcoded colors (pixel-perfect backward compat)
- 4 presets: Default, Monochrome, Neon, Pastel
- 1 custom theme with per-color pickers
- Gradients: 1 color picked → auto-generate lighter variant (~20%) via `Color.lighter(by:)`

### UsageThresholds

```swift
struct UsageThresholds: Codable, Equatable {
    var warningPercent: Int   // default: 60
    var criticalPercent: Int  // default: 85
}
```

- Sliders range 10...95, step 5
- Constraint: warning < critical (auto-adjust if violated)

### Storage

- `@AppStorage("selectedPreset")` — String: "default" | "monochrome" | "neon" | "pastel" | "custom"
- `@AppStorage("customThemeJSON")` — String: JSON-encoded ThemeColors
- `@AppStorage("warningThreshold")` / `@AppStorage("criticalThreshold")` — Int
- `@AppStorage("menuBarMonochrome")` — Bool
- `shared.json` gains optional `theme: ThemeColors?` and `thresholds: UsageThresholds?` fields (nil = defaults, backward compatible)

## ThemeManager

Singleton `ObservableObject` in `Shared/ThemeManager.swift`:

- `current: ThemeColors` — resolved from preset or custom
- `gaugeColor(for pct: Int) -> Color` — uses thresholds
- `gaugeGradient(for pct: Int) -> [Color]` — color + lighter variant
- `pacingColor(for zone: PacingZone) -> Color`
- `pacingGradient(for zone: PacingZone) -> [Color]`
- `menuBarColor(for pct: Int) -> NSColor` — respects monochrome toggle
- `syncToSharedContainer()` — writes theme + thresholds to shared.json, triggers `WidgetCenter.shared.reloadAllTimelines()`

Widget reads `ThemeColors` + `UsageThresholds` from `SharedContainer` (static helpers, no singleton).

## UI: Theming Tab

New tab in SettingsView between Display and Proxy.

```
┌─────────────────────────────────────────────────┐
│  Theming                                        │
│                                                 │
│  ── Color Theme ──────────────────────────────  │
│  ○ Default  ○ Monochrome  ○ Neon  ○ Pastel     │
│  ○ Custom                                       │
│                                                 │
│  [Custom section — visible only if Custom]      │
│  ┌─────────────────────────────────────────┐    │
│  │ Gauge Normal    [■ picker]              │    │
│  │ Gauge Warning   [■ picker]              │    │
│  │ Gauge Critical  [■ picker]              │    │
│  │ Pacing Chill    [■ picker]              │    │
│  │ Pacing On Track [■ picker]              │    │
│  │ Pacing Hot      [■ picker]              │    │
│  │ Widget Bg       [■ picker]              │    │
│  │ Widget Text     [■ picker]              │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  ── Usage Thresholds ─────────────────────────  │
│  Warning   [====●=======] 60%                   │
│  Critical  [=========●==] 85%                   │
│                                                 │
│  ── Menu Bar ─────────────────────────────────  │
│  ☑ Monochrome menu bar                          │
│                                                 │
│  ── Preview ──────────────────────────────────  │
│  [● 45%]     [● 72%]      [● 90%]              │
│   Normal      Warning      Critical             │
│                                                 │
│  [Reset to Defaults]                            │
└─────────────────────────────────────────────────┘
```

- Preset → Custom: custom colors initialized from current preset
- 3 live preview gauges (normal/warning/critical states)
- Reset: confirms via alert, restores all defaults
- All changes propagate immediately to menu bar (SwiftUI reactivity) and widget (shared.json + reloadAllTimelines)

## Refactoring Scope

### Files to create

| File | Role |
|---|---|
| `Shared/ThemeColors.swift` | ThemeColors struct + presets + UsageThresholds + gradient helpers |
| `Shared/ThemeManager.swift` | Singleton ObservableObject, preset/custom/thresholds/monochrome, sync |

### Files to modify

| File | Change |
|---|---|
| `ClaudeUsageApp/SettingsView.swift` | Add Theming tab |
| `Shared/SharedContainer.swift` | Add `theme` and `thresholds` to SharedData |
| `Shared/Extensions.swift` | Add `Color.lighter(by:)` |
| `Shared/UsageModels.swift` | Replace hardcoded colors → ThemeManager |
| `Shared/UsageNotificationManager.swift` | Replace hardcoded 60/85 thresholds |
| `ClaudeUsageApp/MenuBarView.swift` | `nsColorForPct` → ThemeManager, popover gradients |
| `ClaudeUsageWidget/UsageWidgetView.swift` | Read theme/thresholds from shared.json |
| `ClaudeUsageWidget/PacingWidgetView.swift` | Read theme from shared.json |

### Unchanged

- App/widget architecture (sandbox, shared.json, entitlements)
- Existing tabs (Connection, Display, Proxy)
- Refresh flow (timer → API → shared.json → widget)
- `project.yml` (new files in Shared/, already included in both targets)
