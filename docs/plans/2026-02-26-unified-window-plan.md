# Unified Floating Window Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the 3 separate windows (popover, dashboard, settings) with a single borderless floating window containing sidebar navigation, and fix API plan type detection.

**Architecture:** A transparent NSWindow hosts a SwiftUI `MainAppView` with icon sidebar (60px) + content panel. Both panels are rounded floating shapes with a gap between them. Onboarding takes over the full window on first launch. The popover is unchanged.

**Tech Stack:** SwiftUI, AppKit (NSWindow, NSHostingController), Combine, Swift Testing

---

## Context

**Codebase conventions:**
- `ObservableObject` + `@Published` (NO `@Observable`)
- `@EnvironmentObject` for store injection
- `@State` local + `.onChange` for bindings to avoid Release build loops
- Protocol-based services with mocks in `TokenEaterTests/Mocks/`
- Swift Testing framework (`import Testing`, `@Test`, `#expect`)
- `@MainActor` on all stores and controllers
- Tests: `xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test`
- Build: `export DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer` before xcodebuild
- Generate project: `xcodegen generate` before build/test
- Localization: keys in `Shared/en.lproj/Localizable.strings` and `Shared/fr.lproj/Localizable.strings`

**API response for profile (real data):**
```json
{
  "account": { "has_claude_max": false, "has_claude_pro": false, ... },
  "organization": { "organization_type": "claude_team", "rate_limit_tier": "default_claude_max_5x", ... }
}
```
Team/Enterprise plans have `has_claude_max: false` + `has_claude_pro: false` — plan must be derived from `organization_type`.

---

### Task 1: Fix PlanType enum to support Team/Enterprise

**Files:**
- Modify: `Shared/Models/ProfileModels.swift`
- Modify: `Shared/Stores/UsageStore.swift:141-151` (refreshProfile)
- Modify: `TokenEaterTests/ProfileModelTests.swift`
- Modify: `TokenEaterTests/Fixtures/ProfileResponse+Fixture.swift`

**Step 1: Update tests for new PlanType cases**

In `TokenEaterTests/ProfileModelTests.swift`, add tests:

```swift
@Test func planTypeDerivedFromOrganizationType_team() {
    let account = AccountInfo(
        uuid: "1", fullName: "Test", displayName: "T",
        email: "t@t.com", hasClaudeMax: false, hasClaudePro: false
    )
    let org = OrganizationInfo(
        uuid: "1", name: "Org", organizationType: "claude_team",
        billingType: "stripe", rateLimitTier: "default"
    )
    let planType = PlanType(from: account, organization: org)
    #expect(planType == .team)
}

@Test func planTypeDerivedFromOrganizationType_enterprise() {
    let account = AccountInfo(
        uuid: "1", fullName: "Test", displayName: "T",
        email: "t@t.com", hasClaudeMax: false, hasClaudePro: false
    )
    let org = OrganizationInfo(
        uuid: "1", name: "Org", organizationType: "claude_enterprise",
        billingType: "stripe", rateLimitTier: "default"
    )
    let planType = PlanType(from: account, organization: org)
    #expect(planType == .enterprise)
}

@Test func planTypeMaxTakesPrecedenceOverOrg() {
    let account = AccountInfo(
        uuid: "1", fullName: "Test", displayName: "T",
        email: "t@t.com", hasClaudeMax: true, hasClaudePro: false
    )
    let org = OrganizationInfo(
        uuid: "1", name: "Org", organizationType: "claude_team",
        billingType: "stripe", rateLimitTier: "default"
    )
    let planType = PlanType(from: account, organization: org)
    #expect(planType == .max)
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild ... test 2>&1 | tail -20`
Expected: FAIL — `PlanType` init doesn't accept `organization` parameter, `.team` and `.enterprise` don't exist.

**Step 3: Update PlanType enum**

In `Shared/Models/ProfileModels.swift`, replace the `PlanType` enum:

```swift
enum PlanType: String, Codable {
    case pro, max, team, enterprise, free, unknown

    init(from account: AccountInfo, organization: OrganizationInfo? = nil) {
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

Update `UsageStore.refreshProfile()` to pass organization:

```swift
planType = PlanType(from: profile.account, organization: profile.organization)
```

Update existing tests that use `PlanType(from:)` with single argument — add `organization: nil` or keep using the default.

**Step 4: Run tests to verify they pass**

Expected: ALL PASS

**Step 5: Add rate limit tier formatting helper**

In `Shared/Models/ProfileModels.swift`, add an extension:

```swift
extension String {
    /// Formats "default_claude_max_5x" → "Max 5x"
    var formattedRateLimitTier: String {
        self.replacingOccurrences(of: "default_claude_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
```

Update `DashboardView.swift` header to use `.formattedRateLimitTier`:

```swift
if let tier = usageStore.rateLimitTier {
    Text(tier.formattedRateLimitTier)
```

**Step 6: Run tests, commit**

```bash
git add Shared/Models/ProfileModels.swift Shared/Stores/UsageStore.swift TokenEaterTests/ProfileModelTests.swift TokenEaterApp/DashboardView.swift
git commit -m "fix(models): derive PlanType from organization_type for Team/Enterprise plans"
```

---

### Task 2: Create AppSection enum and MainAppView shell

**Files:**
- Create: `Shared/Models/AppSection.swift`
- Create: `TokenEaterApp/MainAppView.swift`
- Create: `TokenEaterApp/AppSidebar.swift`

**Step 1: Create AppSection enum**

Create `Shared/Models/AppSection.swift`:

```swift
import Foundation

enum AppSection: String, CaseIterable {
    case dashboard
    case display
    case themes
    case settings
}
```

**Step 2: Create AppSidebar**

Create `TokenEaterApp/AppSidebar.swift`:

```swift
import SwiftUI

struct AppSidebar: View {
    @Binding var selection: AppSection

    private let items: [(section: AppSection, icon: String)] = [
        (.dashboard, "chart.bar.fill"),
        (.display, "display"),
        (.themes, "paintpalette.fill"),
        (.settings, "gearshape.fill"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 8)

            ForEach(items, id: \.section) { item in
                sidebarButton(section: item.section, icon: item.icon)
            }

            Spacer()

            // Quit button
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text(String(localized: "menubar.quit")))

            Spacer().frame(height: 8)
        }
        .frame(width: 60)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.04, green: 0.04, blue: 0.10))
        )
    }

    private func sidebarButton(section: AppSection, icon: String) -> some View {
        let isActive = selection == section
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = section
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(isActive ? 1.0 : 0.4))
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isActive ? Color.white.opacity(0.1) : .clear)
                )
                .scaleEffect(isActive ? 1.0 : 0.95)
        }
        .buttonStyle(.plain)
        .help(Text(sidebarLabel(for: section)))
    }

    private func sidebarLabel(for section: AppSection) -> String {
        switch section {
        case .dashboard: String(localized: "sidebar.dashboard")
        case .display: String(localized: "sidebar.display")
        case .themes: String(localized: "sidebar.themes")
        case .settings: String(localized: "sidebar.settings")
        }
    }
}
```

**Step 3: Create MainAppView shell**

Create `TokenEaterApp/MainAppView.swift`:

```swift
import SwiftUI

struct MainAppView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var updateStore: UpdateStore

    @State private var selectedSection: AppSection = .dashboard

    var body: some View {
        if settingsStore.hasCompletedOnboarding {
            mainContent
        } else {
            onboardingContent
        }
    }

    private var mainContent: some View {
        HStack(spacing: 4) {
            AppSidebar(selection: $selectedSection)

            Group {
                switch selectedSection {
                case .dashboard:
                    DashboardView()
                case .display:
                    DisplaySectionView()
                case .themes:
                    ThemesSectionView()
                case .settings:
                    SettingsSectionView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.04, green: 0.04, blue: 0.10))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(4)
        .task {
            usageStore.proxyConfig = settingsStore.proxyConfig
            usageStore.startAutoRefresh(thresholds: themeStore.thresholds)
            themeStore.syncToSharedFile()
            updateStore.startAutoCheck()
        }
    }

    private var onboardingContent: some View {
        OnboardingView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.04, green: 0.04, blue: 0.10))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(4)
    }
}
```

**Step 4: Add localization keys**

Add to both `en.lproj/Localizable.strings` and `fr.lproj/Localizable.strings`:

English:
```
"sidebar.dashboard" = "Dashboard";
"sidebar.display" = "Display";
"sidebar.themes" = "Themes";
"sidebar.settings" = "Settings";
```

French:
```
"sidebar.dashboard" = "Tableau de bord";
"sidebar.display" = "Affichage";
"sidebar.themes" = "Thèmes";
"sidebar.settings" = "Réglages";
```

**Step 5: Create stub views for sections not yet implemented**

Create placeholder views that will be replaced in later tasks. Add to `MainAppView.swift` temporarily (or create separate files):

```swift
struct DisplaySectionView: View {
    var body: some View {
        Text("Display — coming soon")
            .foregroundStyle(.white.opacity(0.5))
    }
}

struct ThemesSectionView: View {
    var body: some View {
        Text("Themes — coming soon")
            .foregroundStyle(.white.opacity(0.5))
    }
}

struct SettingsSectionView: View {
    var body: some View {
        Text("Settings — coming soon")
            .foregroundStyle(.white.opacity(0.5))
    }
}
```

**Step 6: Run tests (should still pass — no existing code changed), commit**

```bash
git add Shared/Models/AppSection.swift TokenEaterApp/MainAppView.swift TokenEaterApp/AppSidebar.swift Shared/en.lproj/Localizable.strings Shared/fr.lproj/Localizable.strings
git commit -m "feat(ui): create MainAppView shell with sidebar navigation"
```

---

### Task 3: Refactor StatusBarController for transparent borderless window

**Files:**
- Modify: `TokenEaterApp/StatusBarController.swift`
- Modify: `TokenEaterApp/TokenEaterApp.swift`

**Step 1: Refactor StatusBarController.showDashboard()**

Replace the `showDashboard()` method to create a transparent borderless window hosting `MainAppView`:

```swift
func showDashboard() {
    popover.performClose(nil)
    stopEventMonitor()

    if let window = dashboardWindow {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let appView = MainAppView()
        .environmentObject(usageStore)
        .environmentObject(themeStore)
        .environmentObject(settingsStore)
        .environmentObject(updateStore)

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
        styleMask: [.titled, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = true
    window.contentViewController = NSHostingController(rootView: appView)
    window.center()
    window.setFrameAutosaveName("MainWindow")
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    self.dashboardWindow = window
}
```

**Step 2: Remove WindowGroup("settings") from TokenEaterApp.swift**

Replace `TokenEaterApp.body` to remove the settings WindowGroup entirely. The `.task` logic that was in `SettingsContentView` is now in `MainAppView`:

```swift
@main
struct TokenEaterApp: App {
    private let usageStore = UsageStore()
    private let themeStore = ThemeStore()
    private let settingsStore = SettingsStore()
    private let updateStore = UpdateStore()

    private let statusBarController: StatusBarController

    init() {
        NotificationService().setupDelegate()
        statusBarController = StatusBarController(
            usageStore: usageStore,
            themeStore: themeStore,
            settingsStore: settingsStore,
            updateStore: updateStore
        )
    }

    var body: some Scene {
        // Empty scene — all UI is managed by StatusBarController
        Settings {
            EmptyView()
        }
    }
}
```

Note: We need at least one `Scene` in the body. `Settings { EmptyView() }` is a hidden scene that satisfies the requirement.

**Step 3: Auto-open dashboard on launch**

In `StatusBarController.init()`, after setup, open the main window automatically:

```swift
super.init()
setupStatusItem()
setupPopover()
observeStoreChanges()
observeDashboardRequest()

// Auto-open main window on launch
DispatchQueue.main.async { [weak self] in
    self?.showDashboard()
}
```

**Step 4: Update the "settings" button in the popover**

In `MenuBarView.swift`, find the settings action button and change it to open the dashboard instead of the settings window:

```swift
actionButton(icon: "gear", label: String(localized: "menubar.settings")) {
    NotificationCenter.default.post(name: .openDashboard, object: nil)
}
```

**Step 5: Run tests, build Release, commit**

```bash
git add TokenEaterApp/StatusBarController.swift TokenEaterApp/TokenEaterApp.swift TokenEaterApp/MenuBarView.swift
git commit -m "refactor(app): replace settings WindowGroup with transparent borderless main window"
```

---

### Task 4: Redesign DashboardView in 2-column landscape

**Files:**
- Modify: `TokenEaterApp/DashboardView.swift`

**Step 1: Rewrite DashboardView for landscape 2-column layout**

Replace the entire `DashboardView` content. The view now lives inside the content panel of `MainAppView` (no more `frame(width: 650, height: 550)`):

```swift
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        ZStack {
            AnimatedGradient(baseColors: backgroundColors)

            HStack(spacing: 0) {
                // Left column — Metrics
                leftColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Right column — Context
                rightColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(24)
        }
        .onAppear {
            if settingsStore.hasCompletedOnboarding {
                if usageStore.lastUpdate == nil {
                    usageStore.proxyConfig = settingsStore.proxyConfig
                    usageStore.reloadConfig(thresholds: themeStore.thresholds)
                    usageStore.startAutoRefresh(thresholds: themeStore.thresholds)
                } else {
                    Task { await usageStore.refresh(thresholds: themeStore.thresholds) }
                }
            }
        }
    }

    // MARK: - Left Column

    private var leftColumn: some View {
        VStack(spacing: 24) {
            Spacer()

            // Hero ring
            ZStack {
                ParticleField(
                    particleCount: 25,
                    speed: Double(usageStore.fiveHourPct) / 100.0,
                    color: gaugeColor(for: usageStore.fiveHourPct),
                    radius: 130
                )
                .frame(width: 280, height: 280)

                RingGauge(
                    percentage: usageStore.fiveHourPct,
                    gradient: gaugeGradient(for: usageStore.fiveHourPct),
                    size: 200,
                    glowColor: gaugeColor(for: usageStore.fiveHourPct),
                    glowRadius: 8
                )
                .overlay {
                    VStack(spacing: 2) {
                        GlowText(
                            "\(usageStore.fiveHourPct)%",
                            font: .system(size: 42, weight: .black, design: .rounded),
                            color: gaugeColor(for: usageStore.fiveHourPct),
                            glowRadius: 6
                        )
                        Text(String(localized: "metric.session"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        if !usageStore.fiveHourReset.isEmpty {
                            Text(String(format: String(localized: "metric.reset"), usageStore.fiveHourReset))
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }
            }

            // Satellite rings
            HStack(spacing: 20) {
                satelliteRing(label: String(localized: "metric.weekly"), pct: usageStore.sevenDayPct)
                satelliteRing(label: String(localized: "metric.sonnet"), pct: usageStore.sonnetPct)
                if usageStore.hasOpus {
                    satelliteRing(label: "Opus", pct: usageStore.opusPct)
                }
                if usageStore.hasCowork {
                    satelliteRing(label: "Cowork", pct: usageStore.coworkPct)
                }
            }

            Spacer()
        }
    }

    // MARK: - Right Column

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            dashboardHeader

            Spacer()

            // Profile
            if usageStore.planType != .unknown {
                profileCard
            }

            // Pacing
            if let pacing = usageStore.pacingResult {
                pacingCard(pacing: pacing)
            }

            Spacer()
        }
    }

    // MARK: - Header

    private var dashboardHeader: some View {
        HStack {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Text("TokenEater")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            if usageStore.planType != .unknown {
                Text(usageStore.planType.displayLabel)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(usageStore.planType.badgeColor.opacity(0.3))
                    .clipShape(Capsule())
            }
            Spacer()
            if usageStore.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }
            if let date = usageStore.lastUpdate {
                Text(String(format: String(localized: "menubar.updated"), date.formatted(.relative(presentation: .named))))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }
            Button {
                Task { await usageStore.refresh(thresholds: themeStore.thresholds) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let tier = usageStore.rateLimitTier {
                HStack(spacing: 6) {
                    Text(String(localized: "dashboard.tier"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(tier.formattedRateLimitTier)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            if let org = usageStore.organizationName {
                HStack(spacing: 6) {
                    Text(String(localized: "dashboard.org"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(org)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Pacing Card

    private func pacingCard(pacing: PacingResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "pacing.label"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                let sign = pacing.delta >= 0 ? "+" : ""
                GlowText(
                    "\(sign)\(Int(pacing.delta))%",
                    font: .system(size: 20, weight: .black, design: .rounded),
                    color: themeStore.current.pacingColor(for: pacing.zone),
                    glowRadius: 4
                )
            }
            PacingBar(
                actual: pacing.actualUsage,
                expected: pacing.expectedUsage,
                zone: pacing.zone,
                gradient: themeStore.current.pacingGradient(for: pacing.zone, startPoint: .leading, endPoint: .trailing)
            )
            Text(pacing.message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(themeStore.current.pacingColor(for: pacing.zone).opacity(0.8))
            if let resetDate = pacing.resetDate {
                let diff = resetDate.timeIntervalSinceNow
                if diff > 0 {
                    let days = Int(diff) / 86400
                    let hours = (Int(diff) % 86400) / 3600
                    let resetText = days > 0
                        ? String(format: String(localized: "dashboard.pacing.reset.days"), days, hours)
                        : String(format: String(localized: "dashboard.pacing.reset.hours"), hours)
                    Text(resetText)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Satellite Ring

    private func satelliteRing(label: String, pct: Int) -> some View {
        VStack(spacing: 6) {
            RingGauge(
                percentage: pct,
                gradient: gaugeGradient(for: pct),
                size: 80,
                glowColor: gaugeColor(for: pct),
                glowRadius: 4
            )
            .overlay {
                GlowText(
                    "\(pct)%",
                    font: .system(size: 18, weight: .black, design: .rounded),
                    color: gaugeColor(for: pct),
                    glowRadius: 3
                )
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Helpers

    private var backgroundColors: [Color] {
        switch usageStore.pacingZone {
        case .chill: [Color(red: 0.04, green: 0.04, blue: 0.10), Color(red: 0.04, green: 0.08, blue: 0.16)]
        case .onTrack: [Color(red: 0.04, green: 0.04, blue: 0.10), Color(red: 0.08, green: 0.08, blue: 0.16)]
        case .hot: [Color(red: 0.10, green: 0.04, blue: 0.04), Color(red: 0.16, green: 0.08, blue: 0.08)]
        }
    }

    private func gaugeColor(for pct: Int) -> Color {
        themeStore.current.gaugeColor(for: Double(pct), thresholds: themeStore.thresholds)
    }

    private func gaugeGradient(for pct: Int) -> LinearGradient {
        themeStore.current.gaugeGradient(for: Double(pct), thresholds: themeStore.thresholds, startPoint: .leading, endPoint: .trailing)
    }
}
```

Also add `displayLabel` and `badgeColor` to `PlanType`:

```swift
extension PlanType {
    var displayLabel: String {
        switch self {
        case .pro: "PRO"
        case .max: "MAX"
        case .team: "TEAM"
        case .enterprise: "ENTERPRISE"
        case .free: "FREE"
        case .unknown: ""
        }
    }

    var badgeColor: Color {
        switch self {
        case .max: .purple
        case .pro: .blue
        case .team: .teal
        case .enterprise: .orange
        case .free: .gray
        case .unknown: .clear
        }
    }
}
```

Add localization keys:

English:
```
"dashboard.tier" = "Tier";
"dashboard.org" = "Organization";
```

French:
```
"dashboard.tier" = "Tier";
"dashboard.org" = "Organisation";
```

**Step 2: Run tests, build Release, commit**

```bash
git add TokenEaterApp/DashboardView.swift Shared/Models/ProfileModels.swift Shared/en.lproj/Localizable.strings Shared/fr.lproj/Localizable.strings
git commit -m "feat(ui): redesign DashboardView in 2-column landscape layout"
```

---

### Task 5: Build DisplaySectionView

**Files:**
- Create: `TokenEaterApp/DisplaySectionView.swift`
- Remove stub from `MainAppView.swift`

**Step 1: Create DisplaySectionView**

Port all logic from old `DisplayTab` with dark premium styling. Replace `Form`/`Section` with custom glass cards:

```swift
import SwiftUI

struct DisplaySectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var localClickBehavior: ClickBehavior = .popover
    @State private var showFiveHour = true
    @State private var showSevenDay = true
    @State private var showSonnet = false
    @State private var showPacing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(String(localized: "sidebar.display"))

            // Click Behavior
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.clickbehavior"))
                    Picker("", selection: $localClickBehavior) {
                        Text(String(localized: "settings.clickbehavior.popover")).tag(ClickBehavior.popover)
                        Text(String(localized: "settings.clickbehavior.dashboard")).tag(ClickBehavior.dashboard)
                    }
                    .pickerStyle(.segmented)
                    .colorMultiply(.white)
                    .onChange(of: localClickBehavior) { _, newValue in
                        settingsStore.clickBehavior = newValue
                    }
                }
            }

            // Menu Bar
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.menubar.title"))
                    darkToggle(String(localized: "settings.menubar.toggle"), isOn: $settingsStore.showMenuBar)
                    darkToggle(String(localized: "settings.theme.monochrome"), isOn: $themeStore.menuBarMonochrome)
                }
            }

            // Pinned Metrics
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.metrics.pinned"))
                    darkToggle(String(localized: "metric.session"), isOn: $showFiveHour)
                    darkToggle(String(localized: "metric.weekly"), isOn: $showSevenDay)
                    darkToggle(String(localized: "metric.sonnet"), isOn: $showSonnet)
                    darkToggle(String(localized: "pacing.label"), isOn: $showPacing)
                    if showPacing {
                        PacingDisplayPicker(selection: $settingsStore.pacingDisplayMode)
                            .padding(.leading, 8)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .task {
            localClickBehavior = settingsStore.clickBehavior
            showFiveHour = settingsStore.pinnedMetrics.contains(.fiveHour)
            showSevenDay = settingsStore.pinnedMetrics.contains(.sevenDay)
            showSonnet = settingsStore.pinnedMetrics.contains(.sonnet)
            showPacing = settingsStore.pinnedMetrics.contains(.pacing)
        }
        .onChange(of: showFiveHour) { _, new in syncMetric(.fiveHour, on: new, revert: { showFiveHour = true }) }
        .onChange(of: showSevenDay) { _, new in syncMetric(.sevenDay, on: new, revert: { showSevenDay = true }) }
        .onChange(of: showSonnet) { _, new in syncMetric(.sonnet, on: new, revert: { showSonnet = true }) }
        .onChange(of: showPacing) { _, new in
            withAnimation(.easeInOut(duration: 0.2)) { syncMetric(.pacing, on: new, revert: { showPacing = true }) }
        }
        .onChange(of: settingsStore.pinnedMetrics) { _, metrics in
            if showFiveHour != metrics.contains(.fiveHour) { showFiveHour = metrics.contains(.fiveHour) }
            if showSevenDay != metrics.contains(.sevenDay) { showSevenDay = metrics.contains(.sevenDay) }
            if showSonnet != metrics.contains(.sonnet) { showSonnet = metrics.contains(.sonnet) }
            if showPacing != metrics.contains(.pacing) {
                withAnimation(.easeInOut(duration: 0.2)) { showPacing = metrics.contains(.pacing) }
            }
        }
    }

    private func syncMetric(_ metric: MetricID, on: Bool, revert: @escaping () -> Void) {
        if on {
            settingsStore.pinnedMetrics.insert(metric)
        } else if settingsStore.pinnedMetrics.count > 1 {
            settingsStore.pinnedMetrics.remove(metric)
        } else {
            revert()
        }
    }
}
```

**Step 2: Extract reusable dark premium helpers**

Create `Shared/Components/DarkPremiumHelpers.swift` with helpers used across all sections:

```swift
import SwiftUI

// MARK: - Glass Card

func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
}

// MARK: - Section Title

func sectionTitle(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(.white)
}

// MARK: - Card Label

func cardLabel(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white.opacity(0.5))
}

// MARK: - Dark Toggle

func darkToggle(_ label: String, isOn: Binding<Bool>) -> some View {
    Toggle(isOn: isOn) {
        Text(label)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.8))
    }
    .toggleStyle(.switch)
    .tint(.blue)
}
```

Note: `PacingDisplayPicker` needs to be moved from `SettingsView.swift` to its own file or made non-private. Extract it to `Shared/Components/PacingDisplayPicker.swift`.

**Step 3: Remove the stub from MainAppView, run tests, commit**

```bash
git add TokenEaterApp/DisplaySectionView.swift Shared/Components/DarkPremiumHelpers.swift Shared/Components/PacingDisplayPicker.swift TokenEaterApp/MainAppView.swift
git commit -m "feat(ui): build DisplaySectionView with dark premium glass cards"
```

---

### Task 6: Build ThemesSectionView

**Files:**
- Create: `TokenEaterApp/ThemesSectionView.swift`

**Step 1: Create ThemesSectionView**

Port logic from old `ThemingTab` with dark premium styling:

```swift
import SwiftUI

struct ThemesSectionView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var showResetAlert = false
    @State private var warningSlider: Double = 60
    @State private var criticalSlider: Double = 85

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(String(localized: "sidebar.themes"))

            // Presets
            glassCard {
                VStack(alignment: .leading, spacing: 12) {
                    cardLabel(String(localized: "settings.theme.preset"))
                    HStack(spacing: 12) {
                        ForEach(ThemeColors.allPresets, id: \.key) { preset in
                            presetCard(key: preset.key, label: preset.label, colors: preset.colors)
                        }
                        customPresetCard()
                    }
                }
            }

            // Custom colors (if custom selected)
            if themeStore.selectedPreset == "custom" {
                glassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        cardLabel(String(localized: "settings.theme.colors"))
                        themeColorRow("settings.theme.gauge.normal", hex: $themeStore.customTheme.gaugeNormal)
                        themeColorRow("settings.theme.gauge.warning", hex: $themeStore.customTheme.gaugeWarning)
                        themeColorRow("settings.theme.gauge.critical", hex: $themeStore.customTheme.gaugeCritical)
                        themeColorRow("settings.theme.pacing.chill", hex: $themeStore.customTheme.pacingChill)
                        themeColorRow("settings.theme.pacing.ontrack", hex: $themeStore.customTheme.pacingOnTrack)
                        themeColorRow("settings.theme.pacing.hot", hex: $themeStore.customTheme.pacingHot)
                    }
                }
            }

            // Thresholds
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.theme.thresholds"))
                    thresholdSlider(label: String(localized: "settings.theme.warning"), value: $warningSlider, range: 10...90)
                    thresholdSlider(label: String(localized: "settings.theme.critical"), value: $criticalSlider, range: 15...95)

                    // Preview
                    HStack(spacing: 24) {
                        Spacer()
                        themePreviewGauge(pct: Double(max(themeStore.warningThreshold - 15, 5)), label: "Normal")
                        themePreviewGauge(pct: Double(themeStore.warningThreshold + themeStore.criticalThreshold) / 2.0, label: "Warning")
                        themePreviewGauge(pct: Double(min(themeStore.criticalThreshold + 5, 100)), label: "Critical")
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }

            // Reset
            HStack {
                Spacer()
                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    Text(String(localized: "settings.theme.reset"))
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .alert(String(localized: "settings.theme.reset.confirm"), isPresented: $showResetAlert) {
                    Button(String(localized: "settings.theme.reset.cancel"), role: .cancel) { }
                    Button(String(localized: "settings.theme.reset.action"), role: .destructive) {
                        themeStore.resetToDefaults()
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .task {
            warningSlider = Double(themeStore.warningThreshold)
            criticalSlider = Double(themeStore.criticalThreshold)
        }
        .onChange(of: warningSlider) { _, new in
            let int = Int(new)
            if themeStore.warningThreshold != int { themeStore.warningThreshold = int }
            if int >= themeStore.criticalThreshold { themeStore.criticalThreshold = min(int + 5, 95) }
        }
        .onChange(of: criticalSlider) { _, new in
            let int = Int(new)
            if themeStore.criticalThreshold != int { themeStore.criticalThreshold = int }
            if int <= themeStore.warningThreshold { themeStore.warningThreshold = max(int - 5, 10) }
        }
        .onChange(of: themeStore.warningThreshold) { _, new in
            let d = Double(new); if warningSlider != d { warningSlider = d }
        }
        .onChange(of: themeStore.criticalThreshold) { _, new in
            let d = Double(new); if criticalSlider != d { criticalSlider = d }
        }
        .onChange(of: themeStore.selectedPreset) { oldValue, newValue in
            if newValue == "custom", let source = ThemeColors.preset(for: oldValue) {
                themeStore.customTheme = source
            }
        }
    }

    // MARK: - Preset Card

    private func presetCard(key: String, label: String, colors: ThemeColors) -> some View {
        let isSelected = themeStore.selectedPreset == key
        return Button {
            themeStore.selectedPreset = key
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: colors.gaugeNormal), Color(hex: colors.gaugeWarning), Color(hex: colors.gaugeCritical)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle().stroke(isSelected ? Color.white : .clear, lineWidth: 2)
                    )
                    .shadow(color: isSelected ? Color.white.opacity(0.3) : .clear, radius: 6)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(isSelected ? 0.9 : 0.5))
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private func customPresetCard() -> some View {
        let isSelected = themeStore.selectedPreset == "custom"
        return Button {
            themeStore.selectedPreset = "custom"
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(
                        AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center)
                    )
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(isSelected ? Color.white : .clear, lineWidth: 2))
                    .shadow(color: isSelected ? Color.white.opacity(0.3) : .clear, radius: 6)
                Text(String(localized: "settings.theme.custom"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(isSelected ? 0.9 : 0.5))
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    // MARK: - Helpers

    private func themeColorRow(_ labelKey: LocalizedStringKey, hex: Binding<String>) -> some View {
        let colorBinding = Binding<Color>(
            get: { Color(hex: hex.wrappedValue) },
            set: { newColor in
                let nsColor = NSColor(newColor).usingColorSpace(.sRGB) ?? NSColor(newColor)
                let r = Int(nsColor.redComponent * 255)
                let g = Int(nsColor.greenComponent * 255)
                let b = Int(nsColor.blueComponent * 255)
                hex.wrappedValue = String(format: "#%02X%02X%02X", r, g, b)
            }
        )
        return HStack {
            Text(labelKey)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
        }
    }

    private func thresholdSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 60, alignment: .leading)
            Slider(value: value, in: range, step: 5)
                .tint(.blue)
            Text("\(Int(value.wrappedValue))%")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func themePreviewGauge(pct: Double, label: String) -> some View {
        let color = themeStore.current.gaugeColor(for: pct, thresholds: themeStore.thresholds)
        return VStack(spacing: 4) {
            RingGauge(
                percentage: Int(pct),
                gradient: themeStore.current.gaugeGradient(for: pct, thresholds: themeStore.thresholds, startPoint: .leading, endPoint: .trailing),
                size: 40,
                glowColor: color,
                glowRadius: 3
            )
            .overlay {
                GlowText(
                    "\(Int(pct))%",
                    font: .system(size: 10, weight: .black, design: .rounded),
                    color: color,
                    glowRadius: 2
                )
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}
```

**Step 2: Remove stub, run tests, commit**

```bash
git add TokenEaterApp/ThemesSectionView.swift TokenEaterApp/MainAppView.swift
git commit -m "feat(ui): build ThemesSectionView with dark premium preset cards"
```

---

### Task 7: Build SettingsSectionView

**Files:**
- Create: `TokenEaterApp/SettingsSectionView.swift`

**Step 1: Create SettingsSectionView**

Port connection, proxy, notifications, and about logic from old tabs:

```swift
import SwiftUI

struct SettingsSectionView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var updateStore: UpdateStore

    @State private var isTesting = false
    @State private var testResult: ConnectionTestResult?
    @State private var isImporting = false
    @State private var importMessage: String?
    @State private var importSuccess = false
    @State private var notifTestCooldown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(String(localized: "sidebar.settings"))

            // Connection
            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    cardLabel(String(localized: "settings.tab.connection"))
                    HStack(spacing: 8) {
                        Circle()
                            .fill(usageStore.hasConfig && !usageStore.hasError ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(usageStore.hasConfig && !usageStore.hasError
                             ? String(localized: "settings.connected")
                             : String(localized: "settings.disconnected"))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        if isImporting {
                            ProgressView().scaleEffect(0.6)
                        }
                        Button(String(localized: "settings.redetect")) {
                            connectAutoDetect()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.blue)
                    }
                    if let message = importMessage {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(importSuccess ? .green : .orange)
                    }
                    if let result = testResult {
                        Text(result.message)
                            .font(.system(size: 11))
                            .foregroundStyle(result.success ? .green : .red)
                    }
                }
            }

            // Proxy
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.tab.proxy"))
                    darkToggle(String(localized: "settings.proxy.toggle"), isOn: $settingsStore.proxyEnabled)
                    if settingsStore.proxyEnabled {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "settings.proxy.host"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.4))
                                TextField("127.0.0.1", text: $settingsStore.proxyHost)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "settings.proxy.port"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.4))
                                TextField("1080", value: $settingsStore.proxyPort, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 80)
                            }
                        }
                    }
                }
            }

            // Notifications
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.notifications.title"))
                    HStack {
                        switch settingsStore.notificationStatus {
                        case .authorized:
                            Label(String(localized: "settings.notifications.on"), systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.green)
                        case .denied:
                            Label(String(localized: "settings.notifications.off"), systemImage: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        default:
                            Label(String(localized: "settings.notifications.unknown"), systemImage: "questionmark.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        if settingsStore.notificationStatus == .denied {
                            Button(String(localized: "settings.notifications.open")) {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings")!)
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }
                        Button(String(localized: "settings.notifications.test")) {
                            if settingsStore.notificationStatus != .authorized {
                                settingsStore.requestNotificationPermission()
                            }
                            settingsStore.sendTestNotification()
                            notifTestCooldown = true
                            Task {
                                try? await Task.sleep(for: .seconds(3))
                                notifTestCooldown = false
                                await settingsStore.refreshNotificationStatus()
                            }
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .disabled(notifTestCooldown)
                    }
                }
            }

            // About
            glassCard {
                HStack {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                    Text("TokenEater v\(version)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    if updateStore.updateAvailable {
                        Text(String(localized: "update.badge"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                    Button(String(localized: "update.check")) {
                        Task { await updateStore.checkForUpdate(userInitiated: true) }
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .disabled(updateStore.isChecking)
                }
            }

            Spacer()
        }
        .padding(24)
        .onAppear {
            Task { await settingsStore.refreshNotificationStatus() }
        }
        .sheet(isPresented: $updateStore.showUpdateModal) {
            UpdateModalView()
        }
    }

    private func connectAutoDetect() {
        isImporting = true
        importMessage = nil
        guard settingsStore.keychainTokenExists() else {
            isImporting = false
            importMessage = String(localized: "connect.noclaudecode")
            importSuccess = false
            return
        }
        Task {
            let result = await usageStore.connectAutoDetect()
            isImporting = false
            if result.success {
                importMessage = String(localized: "connect.oauth.success")
                importSuccess = true
                usageStore.proxyConfig = settingsStore.proxyConfig
                usageStore.reloadConfig(thresholds: themeStore.thresholds)
                themeStore.syncToSharedFile()
            } else {
                importMessage = result.message
                importSuccess = false
            }
        }
    }
}
```

Add localization keys:

English:
```
"settings.connected" = "Connected";
"settings.disconnected" = "Not connected";
"settings.redetect" = "Re-detect";
```

French:
```
"settings.connected" = "Connecté";
"settings.disconnected" = "Non connecté";
"settings.redetect" = "Re-détecter";
```

**Step 2: Remove stub, run tests, commit**

```bash
git add TokenEaterApp/SettingsSectionView.swift Shared/en.lproj/Localizable.strings Shared/fr.lproj/Localizable.strings TokenEaterApp/MainAppView.swift
git commit -m "feat(ui): build SettingsSectionView with dark premium glass cards"
```

---

### Task 8: Redesign OnboardingView for unified window

**Files:**
- Modify: `TokenEaterApp/OnboardingView.swift`
- Modify: `TokenEaterApp/OnboardingSteps/WelcomeStep.swift`
- Modify: `TokenEaterApp/OnboardingSteps/PrerequisiteStep.swift`
- Modify: `TokenEaterApp/OnboardingSteps/NotificationStep.swift`
- Modify: `TokenEaterApp/OnboardingSteps/ConnectionStep.swift`

**Step 1: Update OnboardingView**

The onboarding now fills the full unified window panel (no fixed frame). Add AnimatedGradient background:

```swift
import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var forward = true

    var body: some View {
        ZStack {
            AnimatedGradient(baseColors: [
                Color(red: 0.04, green: 0.04, blue: 0.10),
                Color(red: 0.08, green: 0.04, blue: 0.16),
            ])

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
            .transition(.asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
            ))
            .id(viewModel.currentStep)

            // Page dots
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    ForEach(OnboardingStep.allCases, id: \.self) { step in
                        Circle()
                            .fill(step == viewModel.currentStep ? Color.white : Color.white.opacity(0.2))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .onChange(of: viewModel.currentStep) { oldValue, newValue in
            forward = newValue.rawValue > oldValue.rawValue
        }
    }
}
```

**Step 2: Restyle each onboarding step with dark premium look**

Each step should use `.foregroundStyle(.white)` text, GlowText for titles, glass card backgrounds for interactive elements, and the same dark aesthetic. Remove the `.frame(width: 520, height: 580)` from the old view — sizing comes from the window.

The steps keep the same logic (checkClaudeCode, connect, notifications) but get dark premium styling: white text on transparent background, glow effects, glass cards for action areas.

Key style changes for all steps:
- Title: `GlowText` with white color, size 24-28
- Subtitle: `.white.opacity(0.5)`, size 14
- Buttons: glass card background with glow on hover
- Status indicators: same logic, dark styled
- Remove any `.background(.background)` or system backgrounds

**Step 3: Run tests, commit**

```bash
git add TokenEaterApp/OnboardingView.swift TokenEaterApp/OnboardingSteps/
git commit -m "feat(ui): redesign onboarding with dark premium style for unified window"
```

---

### Task 9: Cleanup — remove old SettingsView and dead code

**Files:**
- Delete: Old code from `TokenEaterApp/SettingsView.swift` (replace with just the `PacingDisplayPicker` if not yet extracted)
- Modify: `TokenEaterApp/TokenEaterApp.swift` — remove `RootView`, `SettingsContentView`
- Modify: `TokenEaterApp/MenuBarView.swift` — update the settings action to open dashboard

**Step 1: Remove old SettingsView**

Delete the entire content of `SettingsView.swift` or delete the file if `PacingDisplayPicker` has been moved to `Shared/Components/`. The `SettingsHeaderView`, `ConnectionTab`, `DisplayTab`, `ThemingTab`, `ProxyTab` are all replaced by the new section views.

**Step 2: Clean up TokenEaterApp.swift**

Remove `RootView` and `SettingsContentView` private structs — they're no longer needed since there's no `WindowGroup("settings")`. The `App.body` only has the hidden `Settings` scene.

**Step 3: Verify no dangling references**

Search for `SettingsView()`, `SettingsContentView()`, `openWindow(id: "settings")` — remove or replace all occurrences.

**Step 4: Run tests, build Release, commit**

```bash
git add -A
git commit -m "refactor: remove old SettingsView and WindowGroup settings scene"
```

---

### Task 10: Integration test — Release build + full nuke + install

**Step 1: Run all unit tests**

```bash
xcodegen generate
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests -configuration Debug -derivedDataPath build -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test
```

Expected: ALL PASS (126+ tests)

**Step 2: Build Release with Xcode 16.4**

```bash
export DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer
DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject 2>/dev/null | grep -oE 'OU=[A-Z0-9]{10}' | head -1 | cut -d= -f2)
xcodegen generate
plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' TokenEaterWidget/Info.plist 2>/dev/null
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM build
```

Expected: BUILD SUCCEEDED

**Step 3: Trigger CI test-build for iso-prod verification**

```bash
git push origin feat/42-enrich-displayed-data-with-add
gh workflow run test-build.yml -f branch=feat/42-enrich-displayed-data-with-add
```

Wait for CI to pass, download DMG, mega nuke, install, verify:
- First launch: onboarding in borderless floating window with dark premium style
- After connect: sidebar + dashboard in 2-column landscape
- Plan badge shows "TEAM" (not "FREE")
- Rate limit tier shows "Max 5x" (not "default_claude_max_5x")
- Profile card shows organization name
- Display, Themes, Settings sections all work
- Popover still works (unchanged)
- Click behavior toggle works (popover vs dashboard)

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: address integration test issues"
```
