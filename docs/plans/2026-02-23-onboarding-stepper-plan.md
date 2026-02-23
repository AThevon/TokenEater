# Onboarding Stepper Modal — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the bare SettingsView first-launch with a 3-step onboarding stepper modal that explains the app, detects Claude Code, and primes the user before the Keychain dialog.

**Architecture:** A new `OnboardingView` (SwiftUI window) with 3 steps controlled by an `OnboardingViewModel`. The app entry point conditionally shows onboarding vs normal flow based on `@AppStorage("hasCompletedOnboarding")`. A new `KeychainOAuthReader.tokenExists()` method checks Keychain item presence without triggering the password dialog.

**Tech Stack:** SwiftUI, Security framework (Keychain), WidgetKit, macOS 14+

**Design doc:** `docs/plans/2026-02-23-onboarding-stepper-design.md`
**Issue:** https://github.com/AThevon/TokenEater/issues/12

---

### Task 1: Add `tokenExists()` to KeychainOAuthReader

Add a lightweight Keychain check that returns `Bool` without triggering the macOS password dialog. Uses `kSecReturnAttributes` instead of `kSecReturnData`.

**Files:**
- Modify: `Shared/KeychainOAuthReader.swift`

**Step 1: Add the `tokenExists()` method**

Add this method to `KeychainOAuthReader` (after the existing `readClaudeCodeToken()`):

```swift
/// Check if the Claude Code Keychain item exists WITHOUT triggering the password dialog.
/// Uses kSecReturnAttributes (metadata only) instead of kSecReturnData.
static func tokenExists() -> Bool {
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
```

**Step 2: Build to verify**

Run:
```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Debug -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shared/KeychainOAuthReader.swift
git commit -m "feat(keychain): add tokenExists() for silent detection

Check Keychain item presence using kSecReturnAttributes
to avoid triggering the macOS password dialog.

Ref: #12"
```

---

### Task 2: Create OnboardingViewModel

State machine for the 3-step onboarding flow.

**Files:**
- Create: `ClaudeUsageApp/OnboardingViewModel.swift`

**Step 1: Create the ViewModel**

```swift
import SwiftUI
import WidgetKit

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case prerequisites = 1
    case connection = 2
}

enum ClaudeCodeStatus {
    case checking
    case detected
    case notFound
}

enum ConnectionStatus {
    case idle
    case connecting
    case success(UsageResponse)
    case failed(String)
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
    @Published var isDetailedMode = false
    @Published var claudeCodeStatus: ClaudeCodeStatus = .checking
    @Published var connectionStatus: ConnectionStatus = .idle

    func checkClaudeCode() {
        claudeCodeStatus = .checking
        // Small delay so the UI has time to show "checking" state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.claudeCodeStatus = KeychainOAuthReader.tokenExists() ? .detected : .notFound
        }
    }

    func connect() {
        connectionStatus = .connecting

        guard let oauth = KeychainOAuthReader.readClaudeCodeToken() else {
            connectionStatus = .failed(String(localized: "onboarding.connection.failed.notoken"))
            return
        }

        SharedContainer.oauthToken = oauth.accessToken

        Task {
            do {
                let usage = try await ClaudeAPIClient.shared.fetchUsage()
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

    func goNext() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = next
        }
    }

    func goBack() {
        guard let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = prev
        }
    }
}
```

**Step 2: Build to verify**

Run:
```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Debug -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ClaudeUsageApp/OnboardingViewModel.swift
git commit -m "feat(onboarding): add OnboardingViewModel state machine

3-step stepper with Claude Code detection, connection flow,
and simplified/detailed mode toggle.

Ref: #12"
```

---

### Task 3: Create WelcomeStep view

First step of the onboarding — app presentation with demo data preview.

**Files:**
- Create: `ClaudeUsageApp/OnboardingSteps/WelcomeStep.swift`

**Step 1: Create the view**

```swift
import SwiftUI

struct WelcomeStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    // Demo data for preview gauges
    private let demoValues: [(String, Int, Color)] = [
        ("5h", 35, Color(hex: "#22C55E")),
        ("7d", 52, Color(hex: "#FF9F0A")),
        ("Sonnet", 12, Color(hex: "#3B82F6")),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)

            // Title
            Text("TokenEater")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("onboarding.welcome.subtitle")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Demo preview
            demoPreview
                .padding(.vertical, 8)

            Text("onboarding.welcome.description")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Spacer()

            // CTA
            Button {
                viewModel.goNext()
            } label: {
                Text("onboarding.continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
    }

    private var demoPreview: some View {
        HStack(spacing: 24) {
            ForEach(demoValues, id: \.0) { label, value, color in
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(color.opacity(0.15), lineWidth: 6)
                            .frame(width: 56, height: 56)
                        Circle()
                            .trim(from: 0, to: CGFloat(value) / 100)
                            .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 56, height: 56)
                            .rotationEffect(.degrees(-90))
                        Text("\(value)%")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}
```

**Step 2: Build to verify**

Run:
```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Debug -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ClaudeUsageApp/OnboardingSteps/WelcomeStep.swift
git commit -m "feat(onboarding): add WelcomeStep view

App presentation with demo data preview gauges.

Ref: #12"
```

---

### Task 4: Create PrerequisiteStep view

Second step — Claude Code detection with install guide fallback.

**Files:**
- Create: `ClaudeUsageApp/OnboardingSteps/PrerequisiteStep.swift`

**Step 1: Create the view**

```swift
import SwiftUI

struct PrerequisiteStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Mode toggle
            modeToggle

            // Status icon
            statusIcon

            // Content adapted to detection status
            statusContent

            Spacer()

            // Navigation
            HStack {
                Button {
                    viewModel.goBack()
                } label: {
                    Text("onboarding.back")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Spacer()

                Button {
                    viewModel.goNext()
                } label: {
                    Text("onboarding.continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.claudeCodeStatus != .detected)
            }
        }
        .padding(32)
        .onAppear {
            viewModel.checkClaudeCode()
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

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch viewModel.claudeCodeStatus {
        case .checking:
            ProgressView()
                .controlSize(.large)
        case .detected:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
        case .notFound:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Status Content

    @ViewBuilder
    private var statusContent: some View {
        switch viewModel.claudeCodeStatus {
        case .checking:
            Text("onboarding.prereq.checking")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

        case .detected:
            detectedContent

        case .notFound:
            notFoundContent
        }
    }

    private var detectedContent: some View {
        VStack(spacing: 12) {
            Text("onboarding.prereq.detected.title")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            if viewModel.isDetailedMode {
                Text("onboarding.prereq.detected.detailed")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            } else {
                Text("onboarding.prereq.detected.simple")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            planRequirement
        }
    }

    private var notFoundContent: some View {
        VStack(spacing: 16) {
            Text("onboarding.prereq.notfound.title")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            // Install guide
            VStack(alignment: .leading, spacing: 12) {
                guideStep(number: 1, text: String(localized: "onboarding.prereq.step1"))
                guideStep(number: 2, text: String(localized: "onboarding.prereq.step2"))
                guideStep(number: 3, text: String(localized: "onboarding.prereq.step3"))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )

            HStack(spacing: 12) {
                Link(destination: URL(string: "https://docs.anthropic.com/en/docs/claude-code/overview")!) {
                    Label("onboarding.prereq.install.link", systemImage: "arrow.up.right")
                }

                Button {
                    viewModel.checkClaudeCode()
                } label: {
                    Label("onboarding.prereq.retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            planRequirement
        }
    }

    private var planRequirement: some View {
        Label {
            Text("onboarding.prereq.plan.required")
                .font(.system(size: 12))
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    private func guideStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }
}
```

**Step 2: Build to verify**

Run:
```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Debug -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ClaudeUsageApp/OnboardingSteps/PrerequisiteStep.swift
git commit -m "feat(onboarding): add PrerequisiteStep view

Claude Code detection with install guide fallback
and simplified/detailed mode toggle.

Ref: #12"
```

---

### Task 5: Create ConnectionStep view

Third step — permission priming, Keychain access, success/failure states.

**Files:**
- Create: `ClaudeUsageApp/OnboardingSteps/ConnectionStep.swift`

**Step 1: Create the view**

```swift
import SwiftUI

struct ConnectionStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            switch viewModel.connectionStatus {
            case .idle:
                primingContent
            case .connecting:
                connectingContent
            case .success(let usage):
                successContent(usage: usage)
            case .failed(let message):
                failedContent(message: message)
            }

            Spacer()

            // Navigation
            bottomBar
        }
        .padding(32)
    }

    // MARK: - Priming (before connection)

    private var primingContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("onboarding.connection.title")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            if viewModel.isDetailedMode {
                Text("onboarding.connection.detailed")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            } else {
                Text("onboarding.connection.simple")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            Button {
                viewModel.connect()
            } label: {
                Label("onboarding.connection.authorize", systemImage: "key.fill")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
    }

    // MARK: - Connecting

    private var connectingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("onboarding.connection.connecting")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Success

    private func successContent(usage: UsageResponse) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("onboarding.connection.success.title")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            // Real data preview
            realDataPreview(usage: usage)

            // Widget hint
            Label {
                Text("onboarding.connection.widget.hint")
                    .font(.system(size: 12))
            } icon: {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(.blue)
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
        }
    }

    private func realDataPreview(usage: UsageResponse) -> some View {
        let values: [(String, Int, Color)] = [
            ("5h", Int(usage.fiveHour?.utilization ?? 0), Color(hex: "#22C55E")),
            ("7d", Int(usage.sevenDay?.utilization ?? 0), Color(hex: "#FF9F0A")),
            ("Sonnet", Int(usage.sevenDaySonnet?.utilization ?? 0), Color(hex: "#3B82F6")),
        ]

        return HStack(spacing: 24) {
            ForEach(values, id: \.0) { label, value, color in
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(color.opacity(0.15), lineWidth: 6)
                            .frame(width: 56, height: 56)
                        Circle()
                            .trim(from: 0, to: CGFloat(value) / 100)
                            .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 56, height: 56)
                            .rotationEffect(.degrees(-90))
                        Text("\(value)%")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Failed

    private func failedContent(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("onboarding.connection.failed.title")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            // Tip about re-login
            Label {
                Text("onboarding.connection.failed.tip")
                    .font(.system(size: 12))
            } icon: {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)

            Button {
                viewModel.connectionStatus = .idle
            } label: {
                Label("onboarding.connection.retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        switch viewModel.connectionStatus {
        case .success:
            Button {
                viewModel.completeOnboarding()
                NSApplication.shared.keyWindow?.close()
            } label: {
                Text("onboarding.connection.start")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        default:
            HStack {
                Button {
                    viewModel.goBack()
                } label: {
                    Text("onboarding.back")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Spacer()
            }
        }
    }
}
```

**Step 2: Build to verify**

Run:
```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Debug -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ClaudeUsageApp/OnboardingSteps/ConnectionStep.swift
git commit -m "feat(onboarding): add ConnectionStep view

Permission priming, Keychain access trigger,
success with real data preview, and failure handling.

Ref: #12"
```

---

### Task 6: Create OnboardingView container

The main container view that holds the stepper, page dots, and step transitions.

**Files:**
- Create: `ClaudeUsageApp/OnboardingView.swift`

**Step 1: Create the container view**

```swift
import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Step content
            Group {
                switch viewModel.currentStep {
                case .welcome:
                    WelcomeStep(viewModel: viewModel)
                case .prerequisites:
                    PrerequisiteStep(viewModel: viewModel)
                case .connection:
                    ConnectionStep(viewModel: viewModel)
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .id(viewModel.currentStep)

            // Page dots
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step == viewModel.currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.currentStep)
                }
            }
            .padding(.bottom, 20)
        }
        .frame(width: 520, height: 480)
    }
}
```

**Step 2: Build to verify**

Run:
```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Debug -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ClaudeUsageApp/OnboardingView.swift
git commit -m "feat(onboarding): add OnboardingView container

Stepper container with page dots and step transitions.

Ref: #12"
```

---

### Task 7: Wire onboarding into app entry point

Modify `ClaudeUsageApp.swift` to show onboarding on first launch.

**Files:**
- Modify: `ClaudeUsageApp/ClaudeUsageApp.swift`

**Step 1: Add conditional onboarding window**

Replace the entire `ClaudeUsageApp.swift` with:

```swift
import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var menuBarVM = MenuBarViewModel()
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        syncProxyConfig()
    }

    var body: some Scene {
        WindowGroup(id: "settings") {
            if hasCompletedOnboarding {
                SettingsView(onConfigSaved: { [weak menuBarVM] in
                    menuBarVM?.reloadConfig()
                    syncProxyConfig()
                })
            } else {
                OnboardingView()
            }
        }
        .windowResizability(.contentSize)

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarPopoverView(viewModel: menuBarVM)
        } label: {
            Image(nsImage: menuBarVM.menuBarImage)
        }
        .menuBarExtraStyle(.window)
    }

    private func syncProxyConfig() {
        ClaudeAPIClient.shared.proxyConfig = ProxyConfig(
            enabled: UserDefaults.standard.bool(forKey: "proxyEnabled"),
            host: UserDefaults.standard.string(forKey: "proxyHost") ?? "127.0.0.1",
            port: {
                let port = UserDefaults.standard.integer(forKey: "proxyPort")
                return port > 0 ? port : 1080
            }()
        )
    }
}
```

**Step 2: Build to verify**

Run:
```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Debug -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ClaudeUsageApp/ClaudeUsageApp.swift
git commit -m "feat(onboarding): wire onboarding into app entry point

Show OnboardingView on first launch, SettingsView after completion.

Ref: #12"
```

---

### Task 8: Add i18n strings for onboarding

Add all localized strings for both English and French.

**Files:**
- Modify: `Shared/en.lproj/Localizable.strings`
- Modify: `Shared/fr.lproj/Localizable.strings`

**Step 1: Add English strings**

Append to `Shared/en.lproj/Localizable.strings`:

```
/* Onboarding */
"onboarding.continue" = "Continue";
"onboarding.back" = "Back";
"onboarding.mode.simple" = "Simple";
"onboarding.mode.detailed" = "Detailed";

/* Onboarding - Welcome */
"onboarding.welcome.subtitle" = "Keep an eye on your Claude usage";
"onboarding.welcome.description" = "A menu bar widget that shows your Claude Code consumption at a glance.";

/* Onboarding - Prerequisites */
"onboarding.prereq.checking" = "Looking for Claude Code…";
"onboarding.prereq.detected.title" = "Claude Code found!";
"onboarding.prereq.detected.simple" = "TokenEater found Claude Code on your Mac. It'll use your existing session to fetch your usage data.";
"onboarding.prereq.detected.detailed" = "TokenEater found a Claude Code OAuth token in your macOS Keychain (service: Claude Code-credentials). It reads this token to call the Anthropic usage API.";
"onboarding.prereq.notfound.title" = "Claude Code not found";
"onboarding.prereq.step1" = "Install Claude Code (Anthropic's CLI)";
"onboarding.prereq.step2" = "Launch it and sign in with your Claude account";
"onboarding.prereq.step3" = "Come back here and hit retry";
"onboarding.prereq.install.link" = "Get Claude Code";
"onboarding.prereq.retry" = "Retry";
"onboarding.prereq.plan.required" = "Requires a Claude Pro or Team plan — the free plan doesn't expose usage data.";

/* Onboarding - Connection */
"onboarding.connection.title" = "One last thing";
"onboarding.connection.simple" = "macOS will ask for your password — that's normal. It lets TokenEater securely read your Claude session.";
"onboarding.connection.detailed" = "macOS protects the Keychain with your login password. TokenEater needs a one-time read via SecItemCopyMatching. Only the access token is copied — nothing else leaves the Keychain.";
"onboarding.connection.authorize" = "Authorize";
"onboarding.connection.connecting" = "Connecting…";
"onboarding.connection.success.title" = "You're all set!";
"onboarding.connection.widget.hint" = "Add the widget: right-click desktop → Edit Widgets → TokenEater";
"onboarding.connection.start" = "Let's go";
"onboarding.connection.retry" = "Try again";
"onboarding.connection.failed.title" = "Something went wrong";
"onboarding.connection.failed.notoken" = "Couldn't read the token. Make sure Claude Code is installed and you're signed in.";
"onboarding.connection.failed.tip" = "Try running /login in Claude Code even if you're already signed in — it can fix stale sessions.";

/* Settings - Onboarding reset */
"settings.onboarding.reset" = "Run setup again";
```

**Step 2: Add French strings**

Append to `Shared/fr.lproj/Localizable.strings`:

```
/* Onboarding */
"onboarding.continue" = "Continuer";
"onboarding.back" = "Retour";
"onboarding.mode.simple" = "Simple";
"onboarding.mode.detailed" = "Détaillé";

/* Onboarding - Welcome */
"onboarding.welcome.subtitle" = "Gardez un œil sur votre conso Claude";
"onboarding.welcome.description" = "Un widget dans la barre de menu pour voir votre consommation Claude Code d'un coup d'œil.";

/* Onboarding - Prerequisites */
"onboarding.prereq.checking" = "Recherche de Claude Code…";
"onboarding.prereq.detected.title" = "Claude Code trouvé !";
"onboarding.prereq.detected.simple" = "TokenEater a trouvé Claude Code sur votre Mac. Il va utiliser votre session pour récupérer vos données d'usage.";
"onboarding.prereq.detected.detailed" = "TokenEater a trouvé un token OAuth Claude Code dans le Keychain macOS (service : Claude Code-credentials). Il lit ce token pour appeler l'API usage d'Anthropic.";
"onboarding.prereq.notfound.title" = "Claude Code introuvable";
"onboarding.prereq.step1" = "Installez Claude Code (le CLI d'Anthropic)";
"onboarding.prereq.step2" = "Lancez-le et connectez-vous avec votre compte Claude";
"onboarding.prereq.step3" = "Revenez ici et cliquez sur réessayer";
"onboarding.prereq.install.link" = "Installer Claude Code";
"onboarding.prereq.retry" = "Réessayer";
"onboarding.prereq.plan.required" = "Nécessite un plan Claude Pro ou Team — le plan gratuit ne fournit pas les données d'usage.";

/* Onboarding - Connection */
"onboarding.connection.title" = "Dernière étape";
"onboarding.connection.simple" = "macOS va demander votre mot de passe — c'est normal. Ça permet à TokenEater de lire votre session Claude en toute sécurité.";
"onboarding.connection.detailed" = "macOS protège le Keychain avec votre mot de passe. TokenEater fait une lecture unique via SecItemCopyMatching. Seul l'access token est copié — rien d'autre ne sort du Keychain.";
"onboarding.connection.authorize" = "Autoriser";
"onboarding.connection.connecting" = "Connexion…";
"onboarding.connection.success.title" = "C'est bon, tout roule !";
"onboarding.connection.widget.hint" = "Ajoutez le widget : clic droit sur le bureau → Modifier les widgets → TokenEater";
"onboarding.connection.start" = "C'est parti";
"onboarding.connection.retry" = "Réessayer";
"onboarding.connection.failed.title" = "Quelque chose a planté";
"onboarding.connection.failed.notoken" = "Impossible de lire le token. Vérifiez que Claude Code est installé et que vous êtes connecté.";
"onboarding.connection.failed.tip" = "Essayez /login dans Claude Code même si vous êtes déjà connecté — ça peut débloquer une session expirée.";

/* Settings - Onboarding reset */
"settings.onboarding.reset" = "Relancer la configuration";
```

**Step 3: Build to verify**

Run:
```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Debug -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add Shared/en.lproj/Localizable.strings Shared/fr.lproj/Localizable.strings
git commit -m "feat(onboarding): add i18n strings (en + fr)

All onboarding strings for welcome, prerequisites,
connection, and settings reset.

Ref: #12"
```

---

### Task 9: Add "Reset onboarding" button in Settings

Add a button in SettingsView to re-launch the onboarding flow.

**Files:**
- Modify: `ClaudeUsageApp/SettingsView.swift`

**Step 1: Add reset button**

In `SettingsView.swift`, add a new `@AppStorage` property alongside the existing ones:

```swift
@AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
```

Then add a new section at the bottom of the `connectionTab` computed property (inside the `Form`, after the existing sections):

```swift
Section {
    Button("settings.onboarding.reset") {
        hasCompletedOnboarding = false
    }
    .foregroundStyle(.secondary)
}
```

**Step 2: Build to verify**

Run:
```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Debug -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ClaudeUsageApp/SettingsView.swift
git commit -m "feat(settings): add reset onboarding button

Allows re-launching the onboarding from the Connection tab.

Ref: #12"
```

---

### Task 10: Build, install, and manual test

Full build + local install to manually verify the onboarding flow.

**Step 1: Full build**

```bash
xcodegen generate
plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' ClaudeUsageWidget/Info.plist 2>/dev/null || true
xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Release -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=S7B8M9JYF4 build
```

Expected: BUILD SUCCEEDED

**Step 2: Nuclear cleanup + install**

Follow the install procedure from CLAUDE.md (kill processes, clear caches, unregister plugin, install, re-register, launch).

**Step 3: Manual test checklist**

- [ ] App opens with onboarding modal (not SettingsView)
- [ ] Step 1: Welcome shows demo gauges, "Continue" works
- [ ] Step 2: Detects Claude Code (or shows install guide if absent)
- [ ] Toggle "Simple/Detailed" changes the explanation text
- [ ] Step 3: Clicking "Authorize" triggers macOS Keychain dialog
- [ ] After Keychain approval: real data appears in preview
- [ ] "Let's go" closes the modal, menu bar shows real data
- [ ] Re-opening the app shows SettingsView (not onboarding)
- [ ] "Reset onboarding" in Settings → re-opening shows onboarding again
- [ ] Page dots update correctly between steps
- [ ] Back button works on steps 2 and 3

**Step 4: Commit any fixes found during manual testing**

---

### Task 11: Update XcodeGen sources (if needed)

Verify that `project.yml` picks up the new `OnboardingSteps/` directory. Since the sources are `- path: ClaudeUsageApp`, XcodeGen recursively includes all `.swift` files in subdirectories — so no change should be needed. Verify by running `xcodegen generate` and checking the project includes the new files.

**Step 1: Verify**

```bash
xcodegen generate 2>&1
# Check new files are included
xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -showBuildSettings 2>/dev/null | grep -c "OnboardingStep"
```

If files are missing, add the `OnboardingSteps` path explicitly in `project.yml`.

**Step 2: Commit if changes needed**

```bash
git add project.yml
git commit -m "chore: ensure OnboardingSteps included in XcodeGen sources

Ref: #12"
```
