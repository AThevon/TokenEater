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
}
