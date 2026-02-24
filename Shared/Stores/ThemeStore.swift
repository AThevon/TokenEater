import SwiftUI
import WidgetKit

@MainActor
@Observable
final class ThemeStore {
    var selectedPreset: String {
        didSet {
            UserDefaults.standard.set(selectedPreset, forKey: "selectedPreset")
            scheduleSync()
        }
    }

    var customTheme: ThemeColors {
        didSet {
            if let data = try? JSONEncoder().encode(customTheme),
               let json = String(data: data, encoding: .utf8) {
                UserDefaults.standard.set(json, forKey: "customThemeJSON")
            }
            scheduleSync()
        }
    }

    var warningThreshold: Int {
        didSet {
            UserDefaults.standard.set(warningThreshold, forKey: "warningThreshold")
            scheduleSync()
        }
    }

    var criticalThreshold: Int {
        didSet {
            UserDefaults.standard.set(criticalThreshold, forKey: "criticalThreshold")
            scheduleSync()
        }
    }

    var menuBarMonochrome: Bool {
        didSet {
            UserDefaults.standard.set(menuBarMonochrome, forKey: "menuBarMonochrome")
        }
    }

    private let sharedFileService: SharedFileServiceProtocol

    init(sharedFileService: SharedFileServiceProtocol = SharedFileService()) {
        self.sharedFileService = sharedFileService

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

    // MARK: - Resolved

    var current: ThemeColors {
        if selectedPreset == "custom" { return customTheme }
        return ThemeColors.preset(for: selectedPreset) ?? .default
    }

    var thresholds: UsageThresholds {
        UsageThresholds(warningPercent: warningThreshold, criticalPercent: criticalThreshold)
    }

    // MARK: - Menu Bar Colors

    func menuBarNSColor(for pct: Int) -> NSColor {
        if menuBarMonochrome { return .labelColor }
        return current.gaugeNSColor(for: Double(pct), thresholds: thresholds)
    }

    func menuBarPacingNSColor(for zone: PacingZone) -> NSColor {
        if menuBarMonochrome { return .labelColor }
        return current.pacingNSColor(for: zone)
    }

    // MARK: - Reset

    func resetToDefaults() {
        selectedPreset = "default"
        customTheme = .default
        warningThreshold = 60
        criticalThreshold = 85
        menuBarMonochrome = false
        syncToSharedFile()
    }

    // MARK: - Sync (debounced)

    @ObservationIgnored private var syncWorkItem: DispatchWorkItem?

    private func scheduleSync() {
        syncWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.syncToSharedFile()
        }
        syncWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    func syncToSharedFile() {
        sharedFileService.updateTheme(current, thresholds: thresholds)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
