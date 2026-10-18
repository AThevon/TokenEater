import Foundation

/// The sections of the dashboard and how they wrap.
///
/// All shows every section that runs, in the order Studio gives them: one per
/// running Claude account and Codex. A provider mode shows one: Claude mode
/// the account it is focused on, Codex mode Codex. Pure, so the order, the
/// fallbacks and the layout rules are unit tested; `MonitoringView` only lays
/// them out.
enum MonitoringColumns {
    /// - Parameters:
    ///   - sections: the running sections in display order (see
    ///     `SettingsStore.runningSections`): no Claude account while Claude
    ///     is off, no Codex while Codex is.
    ///   - focused: the account Claude mode shows. One that no longer runs
    ///     falls back to the main account.
    static func columns(mode: ProviderMode, focused: AccountID, sections: [HomeSection]) -> [HomeSection] {
        switch mode {
        case .all:
            return sections
        case .claude:
            let accounts = sections.compactMap { section -> AccountID? in
                if case .claude(let account) = section { return account }
                return nil
            }
            guard !accounts.isEmpty else { return [] }
            return [.claude(accounts.contains(focused) ? focused : .main)]
        case .codex:
            return sections.contains(.codex) ? [.codex] : []
        }
    }

    // MARK: - Layout

    /// The narrowest a section may get and still sit next to another one.
    /// Below it the hero's number and the cards' labels start to truncate,
    /// so the sections stack whatever the layout asks for.
    static let minimumSideBySideWidth: CGFloat = 340

    /// The narrowest page that still puts two sections abreast. The view
    /// gives the two-per-row candidate this minimum inside `ViewThatFits`,
    /// so a narrower page falls back to one per row in every layout, with
    /// no measured width stored.
    static func twoAbreastMinimumWidth(spacing: CGFloat) -> CGFloat {
        minimumSideBySideWidth * 2 + spacing
    }

    /// Sections per row the layout asks for: one or two, never more.
    ///
    /// One section always has the page. Auto puts exactly two side by side,
    /// as 6.0 did with Claude and Codex (no row follows them, so different
    /// heights leave no hole), and stacks from three, where interleaving
    /// columns would make the page hard to read. One column always stacks;
    /// two columns always pairs.
    static func perRow(layout: HomeLayout, sections: Int) -> Int {
        guard sections > 1 else { return 1 }
        switch layout {
        case .auto: return sections == 2 ? 2 : 1
        case .oneColumn: return 1
        case .twoColumns: return 2
        }
    }

    /// The sections row by row, in order.
    static func rows(_ sections: [HomeSection], perRow: Int) -> [[HomeSection]] {
        let size = max(1, perRow)
        return stride(from: 0, to: sections.count, by: size).map {
            Array(sections[$0 ..< min($0 + size, sections.count)])
        }
    }
}
