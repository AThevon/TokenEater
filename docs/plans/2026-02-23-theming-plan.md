# Theming Tab Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a centralized theming system with presets, custom colors, configurable thresholds, and a monochrome menu bar toggle.

**Architecture:** A `ThemeManager` singleton (ObservableObject) in `Shared/` replaces all hardcoded colors. The app persists via UserDefaults and syncs to `shared.json` for the widget. Color helpers live on `ThemeColors` so both app and widget can use them.

**Tech Stack:** SwiftUI, WidgetKit, macOS 14+, XcodeGen

**Design doc:** `docs/plans/2026-02-23-theming-design.md`

---

### Task 1: Add Color helpers to Extensions.swift

**Files:**
- Modify: `Shared/Extensions.swift`

**Step 1: Add `Color.lighter(by:)` and `NSColor.init(hex:)`**

Add after the existing `Color.init(hex:)` extension (line 18):

```swift
extension Color {
    /// Returns a lighter version of this color by the given factor (0.0 – 1.0).
    func lighter(by amount: Double = 0.15) -> Color {
        let nsColor = NSColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        converted.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(
            hue: Double(h),
            saturation: Double(max(s - CGFloat(amount) * 0.3, 0)),
            brightness: Double(min(b + CGFloat(amount), 1.0)),
            opacity: Double(a)
        )
    }
}

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgbValue & 0x0000FF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
```

**Step 2: Build to verify**

```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Release -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shared/Extensions.swift
git commit -m "feat(theme): add Color.lighter(by:) and NSColor hex init"
```

---

### Task 2: Create ThemeColors.swift

**Files:**
- Create: `Shared/ThemeColors.swift`

**Step 1: Create the file with data models, presets, and color helpers**

```swift
import SwiftUI

// MARK: - Theme Colors

struct ThemeColors: Codable, Equatable {
    var gaugeNormal: String
    var gaugeWarning: String
    var gaugeCritical: String
    var pacingChill: String
    var pacingOnTrack: String
    var pacingHot: String
    var widgetBackground: String
    var widgetText: String

    // MARK: Presets

    static let `default` = ThemeColors(
        gaugeNormal: "#22C55E",
        gaugeWarning: "#F97316",
        gaugeCritical: "#EF4444",
        pacingChill: "#32D74B",
        pacingOnTrack: "#0A84FF",
        pacingHot: "#FF453A",
        widgetBackground: "#000000",
        widgetText: "#FFFFFF"
    )

    static let monochrome = ThemeColors(
        gaugeNormal: "#8E8E93",
        gaugeWarning: "#C7C7CC",
        gaugeCritical: "#FFFFFF",
        pacingChill: "#8E8E93",
        pacingOnTrack: "#AEAEB2",
        pacingHot: "#FFFFFF",
        widgetBackground: "#000000",
        widgetText: "#FFFFFF"
    )

    static let neon = ThemeColors(
        gaugeNormal: "#00FF87",
        gaugeWarning: "#FFD000",
        gaugeCritical: "#FF006E",
        pacingChill: "#00FF87",
        pacingOnTrack: "#00D4FF",
        pacingHot: "#FF006E",
        widgetBackground: "#0A0A0A",
        widgetText: "#FFFFFF"
    )

    static let pastel = ThemeColors(
        gaugeNormal: "#86EFAC",
        gaugeWarning: "#FDE68A",
        gaugeCritical: "#FCA5A5",
        pacingChill: "#86EFAC",
        pacingOnTrack: "#93C5FD",
        pacingHot: "#FCA5A5",
        widgetBackground: "#1A1A2E",
        widgetText: "#E2E8F0"
    )

    static let allPresets: [(key: String, label: String, colors: ThemeColors)] = [
        ("default", String(localized: "theme.default"), .default),
        ("monochrome", String(localized: "theme.monochrome"), .monochrome),
        ("neon", String(localized: "theme.neon"), .neon),
        ("pastel", String(localized: "theme.pastel"), .pastel),
    ]

    static func preset(for key: String) -> ThemeColors? {
        allPresets.first { $0.key == key }?.colors
    }

    // MARK: Color Helpers

    func gaugeColor(for pct: Double, thresholds: UsageThresholds) -> Color {
        if pct >= Double(thresholds.criticalPercent) { return Color(hex: gaugeCritical) }
        if pct >= Double(thresholds.warningPercent) { return Color(hex: gaugeWarning) }
        return Color(hex: gaugeNormal)
    }

    func gaugeGradient(for pct: Double, thresholds: UsageThresholds, startPoint: UnitPoint = .topLeading, endPoint: UnitPoint = .bottomTrailing) -> LinearGradient {
        let base = gaugeColor(for: pct, thresholds: thresholds)
        return LinearGradient(colors: [base, base.lighter()], startPoint: startPoint, endPoint: endPoint)
    }

    func pacingColor(for zone: PacingZone) -> Color {
        switch zone {
        case .chill: return Color(hex: pacingChill)
        case .onTrack: return Color(hex: pacingOnTrack)
        case .hot: return Color(hex: pacingHot)
        }
    }

    func pacingGradient(for zone: PacingZone, startPoint: UnitPoint = .topLeading, endPoint: UnitPoint = .bottomTrailing) -> LinearGradient {
        let base = pacingColor(for: zone)
        return LinearGradient(colors: [base, base.lighter()], startPoint: startPoint, endPoint: endPoint)
    }

    func gaugeNSColor(for pct: Double, thresholds: UsageThresholds) -> NSColor {
        if pct >= Double(thresholds.criticalPercent) { return NSColor(hex: gaugeCritical) }
        if pct >= Double(thresholds.warningPercent) { return NSColor(hex: gaugeWarning) }
        return NSColor(hex: gaugeNormal)
    }

    func pacingNSColor(for zone: PacingZone) -> NSColor {
        switch zone {
        case .chill: return NSColor(hex: pacingChill)
        case .onTrack: return NSColor(hex: pacingOnTrack)
        case .hot: return NSColor(hex: pacingHot)
        }
    }
}

// MARK: - Usage Thresholds

struct UsageThresholds: Codable, Equatable {
    var warningPercent: Int
    var criticalPercent: Int

    static let `default` = UsageThresholds(warningPercent: 60, criticalPercent: 85)
}
```

**Step 2: Build to verify**

```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Release -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shared/ThemeColors.swift
git commit -m "feat(theme): add ThemeColors model with presets and color helpers"
```

---

### Task 3: Update SharedContainer.swift

**Files:**
- Modify: `Shared/SharedContainer.swift`

**Step 1: Add theme and thresholds to SharedData**

Add two optional fields to the `SharedData` struct (line 25, before closing brace):

```swift
        var theme: ThemeColors?
        var thresholds: UsageThresholds?
```

**Step 2: Add theme and thresholds accessors**

Add after the `lastSyncDate` computed property (after line 72), before `// MARK: - Atomic Updates`:

```swift
    // MARK: - Theme

    static var theme: ThemeColors {
        get { load().theme ?? .default }
        set {
            var data = load()
            data.theme = newValue
            save(data)
        }
    }

    // MARK: - Thresholds

    static var thresholds: UsageThresholds {
        get { load().thresholds ?? .default }
        set {
            var data = load()
            data.thresholds = newValue
            save(data)
        }
    }
```

**Step 3: Build to verify**

```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Release -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add Shared/SharedContainer.swift
git commit -m "feat(theme): add theme and thresholds to SharedContainer"
```

---

### Task 4: Create ThemeManager.swift

**Files:**
- Create: `Shared/ThemeManager.swift`

**Step 1: Create the ThemeManager singleton**

```swift
import SwiftUI
import WidgetKit

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var selectedPreset: String {
        didSet {
            UserDefaults.standard.set(selectedPreset, forKey: "selectedPreset")
            scheduleSync()
        }
    }

    @Published var customTheme: ThemeColors {
        didSet {
            if let data = try? JSONEncoder().encode(customTheme),
               let json = String(data: data, encoding: .utf8) {
                UserDefaults.standard.set(json, forKey: "customThemeJSON")
            }
            scheduleSync()
        }
    }

    @Published var warningThreshold: Int {
        didSet {
            UserDefaults.standard.set(warningThreshold, forKey: "warningThreshold")
            scheduleSync()
        }
    }

    @Published var criticalThreshold: Int {
        didSet {
            UserDefaults.standard.set(criticalThreshold, forKey: "criticalThreshold")
            scheduleSync()
        }
    }

    @Published var menuBarMonochrome: Bool {
        didSet {
            UserDefaults.standard.set(menuBarMonochrome, forKey: "menuBarMonochrome")
        }
    }

    // MARK: - Resolved Theme

    var current: ThemeColors {
        if selectedPreset == "custom" { return customTheme }
        return ThemeColors.preset(for: selectedPreset) ?? .default
    }

    var thresholds: UsageThresholds {
        UsageThresholds(warningPercent: warningThreshold, criticalPercent: criticalThreshold)
    }

    // MARK: - Menu Bar (respects monochrome toggle)

    func menuBarNSColor(for pct: Int) -> NSColor {
        if menuBarMonochrome { return .white }
        return current.gaugeNSColor(for: Double(pct), thresholds: thresholds)
    }

    func menuBarPacingNSColor(for zone: PacingZone) -> NSColor {
        if menuBarMonochrome { return .white }
        return current.pacingNSColor(for: zone)
    }

    // MARK: - Reset

    func resetToDefaults() {
        selectedPreset = "default"
        customTheme = .default
        warningThreshold = 60
        criticalThreshold = 85
        menuBarMonochrome = false
        syncToSharedContainer()
    }

    // MARK: - Init

    private init() {
        self.selectedPreset = UserDefaults.standard.string(forKey: "selectedPreset") ?? "default"
        self.warningThreshold = {
            let val = UserDefaults.standard.integer(forKey: "warningThreshold")
            return val > 0 ? val : 60
        }()
        self.criticalThreshold = {
            let val = UserDefaults.standard.integer(forKey: "criticalThreshold")
            return val > 0 ? val : 85
        }()
        self.menuBarMonochrome = UserDefaults.standard.bool(forKey: "menuBarMonochrome")

        if let json = UserDefaults.standard.string(forKey: "customThemeJSON"),
           let data = json.data(using: .utf8),
           let theme = try? JSONDecoder().decode(ThemeColors.self, from: data) {
            self.customTheme = theme
        } else {
            self.customTheme = .default
        }
    }

    // MARK: - Sync (debounced)

    private var syncWorkItem: DispatchWorkItem?

    private func scheduleSync() {
        syncWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.syncToSharedContainer()
            }
        }
        syncWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    func syncToSharedContainer() {
        SharedContainer.theme = current
        SharedContainer.thresholds = thresholds
        WidgetCenter.shared.reloadAllTimelines()
    }
}
```

**Step 2: Build to verify**

```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Release -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shared/ThemeManager.swift
git commit -m "feat(theme): add ThemeManager singleton with debounced sync"
```

---

### Task 5: Refactor UsageNotificationManager.swift

**Files:**
- Modify: `Shared/UsageNotificationManager.swift`

**Step 1: Replace hardcoded thresholds in UsageLevel**

Replace `UsageLevel.from(pct:)` (lines 13-17) with a version that accepts thresholds:

```swift
    static func from(pct: Int, thresholds: UsageThresholds = .default) -> UsageLevel {
        if pct >= thresholds.criticalPercent { return .red }
        if pct >= thresholds.warningPercent { return .orange }
        return .green
    }
```

**Step 2: Update checkThresholds to accept thresholds**

Replace the `checkThresholds` signature (line 27) and the `check` function (line 33):

```swift
    static func checkThresholds(fiveHour: Int, sevenDay: Int, sonnet: Int, thresholds: UsageThresholds = .default) {
        check(metric: "fiveHour", label: String(localized: "metric.session"), pct: fiveHour, thresholds: thresholds)
        check(metric: "sevenDay", label: String(localized: "metric.weekly"), pct: sevenDay, thresholds: thresholds)
        check(metric: "sonnet", label: String(localized: "metric.sonnet"), pct: sonnet, thresholds: thresholds)
    }

    private static func check(metric: String, label: String, pct: Int, thresholds: UsageThresholds) {
        let key = "lastLevel_\(metric)"
        let previousRaw = UserDefaults.standard.integer(forKey: key)
        let previous = UsageLevel(rawValue: previousRaw) ?? .green
        let current = UsageLevel.from(pct: pct, thresholds: thresholds)
```

(rest of `check` stays the same)

**Step 3: Build to verify**

```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Release -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add Shared/UsageNotificationManager.swift
git commit -m "refactor(theme): use dynamic thresholds in UsageNotificationManager"
```

---

### Task 6: Refactor MenuBarView.swift (ViewModel + Popover)

**Files:**
- Modify: `ClaudeUsageApp/MenuBarView.swift`

This is the largest refactoring task. The ViewModel uses NSColor for menu bar rendering, and the Popover uses SwiftUI Color for UI elements. Both need to delegate to ThemeManager.

**Step 1: Update MenuBarViewModel — replace color functions**

In `MenuBarViewModel`, replace `nsColorForPct` (lines 290-294) with:

```swift
    private func nsColorForPct(_ pct: Int) -> NSColor {
        ThemeManager.shared.menuBarNSColor(for: pct)
    }
```

Replace `nsColorForZone` (lines 296-301) with:

```swift
    private func nsColorForZone(_ zone: PacingZone) -> NSColor {
        ThemeManager.shared.menuBarPacingNSColor(for: zone)
    }
```

Update `refresh()` (line 155-158) to pass thresholds:

```swift
            UsageNotificationManager.checkThresholds(
                fiveHour: fiveHourPct,
                sevenDay: sevenDayPct,
                sonnet: sonnetPct,
                thresholds: ThemeManager.shared.thresholds
            )
```

**Step 2: Update MenuBarPopoverView — replace color functions**

Add a theme property at the top of `MenuBarPopoverView`:

```swift
    @ObservedObject private var theme = ThemeManager.shared
```

Replace `colorForPct` (lines 518-522) with:

```swift
    private func colorForPct(_ pct: Int) -> Color {
        theme.current.gaugeColor(for: Double(pct), thresholds: theme.thresholds)
    }
```

Replace `gradientForPct` (lines 524-534) with:

```swift
    private func gradientForPct(_ pct: Int) -> LinearGradient {
        theme.current.gaugeGradient(for: Double(pct), thresholds: theme.thresholds, startPoint: .leading, endPoint: .trailing)
    }
```

Replace `colorForZone` (lines 499-505) with:

```swift
    private func colorForZone(_ zone: PacingZone) -> Color {
        theme.current.pacingColor(for: zone)
    }
```

Replace `gradientForZone` (lines 507-516) with:

```swift
    private func gradientForZone(_ zone: PacingZone) -> LinearGradient {
        theme.current.pacingGradient(for: zone, startPoint: .leading, endPoint: .trailing)
    }
```

**Step 3: Build to verify**

```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Release -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add ClaudeUsageApp/MenuBarView.swift
git commit -m "refactor(theme): use ThemeManager in MenuBarView"
```

---

### Task 7: Refactor UsageWidgetView.swift

**Files:**
- Modify: `ClaudeUsageWidget/UsageWidgetView.swift`

**Step 1: Add theme/thresholds properties to widget views**

In `UsageWidgetView`, add properties after `@Environment(\.widgetFamily) var family` (line 23):

```swift
    private var theme: ThemeColors { SharedContainer.theme }
    private var thresholds: UsageThresholds { SharedContainer.thresholds }
```

**Step 2: Update WidgetBackgroundModifier**

Replace `WidgetBackgroundModifier` (lines 6-16) with a parameterized version:

```swift
struct WidgetBackgroundModifier: ViewModifier {
    var backgroundColor: Color = Color(hex: SharedContainer.theme.widgetBackground).opacity(0.85)

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.containerBackground(for: .widget) {
                backgroundColor
            }
        } else {
            content.padding().background(backgroundColor)
        }
    }
}
```

**Step 3: Refactor CircularUsageView**

Add properties and replace `ringGradient`:

```swift
struct CircularUsageView: View {
    let label: String
    let resetInfo: String
    let utilization: Double
    var theme: ThemeColors = SharedContainer.theme
    var thresholds: UsageThresholds = SharedContainer.thresholds

    private var ringGradient: LinearGradient {
        theme.gaugeGradient(for: utilization, thresholds: thresholds)
    }
    // ... body stays the same
}
```

**Step 4: Refactor CircularPacingView**

Replace hardcoded colors:

```swift
struct CircularPacingView: View {
    let pacing: PacingResult
    var theme: ThemeColors = SharedContainer.theme

    private var ringColor: Color {
        theme.pacingColor(for: pacing.zone)
    }

    private var ringGradient: LinearGradient {
        theme.pacingGradient(for: pacing.zone)
    }
    // ... body stays the same
}
```

**Step 5: Refactor LargeUsageBarView**

Add theme/thresholds properties. Replace `barGradient` and `accentColor`:

```swift
struct LargeUsageBarView: View {
    let icon: String
    let label: String
    let subtitle: String
    let resetInfo: String
    let utilization: Double
    var colorOverride: Color? = nil
    var displayText: String? = nil
    var theme: ThemeColors = SharedContainer.theme
    var thresholds: UsageThresholds = SharedContainer.thresholds

    private var barGradient: LinearGradient {
        if let color = colorOverride {
            return LinearGradient(colors: [color, color.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        }
        return theme.gaugeGradient(for: utilization, thresholds: thresholds, startPoint: .leading, endPoint: .trailing)
    }

    private var accentColor: Color {
        if let color = colorOverride { return color }
        return theme.gaugeColor(for: utilization, thresholds: thresholds)
    }
    // ... body stays the same
}
```

**Step 6: Update pacing colorOverride in largeUsageContent**

In `largeUsageContent`, replace the pacing `colorOverride` closure (lines 177-183):

```swift
                    colorOverride: theme.pacingColor(for: pacing.zone),
```

**Step 7: Build to verify**

```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Release -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 8: Commit**

```bash
git add ClaudeUsageWidget/UsageWidgetView.swift
git commit -m "refactor(theme): use SharedContainer theme in UsageWidgetView"
```

---

### Task 8: Refactor PacingWidgetView.swift

**Files:**
- Modify: `ClaudeUsageWidget/PacingWidgetView.swift`

**Step 1: Add theme property and replace color functions**

Add to `PacingWidgetView` after `let entry: UsageEntry`:

```swift
    private var theme: ThemeColors { SharedContainer.theme }
```

Replace `colorForZone` (lines 90-96):

```swift
    private func colorForZone(_ zone: PacingZone) -> Color {
        theme.pacingColor(for: zone)
    }
```

Replace `gradientForZone` (lines 98-107):

```swift
    private func gradientForZone(_ zone: PacingZone) -> LinearGradient {
        theme.pacingGradient(for: zone)
    }
```

**Step 2: Build to verify**

```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Release -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add ClaudeUsageWidget/PacingWidgetView.swift
git commit -m "refactor(theme): use SharedContainer theme in PacingWidgetView"
```

---

### Task 9: Add Theming tab to SettingsView.swift

**Files:**
- Modify: `ClaudeUsageApp/SettingsView.swift`

**Step 1: Add ThemeManager observation**

Add after the existing `@AppStorage` declarations (around line 29):

```swift
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var showResetAlert = false
```

**Step 2: Add the theming tab to the TabView**

Insert between `displayTab` and `proxyTab` in the TabView (after line 68):

```swift
                themingTab
                    .tabItem {
                        Label("settings.tab.theming", systemImage: "paintpalette.fill")
                    }
```

**Step 3: Increase window height**

Change `.frame(width: 500, height: 400)` (line 75) to:

```swift
        .frame(width: 500, height: 480)
```

**Step 4: Implement the themingTab computed property**

Add before `// MARK: - Proxy Tab` (line 202):

```swift
    // MARK: - Theming Tab

    private var themingTab: some View {
        Form {
            // Preset picker
            Section("settings.theme.colors") {
                Picker("settings.theme.preset", selection: $themeManager.selectedPreset) {
                    ForEach(ThemeColors.allPresets, id: \.key) { preset in
                        Text(preset.label).tag(preset.key)
                    }
                    Divider()
                    Text("settings.theme.custom").tag("custom")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: themeManager.selectedPreset) { newValue in
                    if newValue == "custom" {
                        // Initialize custom from current preset
                        if let previous = ThemeColors.preset(for: themeManager.selectedPreset) {
                            // Already switched, use the old value
                        } else {
                            themeManager.customTheme = themeManager.current
                        }
                    }
                }
            }

            // Custom color pickers (only visible when Custom is selected)
            if themeManager.selectedPreset == "custom" {
                Section("settings.theme.custom.colors") {
                    themeColorPicker("settings.theme.gauge.normal", hex: $themeManager.customTheme.gaugeNormal)
                    themeColorPicker("settings.theme.gauge.warning", hex: $themeManager.customTheme.gaugeWarning)
                    themeColorPicker("settings.theme.gauge.critical", hex: $themeManager.customTheme.gaugeCritical)
                    Divider()
                    themeColorPicker("settings.theme.pacing.chill", hex: $themeManager.customTheme.pacingChill)
                    themeColorPicker("settings.theme.pacing.ontrack", hex: $themeManager.customTheme.pacingOnTrack)
                    themeColorPicker("settings.theme.pacing.hot", hex: $themeManager.customTheme.pacingHot)
                    Divider()
                    themeColorPicker("settings.theme.widget.bg", hex: $themeManager.customTheme.widgetBackground)
                    themeColorPicker("settings.theme.widget.text", hex: $themeManager.customTheme.widgetText)
                }
            }

            // Threshold sliders
            Section("settings.theme.thresholds") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("settings.theme.warning")
                            .frame(width: 60, alignment: .leading)
                        Slider(value: Binding(
                            get: { Double(themeManager.warningThreshold) },
                            set: { newVal in
                                let val = Int(newVal)
                                themeManager.warningThreshold = val
                                if themeManager.criticalThreshold <= val {
                                    themeManager.criticalThreshold = min(val + 5, 95)
                                }
                            }
                        ), in: 10...90, step: 5)
                        Text("\(themeManager.warningThreshold)%")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                    HStack {
                        Text("settings.theme.critical")
                            .frame(width: 60, alignment: .leading)
                        Slider(value: Binding(
                            get: { Double(themeManager.criticalThreshold) },
                            set: { newVal in
                                let val = Int(newVal)
                                themeManager.criticalThreshold = val
                                if themeManager.warningThreshold >= val {
                                    themeManager.warningThreshold = max(val - 5, 10)
                                }
                            }
                        ), in: 15...95, step: 5)
                        Text("\(themeManager.criticalThreshold)%")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }

            // Menu bar monochrome
            Section("settings.theme.menubar") {
                Toggle("settings.theme.monochrome", isOn: $themeManager.menuBarMonochrome)
            }

            // Live preview
            Section("settings.theme.preview") {
                HStack(spacing: 16) {
                    themePreviewGauge(
                        pct: Double(max(themeManager.warningThreshold - 15, 5)),
                        label: String(localized: "settings.theme.preview.normal")
                    )
                    themePreviewGauge(
                        pct: Double(themeManager.warningThreshold + (themeManager.criticalThreshold - themeManager.warningThreshold) / 2),
                        label: String(localized: "settings.theme.preview.warning")
                    )
                    themePreviewGauge(
                        pct: Double(min(themeManager.criticalThreshold + 5, 100)),
                        label: String(localized: "settings.theme.preview.critical")
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

            // Reset
            Section {
                Button("settings.theme.reset", role: .destructive) {
                    showResetAlert = true
                }
                .alert("settings.theme.reset.confirm", isPresented: $showResetAlert) {
                    Button("settings.theme.reset.cancel", role: .cancel) {}
                    Button("settings.theme.reset.action", role: .destructive) {
                        themeManager.resetToDefaults()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Theme Helpers

    private func themeColorPicker(_ titleKey: LocalizedStringKey, hex: Binding<String>) -> some View {
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
        return ColorPicker(titleKey, selection: colorBinding, supportsOpacity: false)
    }

    private func themePreviewGauge(pct: Double, label: String) -> some View {
        let theme = themeManager.current
        let thresholds = themeManager.thresholds
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: min(pct, 100) / 100)
                    .stroke(
                        theme.gaugeGradient(for: pct, thresholds: thresholds),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(Int(pct))%")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
```

**Step 5: Handle preset→custom initialization properly**

Replace the `onChange(of: themeManager.selectedPreset)` inside the preset picker section with a cleaner version. The initial `onChange` above has a logic issue. Replace it with:

```swift
                .onChange(of: themeManager.selectedPreset) { [oldPreset = themeManager.selectedPreset] newValue in
                    if newValue == "custom", let source = ThemeColors.preset(for: oldPreset) {
                        themeManager.customTheme = source
                    }
                }
```

Note: this captures `oldPreset` before the change to initialize the custom theme from the previous preset.

**Step 6: Build to verify**

```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Release -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED (there may be warnings about missing localization keys — that's expected, we handle them in Task 10)

**Step 7: Commit**

```bash
git add ClaudeUsageApp/SettingsView.swift
git commit -m "feat(theme): add Theming tab to SettingsView"
```

---

### Task 10: Add localization keys

**Files:**
- Modify: localization files (find with `find . -name "Localizable.strings" -o -name "Localizable.xcstrings"`)

**Step 1: Find existing localization files**

```bash
find . -name "*.xcstrings" -o -name "*.strings" | head -20
```

**Step 2: Add missing keys**

New keys needed:
- `settings.tab.theming` = "Theming"
- `settings.theme.colors` = "Color Theme"
- `settings.theme.preset` = "Preset"
- `settings.theme.custom` = "Custom"
- `settings.theme.custom.colors` = "Custom Colors"
- `settings.theme.gauge.normal` = "Gauge Normal"
- `settings.theme.gauge.warning` = "Gauge Warning"
- `settings.theme.gauge.critical` = "Gauge Critical"
- `settings.theme.pacing.chill` = "Pacing Chill"
- `settings.theme.pacing.ontrack` = "Pacing On Track"
- `settings.theme.pacing.hot` = "Pacing Hot"
- `settings.theme.widget.bg` = "Widget Background"
- `settings.theme.widget.text` = "Widget Text"
- `settings.theme.thresholds` = "Usage Thresholds"
- `settings.theme.warning` = "Warning"
- `settings.theme.critical` = "Critical"
- `settings.theme.menubar` = "Menu Bar"
- `settings.theme.monochrome` = "Monochrome menu bar"
- `settings.theme.preview` = "Preview"
- `settings.theme.preview.normal` = "Normal"
- `settings.theme.preview.warning` = "Warning"
- `settings.theme.preview.critical` = "Critical"
- `settings.theme.reset` = "Reset to Defaults"
- `settings.theme.reset.confirm` = "Reset all theming settings?"
- `settings.theme.reset.cancel` = "Cancel"
- `settings.theme.reset.action` = "Reset"
- `theme.default` = "Default"
- `theme.monochrome` = "Monochrome"
- `theme.neon` = "Neon"
- `theme.pastel` = "Pastel"

Add to the appropriate localization file(s) for both EN and FR if present.

**Step 3: Build to verify**

```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Release -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add -A -- '*.xcstrings' '*.strings'
git commit -m "feat(theme): add localization keys for theming tab"
```

---

### Task 11: Initial theme sync on app launch

**Files:**
- Modify: `ClaudeUsageApp/ClaudeUsageApp.swift` (or wherever the app's `@main` entry point is)

**Step 1: Find the app entry point**

```bash
grep -r "@main" ClaudeUsageApp/
```

**Step 2: Add initial sync**

In the app's `init()` or `.onAppear`, call:

```swift
ThemeManager.shared.syncToSharedContainer()
```

This ensures the widget has theme data on first launch.

**Step 3: Build to verify**

```bash
xcodegen generate && xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Release -derivedDataPath build DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add ClaudeUsageApp/ClaudeUsageApp.swift
git commit -m "feat(theme): sync theme to SharedContainer on app launch"
```

---

### Task 12: Full build and manual test

**Step 1: Clean build**

```bash
rm -rf build
xcodegen generate
xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Release -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED with 0 errors

**Step 2: Install and test (follow CLAUDE.md nuclear cleanup)**

```bash
killall TokenEater 2>/dev/null; killall NotificationCenter 2>/dev/null; killall chronod 2>/dev/null
rm -rf ~/Library/Application\ Support/com.claudeusagewidget.shared
rm -rf ~/Library/Group\ Containers/group.com.claudeusagewidget.shared
pluginkit -r -i com.claudeusagewidget.app.widget 2>/dev/null
sleep 2
rm -rf /Applications/TokenEater.app
cp -R build/Build/Products/Release/TokenEater.app /Applications/
xattr -cr /Applications/TokenEater.app
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R /Applications/TokenEater.app
sleep 2
open /Applications/TokenEater.app
```

**Step 3: Manual test checklist**

- [ ] Settings → Theming tab appears between Display and Proxy
- [ ] Default preset is selected, 3 preview gauges show correct colors
- [ ] Switching presets updates previews immediately
- [ ] Selecting Custom reveals 8 color pickers
- [ ] Custom color changes update previews live
- [ ] Warning/Critical sliders work, warning stays below critical
- [ ] Monochrome toggle makes menu bar white
- [ ] Reset to Defaults asks confirmation and restores everything
- [ ] Widget updates after theme change (may need to re-add widget)
- [ ] Menu bar colors match the selected theme

**Step 4: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix(theme): post-testing adjustments"
```
