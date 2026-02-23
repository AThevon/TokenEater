# Onboarding Notifications Step — Design

## Context

TokenEater has a 3-step onboarding stepper (Welcome → Prerequisites → Connection). The app already has a full notification system (`UsageNotificationManager`) with threshold-based alerts (orange/red/green), but notification permission is never explicitly requested during onboarding.

## Goal

Add a 4th onboarding step for notifications between Prerequisites and Connection:
**Welcome → Prerequisites → Notifications → Connection**

## Design

### Position & Navigation

- New enum case: `OnboardingStep.notifications = 2` (connection becomes `= 3`)
- Same navigation pattern: Back + Continue buttons, page dots auto-update via `CaseIterable`
- Continue is **always enabled** (soft-gate, not hard-gate)

### Notification Authorization State

New enum in `OnboardingViewModel`:

```swift
enum NotificationStatus {
    case unknown    // Haven't checked yet
    case authorized // Permission granted
    case denied     // Explicitly denied in System Settings
    case notYetAsked // Never prompted
}
```

ViewModel gets:
- `@Published var notificationStatus: NotificationStatus = .unknown`
- `func checkNotificationStatus()` — async check via `UNUserNotificationCenter`
- `func requestNotifications()` — calls `UsageNotificationManager.requestPermission()` then re-checks status

### Screen Layout (NotificationStep.swift)

Top to bottom:

1. **Bell icon** — `bell.badge.fill`, 48pt, blue
2. **Title** — "Stay in the loop"
3. **Description** — simple/detailed mode variants explaining what notifs do
4. **Mockup notification** — fake macOS banner in SwiftUI:
   - Rounded rect with `.ultraThinMaterial`
   - App icon (16px) + "TokenEater" title + example body "Session 5h — 72% / You're past 60%..."
   - Orange accent to show a warning-level notification
5. **Action area** (depends on state):
   - `notYetAsked` → "Enable Notifications" button (`.borderedProminent`)
   - `authorized` → green checkmark + "Send a test" button
   - `denied` → hint text "No worries — you can enable them later" + "Open Settings" button → deep link to `x-apple.systempreferences:com.apple.Notifications-Settings.extension`
6. **Soft-gate hint** (only if not authorized) — small secondary text under Continue: "You'll miss threshold alerts"

### Localization Keys

```
onboarding.notif.title = "Stay in the loop"
onboarding.notif.simple = "Get notified when your usage hits warning or critical levels."
onboarding.notif.detailed = "TokenEater sends local notifications via UNUserNotificationCenter when your usage crosses configurable thresholds (default: 60% warning, 85% critical). Only transitions trigger alerts — no spam."
onboarding.notif.enable = "Enable Notifications"
onboarding.notif.enabled = "Notifications enabled!"
onboarding.notif.test = "Send a test"
onboarding.notif.denied.hint = "No worries — you can enable them later in System Settings."
onboarding.notif.open.settings = "Open Settings"
onboarding.notif.skip.hint = "You'll miss threshold alerts"
onboarding.notif.mockup.title = "Session 5h — 72%"
onboarding.notif.mockup.body = "You're past 60% — consider slowing down"
```

### Deep Link to System Settings

```swift
NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
```

### What We Reuse (No New Services)

- `UsageNotificationManager.requestPermission()` — existing
- `UsageNotificationManager.checkAuthorizationStatus()` — existing
- `UsageNotificationManager.sendTest()` — existing
- Mode toggle (simple/detailed) — existing in ViewModel
- Navigation (goNext/goBack) — existing
- Visual patterns (icon + title + description + material card) — consistent with other steps

### Files to Create/Modify

| File | Action |
|------|--------|
| `ClaudeUsageApp/OnboardingSteps/NotificationStep.swift` | **Create** — new step view |
| `ClaudeUsageApp/OnboardingViewModel.swift` | **Modify** — add `notifications` case, `NotificationStatus`, methods |
| `ClaudeUsageApp/OnboardingView.swift` | **Modify** — add `case .notifications` in switch |
| `Shared/en.lproj/Localizable.strings` | **Modify** — add EN keys |
| `Shared/fr.lproj/Localizable.strings` | **Modify** — add FR keys |
