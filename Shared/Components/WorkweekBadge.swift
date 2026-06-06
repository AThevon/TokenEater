import SwiftUI

/// Small glyph shown on weekly / Sonnet pacing surfaces when workweek pacing is
/// active, so the compressed ("days go faster") and frozen-on-off-days behaviour
/// is explained rather than looking broken. Switches to a "resting" variant on
/// off-days, where the expected pace is parked and the full quota is still
/// available until the real reset. Renders nothing when the schedule isn't
/// active (feature off or all seven days selected).
struct WorkweekBadge: View {
    let schedule: PacingSchedule
    var now: Date = Date()
    var tint: Color = Color.primary.opacity(0.45)

    var body: some View {
        if schedule.isActive {
            let offDay = schedule.isOffDay(now)
            let label = offDay
                ? String(localized: "pacing.workweek.badge.offday")
                : String(localized: "pacing.workweek.badge.active")
            Image(systemName: offDay ? "moon.zzz.fill" : "briefcase.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
                .help(label)
                .accessibilityLabel(label)
        }
    }
}
