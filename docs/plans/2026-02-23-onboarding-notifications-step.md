# Onboarding Notifications Step — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a 4th onboarding step that requests notification permission with a mockup preview and test button.

**Architecture:** Insert a `NotificationStep` between Prerequisites and Connection. The ViewModel gains a `NotificationStatus` enum and two methods (`checkNotificationStatus`, `requestNotifications`). The step reuses `UsageNotificationManager` — no new services.

**Tech Stack:** SwiftUI, UserNotifications (UNUserNotificationCenter), NSWorkspace (deep link)

---

### Task 1: Add NotificationStatus enum and ViewModel logic

**Files:**
- Modify: `ClaudeUsageApp/OnboardingViewModel.swift`

**Step 1: Add the notifications case to OnboardingStep**

Change the enum to 4 cases:

```swift
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case prerequisites = 1
    case notifications = 2
    case connection = 3
}
```

**Step 2: Add NotificationStatus enum**

Add above `OnboardingViewModel` class:

```swift
enum NotificationStatus {
    case unknown
    case authorized
    case denied
    case notYetAsked
}
```

**Step 3: Add published property and methods to OnboardingViewModel**

Add to the class:

```swift
@Published var notificationStatus: NotificationStatus = .unknown

func checkNotificationStatus() {
    Task {
        let status = await UsageNotificationManager.checkAuthorizationStatus()
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
    UsageNotificationManager.requestPermission()
    // Re-check after a short delay (system dialog is async)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.checkNotificationStatus()
    }
}
```

Also add `import UserNotifications` at the top of the file.

**Step 4: Build to verify**

Run: `xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Release -derivedDataPath build DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject 2>/dev/null | grep -oE 'OU=[A-Z0-9]{10}' | head -1 | cut -d= -f2) build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add ClaudeUsageApp/OnboardingViewModel.swift
git commit -m "feat(onboarding): add notifications step to stepper enum and ViewModel"
```

---

### Task 2: Add localization keys (EN + FR)

**Files:**
- Modify: `Shared/en.lproj/Localizable.strings`
- Modify: `Shared/fr.lproj/Localizable.strings`

**Step 1: Add EN keys**

Add after the `/* Onboarding - Prerequisites */` section, before `/* Onboarding - Connection */`:

```
/* Onboarding - Notifications */
"onboarding.notif.title" = "Stay in the loop";
"onboarding.notif.simple" = "Get notified when your usage hits warning or critical levels.";
"onboarding.notif.detailed" = "TokenEater sends local notifications when your usage crosses configurable thresholds (default: 60% warning, 85% critical). Only transitions trigger alerts — no spam.";
"onboarding.notif.enable" = "Enable Notifications";
"onboarding.notif.enabled" = "Notifications enabled!";
"onboarding.notif.test" = "Send a test";
"onboarding.notif.denied.hint" = "No worries — you can enable them later in System Settings.";
"onboarding.notif.open.settings" = "Open Settings";
"onboarding.notif.skip.hint" = "You'll miss threshold alerts";
"onboarding.notif.mockup.title" = "⚠️ Session 5h — 72%";
"onboarding.notif.mockup.body" = "You're past 60%% — consider slowing down";
```

**Step 2: Add FR keys**

Add in the same position in the FR file:

```
/* Onboarding - Notifications */
"onboarding.notif.title" = "Restez informé";
"onboarding.notif.simple" = "Recevez une notification quand votre usage atteint les seuils d'alerte.";
"onboarding.notif.detailed" = "TokenEater envoie des notifications locales quand votre usage franchit les seuils configurables (60% alerte, 85% critique par défaut). Seules les transitions déclenchent une alerte — pas de spam.";
"onboarding.notif.enable" = "Activer les notifications";
"onboarding.notif.enabled" = "Notifications activées !";
"onboarding.notif.test" = "Envoyer un test";
"onboarding.notif.denied.hint" = "Pas de souci — vous pourrez les activer plus tard dans les Réglages Système.";
"onboarding.notif.open.settings" = "Ouvrir les réglages";
"onboarding.notif.skip.hint" = "Vous manquerez les alertes de seuil";
"onboarding.notif.mockup.title" = "⚠️ Session 5h — 72%";
"onboarding.notif.mockup.body" = "Tu dépasses 60%% — lève le pied";
```

Note: `%%` is the escape for literal `%` in `.strings` files.

**Step 3: Commit**

```bash
git add Shared/en.lproj/Localizable.strings Shared/fr.lproj/Localizable.strings
git commit -m "feat(onboarding): add notification step localization keys (EN + FR)"
```

---

### Task 3: Create NotificationStep view

**Files:**
- Create: `ClaudeUsageApp/OnboardingSteps/NotificationStep.swift`

**Step 1: Create the full view**

Create `ClaudeUsageApp/OnboardingSteps/NotificationStep.swift` with this content:

```swift
import SwiftUI

struct NotificationStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Mode toggle (same as PrerequisiteStep)
            modeToggle

            // Bell icon
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            // Title
            Text("onboarding.notif.title")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            // Description (simple/detailed)
            Group {
                if viewModel.isDetailedMode {
                    Text("onboarding.notif.detailed")
                } else {
                    Text("onboarding.notif.simple")
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 380)

            // Notification mockup
            notificationMockup

            // Action area (depends on authorization state)
            actionArea

            Spacer()

            // Navigation
            bottomBar
        }
        .padding(32)
        .onAppear {
            viewModel.checkNotificationStatus()
        }
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        Picker("", selection: $viewModel.isDetailedMode) {
            Text("onboarding.mode.simple").tag(false)
            Text("onboarding.mode.detailed").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
    }

    // MARK: - Notification Mockup

    private var notificationMockup: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text("onboarding.notif.mockup.title")
                    .font(.system(size: 12, weight: .semibold))
                Text("onboarding.notif.mockup.body")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .frame(maxWidth: 340)
    }

    // MARK: - Action Area

    @ViewBuilder
    private var actionArea: some View {
        switch viewModel.notificationStatus {
        case .unknown:
            ProgressView()
                .controlSize(.small)

        case .notYetAsked:
            Button {
                viewModel.requestNotifications()
            } label: {
                Label("onboarding.notif.enable", systemImage: "bell.badge")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .authorized:
            VStack(spacing: 12) {
                Label {
                    Text("onboarding.notif.enabled")
                        .font(.system(size: 15, weight: .medium))
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Button {
                    UsageNotificationManager.sendTest()
                } label: {
                    Label("onboarding.notif.test", systemImage: "paperplane")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

        case .denied:
            VStack(spacing: 12) {
                Text("onboarding.notif.denied.hint")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)

                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("onboarding.notif.open.settings", systemImage: "gear")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button {
                viewModel.goBack()
            } label: {
                Text("onboarding.back")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Button {
                    viewModel.goNext()
                } label: {
                    Text("onboarding.continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                // Soft-gate hint
                if viewModel.notificationStatus != .authorized {
                    Text("onboarding.notif.skip.hint")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
```

**Step 2: Build to verify**

Run the build command from Task 1 Step 4.
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ClaudeUsageApp/OnboardingSteps/NotificationStep.swift
git commit -m "feat(onboarding): create NotificationStep view with mockup and permission flow"
```

---

### Task 4: Wire NotificationStep into the onboarding container

**Files:**
- Modify: `ClaudeUsageApp/OnboardingView.swift`

**Step 1: Add the notifications case to the switch**

In `OnboardingView.swift`, add the `case .notifications` in the Group switch:

```swift
Group {
    switch viewModel.currentStep {
    case .welcome:
        WelcomeStep(viewModel: viewModel)
    case .prerequisites:
        PrerequisiteStep(viewModel: viewModel)
    case .notifications:
        NotificationStep(viewModel: viewModel)
    case .connection:
        ConnectionStep(viewModel: viewModel)
    }
}
```

**Step 2: Build + full nuke + install**

Run the full build+nuke+install command from CLAUDE.md to test the complete flow end-to-end.

**Step 3: Manual verification checklist**

- [ ] Page dots show 4 dots (not 3)
- [ ] Step 3 shows bell icon + mockup notification
- [ ] "Enable Notifications" button triggers macOS permission dialog
- [ ] After granting: green checkmark + "Send a test" button works
- [ ] After denying: "Open Settings" button opens System Settings
- [ ] Soft-gate hint appears under Continue when not authorized
- [ ] Continue works regardless of notification status
- [ ] Back returns to Prerequisites
- [ ] Connection step (now step 4) still works as before

**Step 4: Commit**

```bash
git add ClaudeUsageApp/OnboardingView.swift
git commit -m "feat(onboarding): wire NotificationStep into stepper container"
```
