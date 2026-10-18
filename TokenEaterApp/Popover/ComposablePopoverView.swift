import SwiftUI

// MARK: - Preview interaction environment
//
// The settings editor renders the same view with these values set so tapping
// a cell in the live preview selects it in the element list. The real popover
// never sets them, so the tap layer costs nothing there.

private struct PopoverElementTapKey: EnvironmentKey {
    static let defaultValue: ((UUID) -> Void)? = nil
}

private struct PopoverSelectedElementKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var popoverElementTap: ((UUID) -> Void)? {
        get { self[PopoverElementTapKey.self] }
        set { self[PopoverElementTapKey.self] = newValue }
    }

    var popoverSelectedElement: UUID? {
        get { self[PopoverSelectedElementKey.self] }
        set { self[PopoverSelectedElementKey.self] = newValue }
    }
}

// MARK: - Renderer

/// The composable popover renderer: fixed chrome (status + error banners),
/// then the element grid. Replaces the three variant layouts. The old fixed
/// header (plan badge + refresh button) is composition v2 elements now; only
/// its top breathing room remains as chrome.
struct ComposablePopoverView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var accountsStore: AccountsStore

    static let popoverWidth: CGFloat = 300

    /// True only when the switcher actually draws something: it renders
    /// nothing below two choices, and padding around nothing is a gap.
    private var showsSwitcher: Bool {
        settingsStore.popoverShowsProviderSwitch && settingsStore.modeChoices.count > 1
    }

    /// The Claude store the popover reads by default. Claude mode on an
    /// added account shows that account throughout: its banner, its cells,
    /// its plan badge and its refresh, as if it were the only account.
    private var scopeStore: UsageStore {
        let focused = settingsStore.focusedClaudeAccount
        guard settingsStore.activeProviderMode == .claude, !focused.isMain,
              settingsStore.runningClaudeAccountIDs.contains(focused),
              let store = accountsStore.usageStore(for: focused) else { return usageStore }
        return store
    }

    var body: some View {
        VStack(spacing: 0) {
            // The switcher sits in a band of its own, and the band was
            // lopsided: 12 above, 10 below, and then the grid's own 10 point
            // row spacing under that, so it read as belonging to the top of
            // the popover rather than to nothing in particular. Snug and even
            // now, and the 12 stays when the switcher is absent because that
            // is the spacing the popover has always opened with.
            Color.clear.frame(height: showsSwitcher ? 9 : 12)

            // Pinned, not composable, and that is the whole point: a control
            // that changes the scope cannot be something the scope can
            // delete. It was an element for one release and switching into a
            // mode whose layout lacked it left no way back out. Presence is a
            // single global preference now, off in Studio if you want it off,
            // and it still draws nothing below two choices.
            if settingsStore.popoverShowsProviderSwitch {
                ProviderModeSwitcher(size: .dots)
                    .padding(.bottom, showsSwitcher ? 3 : 0)
            }

            VendorStatusBanner()

            PopoverScopedBody()
                .environmentObject(scopeStore)
        }
        .frame(width: Self.popoverWidth)
        .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)))
    }
}

/// The part of the popover that reads the scope's Claude store, received
/// through the environment so it observes whichever store that is.
private struct PopoverScopedBody: View {
    @EnvironmentObject private var usageStore: UsageStore

    var body: some View {
        VStack(spacing: 0) {
            if usageStore.hasError {
                PopoverErrorBanner()
            }

            PopoverGrid()
        }
    }
}

/// The element grid. Rows come from `PopoverRowPacker` (pure, unit-tested),
/// applied by a custom `Layout` over ONE flat ForEach keyed by element id.
/// Flat identity is load-bearing: a reorder is a genuine SwiftUI "move", so
/// cells glide to their new frame under the container animation, with no
/// duplicated identities during transitions (the nested-ForEach +
/// matchedGeometryEffect approach mounted the same id twice mid-reorder,
/// which SwiftUI documents as undefined geometry).
///
/// Once two Claude accounts run, the All popover is split into sections, one
/// per run of an account's cells (and Codex's), each under a header naming
/// it (`PopoverSectionGrouping`), and every Claude cell reads its own
/// account's store. Cells then glide within their section only. Below two
/// accounts it is the one flat grid it always was.
private struct PopoverGrid: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var codexStore: CodexUsageStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var accountsStore: AccountsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.popoverElementTap) private var tapHandler
    @Environment(\.popoverSelectedElement) private var selectedID

    /// Repaints the grid when an added account's numbers change, since a
    /// cell's presence depends on them.
    @StateObject private var accountStores = UsageStoresObserver()

    @State private var appeared = false

    private static let horizontalPadding: CGFloat = 16
    private static let cellSpacing: CGFloat = 8
    private static let rowSpacing: CGFloat = 10
    private static let sectionSpacing: CGFloat = 12

    var body: some View {
        let visible = visibleElements
        Group {
            if visible.isEmpty {
                emptyState
            } else if showsSections {
                sectioned(visible)
            } else {
                grid(visible, rowOffset: 0)
                    // Edit-time reflow: flat stable ids make position changes
                    // animate as moves, cells glide to their new row instead
                    // of jump-cutting.
                    .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: settingsStore.popoverComposition.elements)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .onAppear {
            appeared = true
            accountStores.track(accountsStore.runningExtraStores)
        }
        .onChange(of: settingsStore.claudeAccounts) { _, _ in
            accountStores.track(accountsStore.runningExtraStores)
        }
    }

    /// Sections only in All, where several accounts share the popover. Claude
    /// mode shows one account, so it needs no header to say which.
    private var showsSections: Bool {
        settingsStore.activeProviderMode == .all && settingsStore.showsAccountMarkers
    }

    private func grid(_ visible: [PopoverElement], rowOffset: Int) -> some View {
        let rowIndexByID = rowIndexMap(visible)
        return PopoverGridLayout(cellSpacing: Self.cellSpacing, rowSpacing: Self.rowSpacing) {
            ForEach(visible) { element in
                cell(element, rowIndex: rowOffset + (rowIndexByID[element.id] ?? 0))
                    .layoutValue(key: PopoverGridWidthKey.self, value: element.effectiveWidth)
                    .layoutValue(key: PopoverGridChromeKey.self, value: element.kind.isChrome)
            }
        }
    }

    private func sectioned(_ visible: [PopoverElement]) -> some View {
        let sections = PopoverSectionGrouping.groups(
            visible,
            mode: settingsStore.activeProviderMode,
            focused: settingsStore.focusedClaudeAccount,
            running: settingsStore.runningClaudeAccountIDs,
            order: settingsStore.orderedSections
        )
        var offsets: [String: Int] = [:]
        var rows = 0
        for section in sections {
            offsets[section.id] = rows
            rows += PopoverRowPacker.pack(section.elements).count
        }
        return VStack(alignment: .leading, spacing: Self.sectionSpacing) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    if section.key.hasHeader {
                        PopoverSectionHeader(key: section.key)
                    }
                    grid(section.elements, rowOffset: offsets[section.id] ?? 0)
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: settingsStore.popoverComposition.elements)
    }

    /// The store a cell reads: the account its Claude kind resolves to, the
    /// scope's own store for everything else. Nil for a Claude cell whose
    /// account is not running, which is then not drawn at all.
    private func store(for element: PopoverElement) -> UsageStore? {
        guard element.kind.provider == .claude else { return usageStore }
        guard let account = settingsStore.effectiveAccount(for: element.account) else { return nil }
        return accountsStore.usageStore(for: account) ?? usageStore
    }

    private var visibleElements: [PopoverElement] {
        settingsStore.popoverComposition.visibleElements.filter { element in
            guard let store = store(for: element) else { return false }
            return PopoverMetricResolver.isVisible(element.kind, usage: store, codex: codexStore, settings: settingsStore)
        }
    }

    private func rowIndexMap(_ visible: [PopoverElement]) -> [UUID: Int] {
        var map: [UUID: Int] = [:]
        for (rowIndex, row) in PopoverRowPacker.pack(visible).enumerated() {
            for element in row { map[element.id] = rowIndex }
        }
        return map
    }

    @ViewBuilder
    private func cell(_ element: PopoverElement, rowIndex: Int) -> some View {
        let selected = selectedID == element.id
        let cellStore = store(for: element) ?? usageStore
        PopoverElementCellView(element: element)
            // Each Claude cell reads its own account; with a single account
            // this is the store the popover already holds.
            .environmentObject(cellStore)
            // A login that no longer answers keeps its last numbers, greyed:
            // its section header says how old they are.
            .lastNumbersDimmed(element.kind.provider == .claude && !element.kind.isChrome
                               && cellStore.lastNumbersDate != nil)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.7), lineWidth: 1.5)
                        .dsGlow(.blue, radius: 6, opacity: 0.5)
                        .padding(-3)
                }
            }
            .contentShape(Rectangle())
            .modifier(PreviewTapModifier(id: element.id, handler: tapHandler))
            // Entrance cascade: 25ms per row, fade + 6px rise. Subtle enough
            // for a surface opened dozens of times a day; skipped under
            // Reduce Motion.
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 6)
            .animation(
                reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85).delay(min(Double(rowIndex) * 0.025, 0.25)),
                value: appeared
            )
    }

    /// Shown when every element is hidden or unavailable right now (e.g. a
    /// pacing-only composition before the first refresh, or a metric the
    /// account no longer has). Static validation can't catch these, they
    /// depend on live data.
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.dashed")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))
            Text(String(localized: "popover.empty"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text(String(localized: "popover.empty.hint"))
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// MARK: - Section headers

/// The line above an account's section in the All popover: whose numbers
/// follow, and how fresh they are. Codex gets one too, so the sections read
/// as peers.
private struct PopoverSectionHeader: View {
    let key: PopoverSectionGrouping.Key

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var accountsStore: AccountsStore

    var body: some View {
        switch key {
        case .claude(let id):
            if let account = settingsStore.claudeAccount(id), let store = accountsStore.usageStore(for: id) {
                ClaudeAccountSectionHeader(account: account, store: store)
            }
        case .codex:
            CodexSectionHeader()
        case .neutral:
            EmptyView()
        }
    }
}

private struct ClaudeAccountSectionHeader: View {
    let account: ClaudeAccountSummary
    @ObservedObject var store: UsageStore

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var accountsStore: AccountsStore

    var body: some View {
        HStack(spacing: 5) {
            AccountDot(colorHex: account.colorHex, size: 7)
            Text(account.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(account.name)
            Spacer(minLength: 6)
            // Re-read every half minute so "4 min ago" keeps up while the
            // popover stays open.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if let caption = caption(now: context.date) {
                    Text(caption.text)
                        .font(.system(size: 9, weight: caption.isAlert ? .semibold : .medium))
                        .foregroundStyle(caption.isAlert ? DS.Palette.semanticWarning.opacity(0.9) : .white.opacity(0.4))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    /// Where the account stands, in a few words, read from the same
    /// `AccountHealth` Settings shows: another login, a refused or silent
    /// Keychain, no login, a missing folder, a limit or no network, or its
    /// numbers are old, or simply its plan when all is well. An expired
    /// token stays calm for the first hour, the usual wait for Claude Code's
    /// next run, as it does everywhere else.
    private func caption(now: Date) -> (text: String, isAlert: Bool)? {
        let folder = accountsStore.record(for: account.id)?.configDir
        let health = AccountHealth.resolve(
            errorState: store.errorState,
            diagnostic: store.tokenDiagnostic,
            loginExpiredSince: store.loginExpiredSince,
            identityState: store.identityState,
            isPaused: false,
            lastUpdate: store.lastUpdate,
            folderExists: folder.map { FileManager.default.fileExists(atPath: $0) } ?? true,
            command: "",
            names: [:]
        )
        switch health {
        case .identityConflict:
            return (String(localized: "popover.account.conflict"), true)
        case .accessDenied:
            return (String(localized: "popover.account.keychainRefused"), true)
        case .timedOut:
            return (String(localized: "popover.account.keychainTimedOut"), true)
        case .noLogin:
            return (String(localized: "popover.account.noLogin"), true)
        case .folderMissing:
            return (String(localized: "popover.account.folderMissing"), true)
        case .rateLimited:
            return (String(localized: "popover.account.rateLimited"), true)
        case .network:
            return (String(localized: "popover.account.offline"), true)
        case .loginExpired where store.loginExpiredSince != nil:
            // The cells below are its last numbers, greyed: say how old.
            let expired = String(localized: "popover.account.expired")
            guard let last = store.lastNumbersDate else { return (expired, true) }
            return (expired + " · " + last.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)), true)
        default:
            break
        }
        if let last = store.lastUpdate,
           now.timeIntervalSince(last) > 2 * Double(settingsStore.refreshInterval) {
            return (last.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)), false)
        }
        guard store.planType != .unknown else { return nil }
        return (store.planType.displayLabel, false)
    }
}

private struct CodexSectionHeader: View {
    @EnvironmentObject private var codexStore: CodexUsageStore

    var body: some View {
        HStack(spacing: 5) {
            ProviderGlyph(provider: .codex, size: 9)
                .foregroundStyle(.white.opacity(0.6))
            Text(ProviderMode.codex.localizedLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            Spacer(minLength: 6)
            if codexStore.planType != .unknown {
                Text(codexStore.planType.displayLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Grid layout

private struct PopoverGridWidthKey: LayoutValueKey {
    static let defaultValue: PopoverElementWidth = .full
}

/// Marks the header-chrome cells (plan badge + refresh). A chrome row is
/// packed on its own and laid out full-width so badge stays leading and
/// refresh stays trailing whether one or both are visible.
private struct PopoverGridChromeKey: LayoutValueKey {
    static let defaultValue: Bool = false
}

/// Places one flat run of cells into centered rows. Row formation delegates
/// to `PopoverRowPacker.packIndices` so the renderer, the editor schematics,
/// and the tests all share the same rule.
private struct PopoverGridLayout: Layout {
    let cellSpacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? ComposablePopoverView.popoverWidth
        let rows = rowGroups(subviews)
        var height: CGFloat = 0
        for row in rows {
            height += rowHeight(row, subviews: subviews, totalWidth: width)
        }
        if rows.count > 1 {
            height += rowSpacing * CGFloat(rows.count - 1)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rowGroups(subviews) {
            let cellW = cellWidth(row, subviews: subviews, totalWidth: bounds.width)
            let heights = row.map {
                subviews[$0].sizeThatFits(ProposedViewSize(width: cellW, height: nil)).height
            }
            let rowH = heights.max() ?? 0
            let contentW = CGFloat(row.count) * cellW + CGFloat(row.count - 1) * cellSpacing
            var x = bounds.minX + (bounds.width - contentW) / 2
            for (i, index) in row.enumerated() {
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (rowH - heights[i]) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: cellW, height: heights[i])
                )
                x += cellW + cellSpacing
            }
            y += rowH + rowSpacing
        }
    }

    private func rowGroups(_ subviews: Subviews) -> [[Int]] {
        PopoverRowPacker.packIndices(
            subviews.map { $0[PopoverGridWidthKey.self] },
            groups: subviews.map { $0[PopoverGridChromeKey.self] ? 1 : 0 }
        )
    }

    private func isChromeRow(_ row: [Int], subviews: Subviews) -> Bool {
        row.first.map { subviews[$0][PopoverGridChromeKey.self] } ?? false
    }

    private func rowWidth(_ row: [Int], subviews: Subviews) -> PopoverElementWidth {
        row.first.map { subviews[$0][PopoverGridWidthKey.self] } ?? .full
    }

    private func rowHeight(_ row: [Int], subviews: Subviews, totalWidth: CGFloat) -> CGFloat {
        let cellW = cellWidth(row, subviews: subviews, totalWidth: totalWidth)
        return row.map {
            subviews[$0].sizeThatFits(ProposedViewSize(width: cellW, height: nil)).height
        }.max() ?? 0
    }

    /// Cell width for a row. Chrome rows (badge / refresh) divide the full
    /// width by their element count so the row spans edge to edge whether one
    /// or both are visible; metric rows resolve against the width fraction
    /// (300 - 2x16 = 268 usable: full 268, half 130, third 84).
    private func cellWidth(_ row: [Int], subviews: Subviews, totalWidth: CGFloat) -> CGFloat {
        if isChromeRow(row, subviews: subviews) {
            let count = CGFloat(max(row.count, 1))
            let spacing = cellSpacing * (count - 1)
            return ((totalWidth - spacing) / count).rounded(.down)
        }
        let width = rowWidth(row, subviews: subviews)
        let spacing = cellSpacing * CGFloat(width.rowCapacity - 1)
        return ((totalWidth - spacing) / CGFloat(width.rowCapacity)).rounded(.down)
    }
}

/// Adds the tap layer only when the editor preview installed a handler, so
/// the real popover keeps its buttons and toggles fully interactive.
private struct PreviewTapModifier: ViewModifier {
    let id: UUID
    let handler: ((UUID) -> Void)?

    func body(content: Content) -> some View {
        if let handler {
            // Transparent layer above the cell so its own buttons / toggles
            // never swallow the selection tap in the editor preview.
            content.overlay(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { handler(id) }
            )
        } else {
            content
        }
    }
}
