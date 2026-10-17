import SwiftUI

/// Codex's plan, reset credits and balance, as one row of pills.
///
/// The dashboard's `footer` block draws this for Codex the way `footerPills`
/// draws Claude's. A block that only one provider could draw would not be a
/// block.
struct CodexFooterPills: View {
    @EnvironmentObject private var codexStore: CodexUsageStore

    var body: some View {
        DashboardPillRow(pills: Self.pills(codexStore))
    }

    /// Empty when Codex has nothing to say here, which the dashboard reads to
    /// leave the row out.
    @MainActor
    static func pills(_ codexStore: CodexUsageStore) -> [DashboardPill] {
        var pills: [DashboardPill] = []
        if codexStore.planType != .unknown {
            pills.append(DashboardPill(
                id: "tier", icon: "sparkles", label: String(localized: "dashboard.tier"),
                value: codexStore.planType.displayLabel, tint: codexStore.planType.badgeColor
            ))
        }
        if let resets = codexStore.lastUsage?.resetCreditsAvailable {
            pills.append(DashboardPill(
                id: "resets",
                icon: "arrow.counterclockwise",
                value: resets == 1
                    ? String(localized: "widget.codex.reset.single")
                    : String(format: String(localized: "widget.codex.resets"), max(0, resets)),
                tint: resets > 0 ? .orange : DS.Palette.textTertiary
            ))
        }
        // The credit balance used to be a bare line of small text under this
        // row, which read as a caption for the pills above rather than as
        // another fact of the same kind. It is the same kind of fact, so it
        // gets the same pill.
        if let credits = codexStore.credits {
            if credits.overageLimitReached == true {
                pills.append(DashboardPill(
                    id: "credits", icon: "exclamationmark.circle",
                    value: String(localized: "codex.credits.cap"), tint: .orange
                ))
            } else if credits.hasCredits == true {
                pills.append(DashboardPill(
                    id: "credits",
                    icon: "creditcard",
                    value: credits.unlimited == true
                        ? String(localized: "codex.credits.unlimited")
                        : String(format: String(localized: "codex.credits.balance"),
                                 credits.balance ?? "-"),
                    tint: DS.Palette.textTertiary
                ))
            }
        }
        return pills
    }
}
