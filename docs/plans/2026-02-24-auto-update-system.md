# Auto-Update System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add in-app update detection via GitHub Releases API and seamless brew upgrade execution via .command script, all within sandbox constraints.

**Architecture:** Protocol-based UpdateService queries GitHub API, @Observable UpdateStore manages state injected via @Environment, UpdateModalView displays release info. Update execution writes a .command shell script to the shared App Support directory and opens it with Terminal via NSWorkspace.

**Tech Stack:** Swift 5.9, SwiftUI, @Observable, URLSession, NSWorkspace, Homebrew Cask

**Design doc:** `docs/plans/2026-02-24-auto-update-system-design.md`

---

### Task 1: Create UpdateModels

**Files:**
- Create: `Shared/Models/UpdateModels.swift`

**Step 1: Create the models file**

```swift
// Shared/Models/UpdateModels.swift
import Foundation

struct GitHubRelease: Codable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

struct UpdateInfo: Sendable {
    let version: String
    let releaseNotes: String?
    let downloadURL: URL?
    let releaseURL: URL
}
```

**Step 2: Build to verify**

Run: `xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Debug -derivedDataPath build build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shared/Models/UpdateModels.swift
git commit -m "feat(update): add GitHub release models"
```

---

### Task 2: Create UpdateService protocol and implementation

**Files:**
- Create: `Shared/Services/Protocols/UpdateServiceProtocol.swift`
- Create: `Shared/Services/UpdateService.swift`

**Step 1: Create the protocol**

```swift
// Shared/Services/Protocols/UpdateServiceProtocol.swift
import Foundation

protocol UpdateServiceProtocol: Sendable {
    func checkForUpdate() async throws -> UpdateInfo?
    func launchBrewUpdate() throws
}
```

**Step 2: Create the service implementation**

Follow existing patterns from `APIClient.swift` and `SharedFileService.swift`:
- `final class` with `@unchecked Sendable`
- `getpwuid(getuid())` for real home directory (not sandbox container)
- `async throws` for network calls
- `try?` for non-critical file operations

```swift
// Shared/Services/UpdateService.swift
import Foundation
import AppKit

enum UpdateError: LocalizedError {
    case invalidResponse
    case scriptWriteFailed
    case scriptLaunchFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return String(localized: "update.error.response")
        case .scriptWriteFailed: return String(localized: "update.error.script")
        case .scriptLaunchFailed: return String(localized: "update.error.launch")
        }
    }
}

final class UpdateService: UpdateServiceProtocol, @unchecked Sendable {
    private let repo = "AThevon/TokenEater"

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private var realHomeDirectory: String {
        guard let pw = getpwuid(getuid()) else { return NSHomeDirectory() }
        return String(cString: pw.pointee.pw_dir)
    }

    private var updateScriptPath: String {
        "\(realHomeDirectory)/Library/Application Support/com.tokeneater.shared/update.command"
    }

    // MARK: - Check

    func checkForUpdate() async throws -> UpdateInfo? {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.invalidResponse
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let remoteVersion = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst())
            : release.tagName

        guard isNewer(remoteVersion, than: currentVersion) else {
            return nil
        }

        let dmgAsset = release.assets.first { $0.name.hasSuffix(".dmg") }

        return UpdateInfo(
            version: remoteVersion,
            releaseNotes: release.body,
            downloadURL: dmgAsset.flatMap { URL(string: $0.browserDownloadURL) },
            releaseURL: URL(string: release.htmlURL)!
        )
    }

    // MARK: - Update

    func launchBrewUpdate() throws {
        let script = """
        #!/bin/bash
        # TokenEater Auto-Update

        if [ -x "/opt/homebrew/bin/brew" ]; then
            BREW="/opt/homebrew/bin/brew"
        elif [ -x "/usr/local/bin/brew" ]; then
            BREW="/usr/local/bin/brew"
        else
            echo "Homebrew not found."
            echo "Run manually: brew upgrade --cask tokeneater"
            read -p "Press Enter to close..."
            exit 1
        fi

        echo "Updating TokenEater..."
        $BREW upgrade --cask tokeneater

        if [ $? -eq 0 ]; then
            echo "Update complete! Relaunching..."
            sleep 1
            open /Applications/TokenEater.app
        else
            echo "Update failed. Try: brew upgrade --cask tokeneater"
            read -p "Press Enter to close..."
        fi

        rm -f "$0"
        """

        let dir = (updateScriptPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )

        guard FileManager.default.createFile(
            atPath: updateScriptPath,
            contents: script.data(using: .utf8)
        ) else {
            throw UpdateError.scriptWriteFailed
        }

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: updateScriptPath
        )

        let url = URL(fileURLWithPath: updateScriptPath)
        guard NSWorkspace.shared.open(url) else {
            // Fallback: copy brew command to clipboard and open release page
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("brew upgrade --cask tokeneater", forType: .string)
            throw UpdateError.scriptLaunchFailed
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Version comparison

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}
```

**Step 3: Build to verify**

Run: `xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Debug -derivedDataPath build build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add Shared/Services/Protocols/UpdateServiceProtocol.swift Shared/Services/UpdateService.swift
git commit -m "feat(update): add UpdateService with GitHub API check and brew update"
```

---

### Task 3: Create UpdateStore

**Files:**
- Create: `Shared/Stores/UpdateStore.swift`

Follow existing pattern from `UsageStore.swift`:
- `@MainActor @Observable final class`
- Default DI in `init(service: UpdateServiceProtocol = UpdateService())`
- `Task<Void, Never>` with `[weak self]` for auto-check loop

**Step 1: Create the store**

```swift
// Shared/Stores/UpdateStore.swift
import Foundation

@MainActor
@Observable
final class UpdateStore {
    var updateAvailable = false
    var latestVersion: String?
    var releaseNotes: String?
    var releaseURL: URL?
    var isChecking = false
    var isUpdating = false
    var updateError: String?
    var showUpdateModal = false

    private let service: UpdateServiceProtocol
    private var checkTask: Task<Void, Never>?

    private var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: "skippedVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "skippedVersion") }
    }

    private var lastCheckDate: Date? {
        get { UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastUpdateCheck") }
    }

    init(service: UpdateServiceProtocol = UpdateService()) {
        self.service = service
    }

    func checkForUpdate(userInitiated: Bool = false) async {
        if !userInitiated, let last = lastCheckDate, Date().timeIntervalSince(last) < 6 * 3600 {
            return
        }

        isChecking = true
        updateError = nil
        defer { isChecking = false }

        do {
            guard let info = try await service.checkForUpdate() else {
                updateAvailable = false
                lastCheckDate = Date()
                return
            }

            latestVersion = info.version
            releaseNotes = info.releaseNotes
            releaseURL = info.releaseURL
            updateAvailable = true
            lastCheckDate = Date()

            if userInitiated || skippedVersion != info.version {
                showUpdateModal = true
            }
        } catch {
            if userInitiated {
                updateError = error.localizedDescription
            }
        }
    }

    func performUpdate() {
        isUpdating = true
        updateError = nil
        do {
            try service.launchBrewUpdate()
        } catch {
            updateError = error.localizedDescription
            isUpdating = false
        }
    }

    func skipCurrentUpdate() {
        skippedVersion = latestVersion
        showUpdateModal = false
    }

    func dismissUpdate() {
        showUpdateModal = false
    }

    func startAutoCheck() {
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            await self?.checkForUpdate()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6 * 3600))
                guard let self else { return }
                await self.checkForUpdate()
            }
        }
    }
}
```

**Step 2: Build to verify**

Run: `xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Debug -derivedDataPath build build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shared/Stores/UpdateStore.swift
git commit -m "feat(update): add UpdateStore with auto-check and skip logic"
```

---

### Task 4: Create UpdateModalView

**Files:**
- Create: `TokenEaterApp/UpdateModalView.swift`

Match existing dark-themed sheet style from `SettingsView.guideSheet`:
- `sheetBg = Color(hex: "#141416")`
- `accent = Color(hex: "#FF9F0A")`
- Rounded rectangles with subtle borders

**Step 1: Create the view**

```swift
// TokenEaterApp/UpdateModalView.swift
import SwiftUI

struct UpdateModalView: View {
    @Environment(UpdateStore.self) private var updateStore

    private let sheetBg = Color(hex: "#141416")
    private let sheetCard = Color.white.opacity(0.04)
    private let accent = Color(hex: "#FF9F0A")

    var body: some View {
        ZStack {
            sheetBg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.bottom, 20)

                if let notes = updateStore.releaseNotes, !notes.isEmpty {
                    releaseNotesSection(notes)
                        .padding(.bottom, 20)
                }

                if let error = updateStore.updateError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.bottom, 12)
                }

                actions
            }
            .padding(24)
        }
        .frame(width: 420, height: 340)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(accent)
                    Text("update.available")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                HStack(spacing: 8) {
                    let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                    Text("v\(current)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("v\(updateStore.latestVersion ?? "?")")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(accent)
                }
            }
            Spacer()
            Button {
                updateStore.dismissUpdate()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Release Notes

    private func releaseNotesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("update.releasenotes")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            ScrollView {
                Text(notes)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(sheetCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
            .frame(maxHeight: 150)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Button("update.skip") {
                updateStore.skipCurrentUpdate()
            }
            .foregroundStyle(.secondary)

            Spacer()

            Button("update.later") {
                updateStore.dismissUpdate()
            }

            Button {
                updateStore.performUpdate()
            } label: {
                if updateStore.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("update.now", systemImage: "arrow.down.circle.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(updateStore.isUpdating)
        }
    }
}
```

**Step 2: Build to verify**

Run: `xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Debug -derivedDataPath build build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add TokenEaterApp/UpdateModalView.swift
git commit -m "feat(update): add update modal view"
```

---

### Task 5: Modify SettingsView

**Files:**
- Modify: `TokenEaterApp/SettingsView.swift`

Three changes:
1. Replace hardcoded `"v4.0.0"` with dynamic version from Bundle
2. Add orange "New" badge when update available (opens modal on click)
3. Add "Check for updates" button in connection tab

**Step 1: Add UpdateStore environment and replace hardcoded version**

In the state section at the top (after existing `@Environment` declarations), add:
```swift
@Environment(UpdateStore.self) private var updateStore
```

Replace the header version text (line ~42):
```swift
// OLD:
Text("v4.0.0")
    .font(.caption2)
    .foregroundStyle(.tertiary)

// NEW:
HStack(spacing: 6) {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    Text("v\(version)")
        .font(.caption2)
        .foregroundStyle(.tertiary)
    if updateStore.updateAvailable {
        Button {
            updateStore.showUpdateModal = true
        } label: {
            Text("update.badge")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(accent.opacity(0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
```

**Step 2: Add "Check for updates" button in connectionTab**

In the connection tab, in the last `Section` (the one with "settings.onboarding.reset"), add the check button above the reset button:

```swift
Section {
    HStack {
        Button("update.check") {
            Task { await updateStore.checkForUpdate(userInitiated: true) }
        }
        .disabled(updateStore.isChecking)

        if updateStore.isChecking {
            ProgressView()
                .controlSize(.small)
        }

        Spacer()

        if let error = updateStore.updateError {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.red)
        } else if updateStore.updateAvailable {
            Text("update.badge")
                .font(.caption2)
                .foregroundStyle(.green)
        }
    }

    Button("settings.onboarding.reset") {
        settingsStore.hasCompletedOnboarding = false
    }
    .foregroundStyle(.secondary)
}
```

**Step 3: Build to verify**

Run: `xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Debug -derivedDataPath build build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add TokenEaterApp/SettingsView.swift
git commit -m "feat(update): dynamic version display, update badge, and check button in settings"
```

---

### Task 6: Wire UpdateStore in TokenEaterApp.swift

**Files:**
- Modify: `TokenEaterApp/TokenEaterApp.swift`

Three changes:
1. Add `@State private var updateStore = UpdateStore()`
2. Add `.environment(updateStore)` on both WindowGroup and MenuBarExtra
3. Add `.sheet` for UpdateModalView bound to `updateStore.showUpdateModal`
4. Start auto-check when onboarding is completed

**Step 1: Apply changes to TokenEaterApp.swift**

```swift
// TokenEaterApp/TokenEaterApp.swift
import SwiftUI

@main
struct TokenEaterApp: App {
    @State private var usageStore = UsageStore()
    @State private var themeStore = ThemeStore()
    @State private var settingsStore = SettingsStore()
    @State private var updateStore = UpdateStore()

    init() {
        NotificationService().setupDelegate()
    }

    var body: some Scene {
        WindowGroup(id: "settings") {
            if settingsStore.hasCompletedOnboarding {
                SettingsView()
                    .sheet(isPresented: Bindable(updateStore).showUpdateModal) {
                        UpdateModalView()
                            .environment(updateStore)
                    }
            } else {
                OnboardingView()
            }
        }
        .environment(usageStore)
        .environment(themeStore)
        .environment(settingsStore)
        .environment(updateStore)
        .onChange(of: settingsStore.hasCompletedOnboarding) { _, completed in
            if completed {
                usageStore.proxyConfig = settingsStore.proxyConfig
                usageStore.reloadConfig(thresholds: themeStore.thresholds)
                themeStore.syncToSharedFile()
                updateStore.startAutoCheck()
            }
        }
        .windowResizability(.contentSize)

        MenuBarExtra(isInserted: Bindable(settingsStore).showMenuBar) {
            MenuBarPopoverView()
                .environment(usageStore)
                .environment(themeStore)
                .environment(settingsStore)
                .environment(updateStore)
        } label: {
            Image(nsImage: menuBarImage)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarImage: NSImage {
        MenuBarRenderer.render(MenuBarRenderer.RenderData(
            pinnedMetrics: settingsStore.pinnedMetrics,
            fiveHourPct: usageStore.fiveHourPct,
            sevenDayPct: usageStore.sevenDayPct,
            sonnetPct: usageStore.sonnetPct,
            pacingDelta: usageStore.pacingDelta,
            pacingZone: usageStore.pacingZone,
            pacingDisplayMode: settingsStore.pacingDisplayMode,
            hasConfig: usageStore.hasConfig,
            hasError: usageStore.hasError,
            colorForPct: { themeStore.menuBarNSColor(for: $0) },
            colorForZone: { themeStore.menuBarPacingNSColor(for: $0) }
        ))
    }
}
```

Note: `updateStore.startAutoCheck()` is called when onboarding completes. For users who already completed onboarding, we also need to start auto-check. Add an `.onAppear` to SettingsView or check in the WindowGroup. The simplest approach: call `startAutoCheck()` unconditionally if onboarding is already completed. Add this to the `init()`:

Actually, `init()` runs before the body is evaluated, so stores aren't ready. Instead, add `.task {}` modifier:

```swift
// On the WindowGroup, add:
.task {
    if settingsStore.hasCompletedOnboarding {
        updateStore.startAutoCheck()
    }
}
```

**Step 2: Build to verify**

Run: `xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Debug -derivedDataPath build build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add TokenEaterApp/TokenEaterApp.swift
git commit -m "feat(update): wire UpdateStore into app lifecycle"
```

---

### Task 7: Add localization strings

**Files:**
- Modify: `Shared/en.lproj/Localizable.strings`
- Modify: `Shared/fr.lproj/Localizable.strings`

**Step 1: Add English strings**

Append to `Shared/en.lproj/Localizable.strings`:

```
/* Update */
"update.available" = "Update available";
"update.releasenotes" = "What's new";
"update.skip" = "Skip this version";
"update.later" = "Later";
"update.now" = "Update";
"update.check" = "Check for updates";
"update.badge" = "New";
"update.error.response" = "Couldn't reach GitHub — try again later";
"update.error.script" = "Failed to prepare update script";
"update.error.launch" = "Couldn't launch updater — command copied to clipboard. Paste in Terminal.";
```

**Step 2: Add French strings**

Append to `Shared/fr.lproj/Localizable.strings`:

```
/* Update */
"update.available" = "Mise à jour disponible";
"update.releasenotes" = "Nouveautés";
"update.skip" = "Ignorer cette version";
"update.later" = "Plus tard";
"update.now" = "Mettre à jour";
"update.check" = "Vérifier les mises à jour";
"update.badge" = "New";
"update.error.response" = "Impossible de joindre GitHub — réessayez plus tard";
"update.error.script" = "Impossible de préparer le script de mise à jour";
"update.error.launch" = "Impossible de lancer la mise à jour — commande copiée. Collez-la dans Terminal.";
```

**Step 3: Build to verify**

Run: `xcodegen generate && xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Debug -derivedDataPath build build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add Shared/en.lproj/Localizable.strings Shared/fr.lproj/Localizable.strings
git commit -m "feat(update): add en/fr localization strings for update system"
```

---

### Task 8: Final build verification

**Step 1: Full clean build**

Run:
```bash
xcodegen generate && \
DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject 2>/dev/null | grep -oE 'OU=[A-Z0-9]{10}' | head -1 | cut -d= -f2) && \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM clean build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 2: Verify no regressions**

- Open the built app from `build/Build/Products/Release/TokenEater.app`
- Verify settings window opens
- Verify version displays dynamically (not hardcoded)
- Verify "Check for updates" button appears in Connection tab
- Since current version matches latest release, update should NOT be detected

**Step 3: Final commit (if any fixups needed)**

```bash
git add -A && git commit -m "fix(update): build fixups"
```

---

### Post-implementation: Homebrew Cask flag

After merging and releasing the first version with auto-update, add `auto_updates true` to `Casks/tokeneater.rb` in the `AThevon/homebrew-tokeneater` tap. This prevents `brew upgrade` from re-upgrading an app that already updated itself.
