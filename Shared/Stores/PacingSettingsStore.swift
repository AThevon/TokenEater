import Foundation

/// Pacing-domain slice of the user settings. Extracted from SettingsStore as the
/// first step of the fat-store split. Owns its own persistence + the shared-file
/// mirror so the (sandboxed) widget computes pacing identically.
@MainActor
final class PacingSettingsStore: ObservableObject {
    /// Acceptable distance ahead of linear pace, in percentage points, before the
    /// pacing zone turns warning/hot. Snapped to the nearest 5 and clamped to
    /// 5...30 when loaded (see init); the setter persists the raw value.
    @Published var margin: Int {
        didSet { UserDefaults.standard.set(margin, forKey: "pacingMargin") }
    }
    /// Workweek pacing: when on, the expected pace only advances over the user's
    /// active days, so off-days don't make them look ahead of pace.
    @Published var workweekEnabled: Bool {
        didSet {
            UserDefaults.standard.set(workweekEnabled, forKey: "pacingWorkweekEnabled")
            sharedFileService.updatePacingSchedule(schedule)
        }
    }
    /// Active weekday numbers (Gregorian 1=Sun ... 7=Sat) used when workweek
    /// pacing is on. Persisted as a sorted array.
    @Published var activeDays: Set<Int> {
        didSet {
            UserDefaults.standard.set(Array(activeDays).sorted(), forKey: "pacingActiveDays")
            sharedFileService.updatePacingSchedule(schedule)
        }
    }
    /// When on, workweek pacing is further narrowed to active hours of the day.
    @Published var hoursEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hoursEnabled, forKey: "pacingHoursEnabled")
            sharedFileService.updatePacingSchedule(schedule)
        }
    }
    /// Start hour (0...23) of the active window, applied to every active day.
    @Published var startHour: Int {
        didSet {
            UserDefaults.standard.set(startHour, forKey: "pacingStartHour")
            sharedFileService.updatePacingSchedule(schedule)
        }
    }
    /// End hour (1...24) of the active window, applied to every active day.
    @Published var endHour: Int {
        didSet {
            UserDefaults.standard.set(endHour, forKey: "pacingEndHour")
            sharedFileService.updatePacingSchedule(schedule)
        }
    }

    /// The resolved schedule handed to the pacing calculator + widget.
    var schedule: PacingSchedule {
        PacingSchedule(
            enabled: workweekEnabled,
            activeDays: activeDays,
            hoursEnabled: hoursEnabled,
            startHour: startHour,
            endHour: endHour
        )
    }

    private let sharedFileService: SharedFileServiceProtocol

    init(sharedFileService: SharedFileServiceProtocol) {
        self.sharedFileService = sharedFileService
        self.margin = {
            let val = UserDefaults.standard.integer(forKey: "pacingMargin")
            let raw = val > 0 ? val : 10
            let snapped = (Int((Double(raw) / 5.0).rounded()) * 5)
            return min(30, max(5, snapped))
        }()
        let enabled = SettingsDefaults.bool(key: "pacingWorkweekEnabled", default: false)
        let days: Set<Int> = {
            if let stored = UserDefaults.standard.array(forKey: "pacingActiveDays") as? [Int], !stored.isEmpty {
                return Set(stored)
            }
            return PacingSchedule.workweek
        }()
        self.workweekEnabled = enabled
        self.activeDays = days
        self.hoursEnabled = SettingsDefaults.bool(key: "pacingHoursEnabled", default: false)
        self.startHour = SettingsDefaults.int(key: "pacingStartHour", default: PacingSchedule.defaultStartHour)
        self.endHour = SettingsDefaults.int(key: "pacingEndHour", default: PacingSchedule.defaultEndHour)
        // Mirror the resolved schedule to the shared file so the (sandboxed)
        // widget computes pacing identically on first paint.
        sharedFileService.updatePacingSchedule(
            PacingSchedule(enabled: enabled, activeDays: days,
                           hoursEnabled: self.hoursEnabled,
                           startHour: self.startHour, endHour: self.endHour)
        )
    }
}

/// Single source of truth for the "absent vs. false / zero" UserDefaults reads.
/// `UserDefaults.bool/integer(forKey:)` cannot tell a missing key from a stored
/// false/0, which would silently override our intended defaults. Shared by
/// SettingsStore and its extracted domain slices.
enum SettingsDefaults {
    static func bool(key: String, default fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }
    static func int(key: String, default fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? fallback
    }
}
