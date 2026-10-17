import SwiftUI

/// The label over one dashboard column once several Claude accounts share
/// the page: a mark (the account's dot, or the provider's glyph for Codex)
/// and the column's name. Its own view so the what's-new screen shows the
/// same header the dashboard draws.
struct DashboardColumnHeader<Mark: View>: View {
    let title: String
    /// The full name on hover, for an account name the column truncates.
    var hoverText: String? = nil
    @ViewBuilder let mark: () -> Mark

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            mark()
            Text(title)
                .lineLimit(1)
                .help(hoverText ?? "")
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(DS.Palette.textSecondary)
        .frame(height: 14)
    }
}

extension DashboardColumnHeader where Mark == AccountDot {
    /// A Claude account's column: its colour dot and its name.
    init(accountName: String, colorHex: String) {
        self.init(title: accountName, hoverText: accountName) {
            AccountDot(colorHex: colorHex, size: 8)
        }
    }
}
