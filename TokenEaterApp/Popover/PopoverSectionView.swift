import SwiftUI

/// Settings panel for the composable popover. Templates on top (built-ins +
/// user-saved), then the element list - the single source of edition: add,
/// reorder (drag), restyle, resize, hide, delete. The live preview renders
/// the real popover; tapping a cell there selects its row here.
struct PopoverSectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var usageStore: UsageStore

    @State private var selectedElementID: UUID?
    @State private var showSaveDialog = false
    @State private var templateName = ""

    /// Width threshold below which the two-column layout becomes unreadable.
    private let horizontalThreshold: CGFloat = 680

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
            Button(String(localized: "popover.editor.cancel"), role: .cancel) { templateName = "" }
        } message: {
            Text(String(localized: "popover.editor.saveTemplate.message"))
        }
    }

    // MARK: - Layouts

    private var horizontalLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                header
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 16) {
                            templatesSection
                            chromeSection
                            elementsSection
                            Spacer(minLength: 12)
                        }
                        .padding(.bottom, 8)
                    }
                    .onChange(of: selectedElementID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 24)
            .padding(.top, 24)

            VStack(alignment: .center, spacing: 14) {
                LivePopoverPreview(selectedElementID: $selectedElementID)
                resetButton
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.trailing, 24)
            .padding(.top, 24)
        }
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
                    chromeSection
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
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                settingsStore.popoverComposition = PopoverBuiltinTemplate.classic.composition
            }
            selectedElementID = nil
        } label: {
            Label(String(localized: "popover.settings.reset"), systemImage: "arrow.uturn.backward")
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.55))
    }

    // MARK: - Templates

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            editorSectionLabel("popover.editor.templates")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PopoverBuiltinTemplate.allCases) { template in
                        TemplateCard(
                            name: template.localizedName,
                            composition: template.composition
                        ) {
                            apply(template.composition)
                        }
                    }
                    ForEach(settingsStore.popoverUserTemplates) { template in
                        TemplateCard(
                            name: template.name,
                            composition: template.composition,
                            isUserTemplate: true
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
                    saveTemplateCard
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var saveTemplateCard: some View {
        Button {
            templateName = ""
            showSaveDialog = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text(String(localized: "popover.editor.saveTemplate.short"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .frame(width: 92, height: 96)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
            )
        }
        .buttonStyle(.plain)
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
        settingsStore.popoverUserTemplates.append(
            PopoverUserTemplate(name: trimmed, composition: settingsStore.popoverComposition)
        )
        templateName = ""
    }

    // MARK: - Chrome (fixed header toggles)

    private var chromeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            editorSectionLabel("popover.zone.general")

            chromeToggleRow(
                isOn: $settingsStore.popoverComposition.showPlanBadge,
                label: String(localized: "popover.option.showPlanBadge")
            )
            chromeToggleRow(
                isOn: $settingsStore.popoverComposition.showRefreshButton,
                label: String(localized: "popover.option.showRefreshButton")
            )
        }
    }

    private func chromeToggleRow(isOn: Binding<Bool>, label: String) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(DS.Palette.accentSettings)
                .labelsHidden()
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
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
                let metricKinds: [PopoverElementKind] = [.session, .weekly, .sonnet, .design, .fable, .extraCredits]
                ForEach(metricKinds) { kind in
                    addButton(for: kind)
                }
            }
            Section(String(localized: "popover.editor.family.pacing")) {
                addButton(for: .sessionPacing)
                addButton(for: .weeklyPacing)
            }
            Section(String(localized: "popover.editor.family.utilities")) {
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
        Button {
            addElement(kind)
        } label: {
            Label(
                available ? kind.localizedLabel
                    : "\(kind.localizedLabel) (\(String(localized: "popover.editor.unavailable")))",
                systemImage: kind.symbolName
            )
        }
        .disabled(!available)
    }

    /// Plan-level availability for the add menu (data-presence gating at
    /// render time is separate and stays live).
    private func accountHasKind(_ kind: PopoverElementKind) -> Bool {
        switch kind {
        case .design: return usageStore.hasDesign
        case .fable: return usageStore.hasFable
        case .extraCredits: return usageStore.hasExtraCredits
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            settingsStore.popoverComposition.elements.append(element)
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
    let onApply: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onApply) {
            VStack(spacing: 7) {
                TemplateSchematic(composition: composition, highlighted: hovering)
                HStack(spacing: 3) {
                    if isUserTemplate {
                        Image(systemName: "person.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Text(name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(hovering ? .white : .white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .padding(8)
            .frame(width: 92, height: 96)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(hovering ? Color.blue.opacity(0.12) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(hovering ? Color.blue.opacity(0.5) : Color.white.opacity(0.07), lineWidth: 1)
                    )
            )
            .scaleEffect(hovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                hovering = isHovering
            }
        }
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
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 3) {
                    ForEach(row) { element in
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
        case .paceText, .utilityRow, .actionButton: return 4
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
                    delegate: ElementDropDelegate(
                        item: element.id,
                        elements: elementsBinding,
                        draggingID: $draggingID
                    )
                )
            }
        }
    }

    // A stored-property binding into the composition struct - allowed (this
    // is not a computed-property binding, `popoverComposition` is @Published
    // storage on the store).
    private var elementsBinding: Binding<[PopoverElement]> {
        $settingsStore.popoverComposition.elements
    }

    private func isAvailable(_ kind: PopoverElementKind) -> Bool {
        switch kind {
        case .design: return usageStore.hasDesign
        case .fable: return usageStore.hasFable
        case .extraCredits: return usageStore.hasExtraCredits
        default: return true
        }
    }

    /// The last visible element can be neither hidden nor deleted, so the
    /// popover can never end up empty.
    private func canDisable(_ element: PopoverElement) -> Bool {
        element.isHidden || settingsStore.popoverComposition.visibleElements.count > 1
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
            HStack(spacing: 4) {
                Text(element.style.localizedLabel)
                    .font(.system(size: 10, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.white.opacity(0.06))
                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            )
        }
        .menuStyle(.borderlessButton)
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

/// Drop delegate for reordering elements. Swaps the dragged element into the
/// hovered slot on every drag tick for instant feedback.
private struct ElementDropDelegate: DropDelegate {
    let item: UUID
    @Binding var elements: [PopoverElement]
    @Binding var draggingID: UUID?

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingID, dragging != item else { return }
        guard let from = elements.firstIndex(where: { $0.id == dragging }),
              let to = elements.firstIndex(where: { $0.id == item })
        else { return }
        if from != to {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                elements.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
