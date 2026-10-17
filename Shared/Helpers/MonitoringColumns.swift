import Foundation

/// The columns of the dashboard, left to right.
///
/// All compares everything that runs: one column per running Claude account,
/// the main one first, then Codex. A provider mode shows one column: Claude
/// mode the account it is focused on, Codex mode Codex. Pure, so the order
/// and the fallbacks are unit tested; `MonitoringView` only lays them out.
enum MonitoringColumns {
    enum Column: Hashable, Identifiable {
        case claude(AccountID)
        case codex

        var id: String {
            switch self {
            case .claude(let account): return "claude" + account.storageSuffix
            case .codex: return "codex"
            }
        }

        var provider: MetricProvider {
            switch self {
            case .claude: return .claude
            case .codex: return .codex
            }
        }
    }

    /// - Parameters:
    ///   - activeAccounts: the running Claude accounts in display order, the
    ///     main one first; empty while Claude is off.
    ///   - focused: the account Claude mode shows. One that no longer runs
    ///     falls back to the main account.
    static func columns(
        mode: ProviderMode,
        focused: AccountID,
        activeAccounts: [AccountID],
        codexEnabled: Bool
    ) -> [Column] {
        switch mode {
        case .all:
            return activeAccounts.map(Column.claude) + (codexEnabled ? [.codex] : [])
        case .claude:
            guard !activeAccounts.isEmpty else { return [] }
            return [.claude(activeAccounts.contains(focused) ? focused : .main)]
        case .codex:
            return codexEnabled ? [.codex] : []
        }
    }

    // MARK: - Rows

    /// Never more than two columns abreast: from three, a hero's number and
    /// every label truncate at an ordinary window width.
    static let maxPerRow = 2

    /// The narrowest a column may get and still sit next to another one once
    /// several accounts share the page. Below it, the columns stack.
    static let minimumSideBySideWidth: CGFloat = 360

    /// The narrowest page that still puts two columns abreast once there
    /// are more than two to lay out.
    static func twoAbreastMinimumWidth(spacing: CGFloat) -> CGFloat {
        minimumSideBySideWidth * CGFloat(maxPerRow) + spacing
    }

    /// How the columns wrap, row by row.
    ///
    /// One or two columns stay on one row whatever the width, which is the
    /// layout 6.0 had for Claude and Codex. From three, the columns go two by
    /// two in order (so Codex lands after the Claude accounts), or one per
    /// row when the page is narrower than `twoAbreastMinimumWidth`, which the
    /// view decides by measuring, not by storing a width.
    static func rows(_ columns: [Column], twoAbreast: Bool) -> [[Column]] {
        guard !columns.isEmpty else { return [] }
        guard columns.count > maxPerRow else { return [columns] }
        let perRow = twoAbreast ? maxPerRow : 1
        return stride(from: 0, to: columns.count, by: perRow).map {
            Array(columns[$0 ..< min($0 + perRow, columns.count)])
        }
    }
}
