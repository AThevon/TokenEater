import SwiftUI

/// Studio editor for the composable popover. Three columns: a template rail
/// on the left (built-ins + user-saved), the element list in the middle (the
/// single source of edition: add, reorder, restyle, resize, hide, delete),
/// and the live popover pinned on the right so every edit is visible without
/// scrolling. Tapping a cell in the preview selects its row in the list.
struct PopoverSectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var usageStore: UsageStore

    @State private var selectedElementID: UUID?
    @State private var showSaveDialog = false
    @State private var templateName = ""

    /// Width below which the three-column layout stops fitting and we fall
    /// back to a single scrolling column.
    private let horizontalThreshold: CGFloat = 780

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= horizontalThreshold {
                horizontalLayout
            } else {
                verticalLayout
            }
        }
        .alert(String(localized: "popover.editor.saveTemplate"), isPresented: $showSaveDialog) {
            TextField(String(localized: "popover.editor.saveTemplate.placeholder"), text: $templateName)
            Button(String(localized: "popover.editor.save")) { saveCurrentAsTemplate() }
                .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(String(localized: "popover.editor.cancel"), role: .cancel) { templateName = "" }
        } message: {
            Text(String(localized: "popover.editor.saveTemplate.message"))
        }
    }

    // MARK: - Layouts

    private var horizontalLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left: template rail (scrolls independently).
            templatesRail

            // Middle: the element list (scrolls). Auto-scrolls to the row
            // that matches a preview tap.
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    elementsSection
                        .padding(.bottom, 8)
                }
                .onChange(of: selectedElementID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Right: the real popover. Scrolls on its own so a tall
            // composition's preview can be seen in full instead of being
            // clipped at the bottom.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .center, spacing: 14) {
                    LivePopoverPreview(selectedElementID: $selectedElementID)
                    resetButton
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
            }
            .frame(width: 312)
        }
        .padding(20)
    }

    private var verticalLayout: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    VStack(alignment: .center, spacing: 14) {
                        LivePopoverPreview(selectedElementID: $selectedElementID)
                        resetButton
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    templatesSection
                    elementsSection
                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .onChange(of: selectedElementID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var header: some View {
        sectionTitle(
            String(localized: "popover.settings.title"),
            subtitle: String(localized: "popover.settings.subtitle")
        )
    }

    private var resetButton: some View {
        StudioResetButton {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                settingsStore.popoverComposition = PopoverBuiltinTemplate.classic.composition
            }
            selectedElementID = nil
        }
    }

    // MARK: - Templates

    // MARK: - Active / modified state

    private var current: PopoverComposition { settingsStore.popoverComposition }

    /// The saved template that matches the current composition, if any.
    private var activeUserTemplateID: UUID? {
        settingsStore.popoverUserTemplates.first { $0.composition.isEquivalent(to: current) }?.id
    }

    /// The built-in that matches (only when no saved template already did).
    private var activeBuiltin: PopoverBuiltinTemplate? {
        guard activeUserTemplateID == nil else { return nil }
        return PopoverBuiltinTemplate.allCases.first { $0.composition.isEquivalent(to: current) }
    }

    /// The current composition diverges from every template -> a custom, not
    /// yet saved, state.
    private var isModified: Bool {
        activeUserTemplateID == nil && activeBuiltin == nil
    }

    /// Vertical template rail for the three-column Studio layout: the custom
    /// state (when modified) on top, then saved templates (newest first),
    /// then the built-ins.
    private var templatesRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            editorSectionLabel("popover.editor.templates")

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    templateCards
                }
                .padding(.vertical, 2)
            }
        }
        .frame(width: 108)
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            editorSectionLabel("popover.editor.templates")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    templateCards
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private var templateCards: some View {
        if isModified {
            CustomStateCard {
                templateName = ""
                showSaveDialog = true
            }
        }
        // Saved templates first, newest on top (saves insert at index 0).
        ForEach(settingsStore.popoverUserTemplates) { template in
            TemplateCard(
                name: template.name,
                composition: template.composition,
                isUserTemplate: true,
                isActive: template.id == activeUserTemplateID
            ) {
                apply(template.composition)
            }
            .contextMenu {
                Button(role: .destructive) {
                    settingsStore.popoverUserTemplates.removeAll { $0.id == template.id }
                } label: {
                    Label(String(localized: "popover.editor.deleteTemplate"), systemImage: "trash")
                }
            }
        }
        ForEach(PopoverBuiltinTemplate.allCases) { template in
            TemplateCard(
                name: template.localizedName,
                composition: template.composition,
                isActive: template == activeBuiltin
            ) {
                apply(template.composition)
            }
        }
    }

    private func apply(_ composition: PopoverComposition) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            settingsStore.popoverComposition = composition
        }
        selectedElementID = nil
    }

    private func saveCurrentAsTemplate() {
        let trimmed = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Suffix duplicate names so two saves under "Work" stay tellable
        // apart in the gallery and the context menu.
        var name = trimmed
        var counter = 2
        while settingsStore.popoverUserTemplates.contains(where: { $0.name == name }) {
            name = "\(trimmed) \(counter)"
            counter += 1
        }
        // Newest on top -> the just-saved template lands above the built-ins.
        settingsStore.popoverUserTemplates.insert(
            PopoverUserTemplate(name: name, composition: settingsStore.popoverComposition),
            at: 0
        )
        templateName = ""
    }

    // MARK: - Elements

    private var elementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                editorSectionLabel("popover.editor.elements")
                Spacer()
                addElementMenu
            }

            ElementListEditor(selectedElementID: $selectedElementID)
        }
    }

    private var addElementMenu: some View {
        Menu {
            Section(String(localized: "popover.editor.family.metrics")) {
                let metricKinds: [PopoverElementKind] = [.session, .weekly, .sonnet, .fable, .extraCredits]
                ForEach(metricKinds) { kind in
                    addButton(for: kind)
                }
            }
            Section(String(localized: "popover.editor.family.pacing")) {
                addButton(for: .sessionPacing)
                addButton(for: .weeklyPacing)
                addButton(for: .fablePacing)
            }
            Section(String(localized: "popover.editor.family.utilities")) {
                addButton(for: .planBadge)
                addButton(for: .refreshButton)
                addButton(for: .watchers)
                addButton(for: .timestamp)
                addButton(for: .openButton)
                addButton(for: .quitButton)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text(String(localized: "popover.editor.addElement"))
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.18))
                    .overlay(Capsule().stroke(Color.blue.opacity(0.45), lineWidth: 1))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private func addButton(for kind: PopoverElementKind) -> some View {
        let available = accountHasKind(kind)
        // Not disabled when unavailable: a user can pre-place a metric the
        // account does not have yet (Extra Credits, Fable) so their
        // layout is future-proof - the render-time gate keeps it hidden until
        // the account actually gains the data, at which point it appears on
        // its own. The label just flags that it is not active yet.
        Button {
            addElement(kind)
        } label: {
            Label(
                available ? kind.localizedLabel
                    : "\(kind.localizedLabel) (\(String(localized: "popover.editor.unavailable")))",
                systemImage: kind.symbolName
            )
        }
    }

    /// Whether the metric is currently active on the account. Only labels the
    /// add-menu entry; it does not block adding (see `addButton`). Render-time
    /// presence gating stays live and separate.
    private func accountHasKind(_ kind: PopoverElementKind) -> Bool {
        switch kind {
        case .fable, .fablePacing: return usageStore.hasFable
        case .extraCredits: return usageStore.hasExtraCredits
        case .planBadge: return usageStore.planType != .unknown
        default: return true
        }
    }

    private func addElement(_ kind: PopoverElementKind) {
        let style = kind.allowedStyles.first ?? .utilityRow
        let element = PopoverElement(
            kind: kind,
            style: style,
            width: style.defaultWidth,
            options: PopoverElementOptions(showReset: kind == .session || kind == .weekly)
        )
        // Insert at the top: the new element lands where the user is looking
        // (right under the add button), not below the fold of a long list.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            settingsStore.popoverComposition.elements.insert(element, at: 0)
        }
        selectedElementID = element.id
    }

    private func editorSectionLabel(_ key: String.LocalizationValue) -> some View {
        Text(String(localized: key))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

// MARK: - Template card

private struct TemplateCard: View {
    let name: String
    let composition: PopoverComposition
    var isUserTemplate: Bool = false
    var isActive: Bool = false
    let onApply: () -> Void

    @State private var hovering = false

    private var fill: Color {
        if isActive { return DS.Palette.accentStudio.opacity(0.16) }
        if hovering { return Color.blue.opacity(0.12) }
        return Color.white.opacity(0.03)
    }

    private var stroke: Color {
        if isActive { return DS.Palette.accentStudio.opacity(0.6) }
        if hovering { return Color.blue.opacity(0.5) }
        return Color.white.opacity(0.07)
    }

    var body: some View {
        Button(action: onApply) {
            VStack(spacing: 7) {
                TemplateSchematic(composition: composition, highlighted: hovering || isActive)
                HStack(spacing: 3) {
                    if isUserTemplate {
                        Image(systemName: "person.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Text(name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isActive || hovering ? .white : .white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .padding(8)
            .frame(width: 92, height: 96)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(stroke, lineWidth: 1)
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.accentStudio)
                        .padding(5)
                }
            }
            .scaleEffect(hovering && !isActive ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                hovering = isHovering
            }
        }
    }
}

/// Shown at the top of the template list when the current composition no
/// longer matches any template. Doubles as the save affordance -> tapping it
/// saves the current composition as a new user template at the top.
private struct CustomStateCard: View {
    let onSave: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSave) {
            VStack(spacing: 6) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Palette.accentStudio)
                Text(String(localized: "editor.custom.modified"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.Palette.accentStudio)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(String(localized: "editor.custom.save"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(8)
            .frame(width: 92, height: 96)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DS.Palette.accentStudio.opacity(hovering ? 0.16 : 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(DS.Palette.accentStudio.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
            )
            .scaleEffect(hovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { hovering = h } }
    }
}

/// Miniature wireframe of a composition: one bar per grid row, split by the
/// row's element widths. Heights hint at the style (tall = ring / arc,
/// medium = card, thin = row).
private struct TemplateSchematic: View {
    let composition: PopoverComposition
    let highlighted: Bool

    private static let maxRows = 6

    var body: some View {
        let rows = PopoverRowPacker.pack(composition.visibleElements).prefix(Self.maxRows)
        VStack(spacing: 3) {
            // Offset identity on purpose: built-in compositions mint fresh
            // element UUIDs on every access, id-keyed cells would defeat
            // SwiftUI diffing and recreate every rectangle each render.
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 3) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, element in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(highlighted ? Color.blue.opacity(0.55) : Color.white.opacity(0.22))
                            .frame(maxWidth: .infinity)
                            .frame(height: schematicHeight(for: element.style))
                    }
                }
            }
        }
        .frame(width: 64)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func schematicHeight(for style: PopoverElementStyle) -> CGFloat {
        switch style {
        case .gaugeRing, .arc: return 13
        case .chip, .bigText, .paceTile: return 8
        case .paceBar: return 6
        case .paceText, .utilityRow, .actionButton, .badge: return 4
        }
    }
}

// MARK: - Live preview

private struct LivePopoverPreview: View {
    @Binding var selectedElementID: UUID?

    var body: some View {
        VStack(spacing: 8) {
            Text(String(localized: "popover.settings.preview"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(1)
                .frame(maxWidth: .infinity)

            // Render the exact view used by the real popover, with the
            // selection tap layer enabled.
            MenuBarPopoverView()
                .environment(\.popoverSelectedElement, selectedElementID)
                .environment(\.popoverElementTap) { id in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedElementID = (selectedElementID == id) ? nil : id
                    }
                }
                .fixedSize()
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)

            Text(String(localized: "popover.editor.preview.hint"))
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Element list

private struct ElementListEditor: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var usageStore: UsageStore

    @Binding var selectedElementID: UUID?
    @State private var draggingID: UUID?

    var body: some View {
        VStack(spacing: 8) {
            elementRows
        }
        // Catch-all so a drop released in the 8pt gaps between rows (outside
        // any row's drop target) still ends the drag session cleanly instead
        // of leaving the dragged row stuck in its lifted style. A drag
        // cancelled outside the list entirely (Escape, drop on the preview)
        // still leaks draggingID until the next drag; that limitation is
        // inherited from the pre-5.9 editor, SwiftUI offers no drag-ended
        // callback for onDrag.
        .onDrop(of: [.text], delegate: ReorderGapDropDelegate(draggingID: $draggingID))
    }

    private var elementRows: some View {
        ForEach(settingsStore.popoverComposition.elements) { element in
            ElementRow(
                element: element,
                isSelected: selectedElementID == element.id,
                isDragging: draggingID == element.id,
                isAvailable: isAvailable(element.kind),
                canDisable: canDisable(element),
                onSelect: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedElementID = (selectedElementID == element.id) ? nil : element.id
                    }
                },
                onToggleHidden: { toggleHidden(element) },
                onDelete: { delete(element) },
                onStyle: { setStyle($0, for: element) },
                onWidth: { setWidth($0, for: element) },
                onContent: { setContent($0, for: element) },
                onToggleReset: { toggleReset(element) }
            )
            .id(element.id)
            .onDrag {
                draggingID = element.id
                return NSItemProvider(object: element.id.uuidString as NSString)
            }
            .onDrop(
                of: [.text],
                delegate: ReorderDropDelegate(
                    item: element.id,
                    items: elementsBinding,
                    draggingID: $draggingID
                )
            )
        }
    }

    // A stored-property binding into the composition struct - allowed (this
    // is not a computed-property binding, `popoverComposition` is @Published
    // storage on the store).
    private var elementsBinding: Binding<[PopoverElement]> {
        $settingsStore.popoverComposition.elements
    }

    // Plan-level availability, mirroring `accountHasKind` in the add menu
    // (data-level gates like pacing-before-first-refresh are the renderer's
    // empty-state fallback, not the editor's job). `.planBadge` must be here:
    // with no known plan the renderer filters it out, so the editor must not
    // count it toward the "keep one element visible" guard, and must keep it
    // freely removable.
    private func isAvailable(_ kind: PopoverElementKind) -> Bool {
        switch kind {
        case .fable, .fablePacing: return usageStore.hasFable
        case .extraCredits: return usageStore.hasExtraCredits
        case .planBadge: return usageStore.planType != .unknown
        default: return true
        }
    }

    /// Whether hiding or deleting this element is allowed. The guard counts
    /// only elements that are visible AND available on the account: removing
    /// an unavailable element (e.g. a Fable arc after a plan downgrade)
    /// never empties the rendered popover, so it must always be removable,
    /// and it must never count as the "one element" keeping the popover
    /// non-empty. The renderer still has an empty-state fallback for the
    /// data-dependent cases validation can't see (pacing before the first
    /// refresh).
    private func canDisable(_ element: PopoverElement) -> Bool {
        if element.isHidden { return true }
        guard isAvailable(element.kind) else { return true }
        let availableVisible = settingsStore.popoverComposition.visibleElements
            .filter { isAvailable($0.kind) }
        return availableVisible.count > 1
    }

    private func mutate(_ id: UUID, _ transform: (inout PopoverElement) -> Void) {
        guard let idx = settingsStore.popoverComposition.elements.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            transform(&settingsStore.popoverComposition.elements[idx])
        }
    }

    private func toggleHidden(_ element: PopoverElement) {
        guard canDisable(element) else { return }
        mutate(element.id) { $0.isHidden.toggle() }
    }

    private func delete(_ element: PopoverElement) {
        guard canDisable(element) else { return }
        if selectedElementID == element.id { selectedElementID = nil }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            settingsStore.popoverComposition.elements.removeAll { $0.id == element.id }
        }
    }

    private func setStyle(_ style: PopoverElementStyle, for element: PopoverElement) {
        mutate(element.id) {
            $0.style = style
            if !style.allowedWidths.contains($0.width) {
                $0.width = style.defaultWidth
            }
        }
    }

    private func setWidth(_ width: PopoverElementWidth, for element: PopoverElement) {
        mutate(element.id) { $0.width = width }
    }

    private func setContent(_ content: PopoverMetricContent, for element: PopoverElement) {
        mutate(element.id) { $0.options.content = content }
    }

    private func toggleReset(_ element: PopoverElement) {
        mutate(element.id) { $0.options.showReset.toggle() }
    }
}

// MARK: - Element row

private struct ElementRow: View {
    let element: PopoverElement
    let isSelected: Bool
    let isDragging: Bool
    let isAvailable: Bool
    let canDisable: Bool
    let onSelect: () -> Void
    let onToggleHidden: () -> Void
    let onDelete: () -> Void
    let onStyle: (PopoverElementStyle) -> Void
    let onWidth: (PopoverElementWidth) -> Void
    let onContent: (PopoverMetricContent) -> Void
    let onToggleReset: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(width: 14)

                Image(systemName: element.kind.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(element.isHidden ? .white.opacity(0.3) : .white.opacity(0.7))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(element.kind.localizedLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(element.isHidden ? .white.opacity(0.35) : .white.opacity(0.9))
                        .lineLimit(1)
                    if !isAvailable {
                        Text(String(localized: "popover.editor.unavailable"))
                            .font(.system(size: 9))
                            .foregroundStyle(.orange.opacity(0.7))
                    }
                }

                Spacer(minLength: 4)

                Button(action: onToggleHidden) {
                    Image(systemName: element.isHidden ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(element.isHidden ? .white.opacity(0.35) : .blue)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canDisable)
                .opacity(canDisable ? 1 : 0.35)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canDisable)
                .opacity(canDisable ? 1 : 0.35)
            }

            // Style / width / options controls. Only rendered when the kind
            // offers a real choice, to keep utility rows lightweight.
            if element.kind.allowedStyles.count > 1 || element.style.allowedWidths.count > 1 {
                HStack(spacing: 8) {
                    if element.kind.allowedStyles.count > 1 {
                        styleMenu
                    }
                    if element.style.allowedWidths.count > 1 {
                        widthPicker
                    }
                    if element.style.supportsContentChoice {
                        contentPicker
                    }
                    if element.style.supportsResetToggle {
                        resetToggle
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(rowFill)
                .shadow(color: isDragging ? .black.opacity(0.4) : .clear, radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(rowStroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .opacity(isDragging ? 0.9 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var rowFill: Color {
        if isDragging { return Color.blue.opacity(0.12) }
        if isSelected { return Color.blue.opacity(0.08) }
        return element.isHidden ? Color.white.opacity(0.015) : Color.white.opacity(0.04)
    }

    private var rowStroke: Color {
        if isDragging || isSelected { return Color.blue.opacity(0.6) }
        return element.isHidden ? Color.white.opacity(0.04) : Color.white.opacity(0.08)
    }

    private var styleMenu: some View {
        Menu {
            ForEach(element.kind.allowedStyles) { style in
                Button {
                    onStyle(style)
                } label: {
                    if style == element.style {
                        Label(style.localizedLabel, systemImage: "checkmark")
                    } else {
                        Text(style.localizedLabel)
                    }
                }
            }
        } label: {
            EditorPickerLabel(caption: "editor.pick.style", value: element.style.localizedLabel)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.secondary)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var widthPicker: some View {
        HStack(spacing: 2) {
            ForEach(PopoverElementWidth.allCases) { width in
                let allowed = element.style.allowedWidths.contains(width)
                let active = element.effectiveWidth == width
                Button {
                    onWidth(width)
                } label: {
                    Image(systemName: width.symbolName)
                        .font(.system(size: 10))
                        .foregroundStyle(active ? .white : .white.opacity(allowed ? 0.45 : 0.15))
                        .frame(width: 24, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(active ? Color.blue.opacity(0.35) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!allowed)
                .help(width.localizedLabel)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var contentPicker: some View {
        HStack(spacing: 2) {
            contentButton(.percent, symbol: "percent")
            contentButton(.resetCountdown, symbol: "clock.arrow.circlepath")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func contentButton(_ content: PopoverMetricContent, symbol: String) -> some View {
        let active = element.options.content == content
        return Button {
            onContent(content)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(active ? .white : .white.opacity(0.45))
                .frame(width: 24, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(active ? Color.blue.opacity(0.35) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(content == .percent
              ? String(localized: "popover.editor.content.percent")
              : String(localized: "popover.editor.content.reset"))
    }

    private var resetToggle: some View {
        Button(action: onToggleReset) {
            Image(systemName: "timer")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(element.options.showReset ? .white : .white.opacity(0.4))
                .frame(width: 24, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(element.options.showReset ? Color.blue.opacity(0.35) : Color.white.opacity(0.05))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "popover.editor.showReset"))
    }
}
// Reordering drop delegates moved to `ReorderDropDelegate.swift` as generics
// (`ReorderDropDelegate` / `ReorderGapDropDelegate`) so the menu bar editor can
// share them.
