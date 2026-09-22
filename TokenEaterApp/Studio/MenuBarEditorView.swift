import SwiftUI

/// Composable menu bar editor: three columns in the Studio -> a template
/// rail on the left, the reorderable segment list in the middle (the single
/// source of edition), and a live NSImage preview pinned on the right whose
/// segments are clickable (click a segment to select its row). Writes go to
/// `settingsStore.menuBarComposition`, which both this view and the status bar
/// observe. Unlike the popover, an empty menu bar is legitimate (the renderer
/// draws the app icon), so there is no "can't remove the last one" guard.
///
/// `previewHeader` sits above the preview (the show-in-menu-bar toggle) and
/// `previewFooter` sits under it (colour controls + reset); the menu bar
/// preview is short, so its column has the spare height for them. Both are
/// injected by `DisplaySectionView` so the surrounding chrome lives with the
/// code that owns those settings.
struct MenuBarEditorView<PreviewHeader: View, PreviewFooter: View>: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var codexStore: CodexUsageStore

    @State private var selectedSegmentID: UUID?
    @State private var showSaveDialog = false
    @State private var templateName = ""

    @ViewBuilder var previewHeader: () -> PreviewHeader
    @ViewBuilder var previewFooter: () -> PreviewFooter

    /// Width below which the three-column layout stops fitting.
    private let horizontalThreshold: CGFloat = 780

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= horizontalThreshold {
                horizontalLayout
            } else {
                verticalLayout
            }
        }
        .alert(String(localized: "menuBar.editor.saveTemplate"), isPresented: $showSaveDialog) {
            TextField(String(localized: "menuBar.editor.saveTemplate.placeholder"), text: $templateName)
            Button(String(localized: "menuBar.editor.save")) { saveCurrentAsTemplate() }
                .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(String(localized: "menuBar.editor.cancel"), role: .cancel) { templateName = "" }
        } message: {
            Text(String(localized: "menuBar.editor.saveTemplate.message"))
        }
    }

    // MARK: - Layouts

    private var horizontalLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left: template rail (scrolls independently).
            templatesRail

            // Middle: the segment list, the only column that scrolls. The
            // header sits outside the ScrollView because it carries this
            // column's primary action ("add segment"), which used to scroll
            // away with the list.
            VStack(alignment: .leading, spacing: 10) {
                segmentsHeader
                ScrollView(.vertical, showsIndicators: true) {
                    segmentsList
                        .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Right: the toggle, the live menu bar item, then the colour
            // controls + reset (the short preview leaves room below it). The
            // preview stays at the top so an edit is always visible.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Centred over the preview it controls. Left-aligned it
                    // read as a stray row above an unrelated image.
                    previewHeader()
                        .frame(maxWidth: .infinity, alignment: .center)
                    MenuBarLivePreview(selectedSegmentID: $selectedSegmentID)
                    previewFooter()
                }
            }
            .frame(width: 300)
        }
        .padding(20)
    }

    private var verticalLayout: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                previewHeader()
                    .frame(maxWidth: .infinity, alignment: .center)
                MenuBarLivePreview(selectedSegmentID: $selectedSegmentID)
                previewFooter()
                templatesSection
                segmentsSection
            }
            .padding(20)
        }
    }

    // MARK: - Active / modified state

    private var current: MenuBarComposition { settingsStore.menuBarComposition }

    private var activeUserTemplateID: UUID? {
        settingsStore.menuBarUserTemplates.first { $0.composition.isEquivalent(to: current) }?.id
    }

    private var activeBuiltin: MenuBarBuiltinTemplate? {
        guard activeUserTemplateID == nil else { return nil }
        return MenuBarBuiltinTemplate.allCases.first { $0.composition.isEquivalent(to: current) }
    }

    private var isModified: Bool {
        activeUserTemplateID == nil && activeBuiltin == nil
    }

    // MARK: - Templates

    /// Vertical template rail: custom state (when modified) on top, then saved
    /// templates (newest first), then built-ins.
    private var templatesRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            editorLabel("menuBar.editor.templates")
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    templateCards
                }
                .padding(.vertical, 2)
            }
        }
        .frame(width: 104)
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            editorLabel("menuBar.editor.templates")
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
            MenuBarCustomStateCard {
                templateName = ""
                showSaveDialog = true
            }
        }
        ForEach(settingsStore.menuBarUserTemplates) { template in
            MenuBarTemplateCard(
                name: template.name,
                composition: template.composition,
                isUserTemplate: true,
                isActive: template.id == activeUserTemplateID
            ) {
                apply(template.composition)
            }
            .contextMenu {
                Button(role: .destructive) {
                    settingsStore.menuBarUserTemplates.removeAll { $0.id == template.id }
                } label: {
                    Label(String(localized: "menuBar.editor.deleteTemplate"), systemImage: "trash")
                }
            }
        }
        ForEach(MenuBarBuiltinTemplate.ordered(
            for: settingsStore.activeProviderMode,
            providerCount: settingsStore.activeProviders.count
        )) { template in
            MenuBarTemplateCard(
                name: template.localizedName,
                composition: template.composition,
                isActive: template == activeBuiltin
            ) {
                apply(template.composition)
            }
        }
    }

    private func apply(_ composition: MenuBarComposition) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            settingsStore.menuBarComposition = composition
        }
        selectedSegmentID = nil
    }

    private func saveCurrentAsTemplate() {
        let trimmed = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var name = trimmed
        var counter = 2
        while settingsStore.menuBarUserTemplates.contains(where: { $0.name == name }) {
            name = "\(trimmed) \(counter)"
            counter += 1
        }
        // Newest on top -> the just-saved template lands above the built-ins.
        settingsStore.menuBarUserTemplates.insert(
            MenuBarUserTemplate(name: name, composition: settingsStore.menuBarComposition),
            at: 0
        )
        templateName = ""
    }

    // MARK: - Segments

    private var segmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            segmentsHeader
            segmentsList
        }
    }

    private var segmentsHeader: some View {
        HStack {
            editorLabel("menuBar.editor.segments")
            Spacer()
            addSegmentMenu
        }
    }

    private var segmentsList: some View {
        MenuBarSegmentListEditor(selectedSegmentID: $selectedSegmentID)
    }

    private var addSegmentMenu: some View {
        AddElementMenuButton(title: String(localized: "menuBar.editor.addSegment")) {
            // Same rule as the popover editor: provider first, family second,
            // derived from the kinds rather than listed by hand.
            ForEach(scopedProviders) { provider in
                let metrics = MenuBarSegmentKind.allCases.filter {
                    $0.provider == provider && !$0.isPacing
                }
                let pacing = MenuBarSegmentKind.allCases.filter {
                    $0.provider == provider && $0.isPacing
                }
                if !metrics.isEmpty {
                    Section(pickerSectionTitle(provider, "menuBar.editor.family.metrics")) {
                        ForEach(metrics) { addButton(for: $0) }
                    }
                }
                if !pacing.isEmpty {
                    Section(pickerSectionTitle(provider, "menuBar.editor.family.pacing")) {
                        ForEach(pacing) { addButton(for: $0) }
                    }
                }
            }
            Section(String(localized: "menuBar.editor.family.status")) {
                addButton(for: .sessionReset)
                addButton(for: .serviceStatus)
            }
        }
    }

    /// The providers this scope can actually render, matching the renderer's
    /// own provider gate. Offering the other one's segments produced rows the
    /// menu bar silently dropped.
    private var scopedProviders: [MetricProvider] {
        settingsStore.activeProviders.filter { settingsStore.activeProviderMode.shows($0) }
    }

    private func pickerSectionTitle(_ provider: MetricProvider, _ familyKey: String.LocalizationValue) -> String {
        let family = String(localized: familyKey)
        guard scopedProviders.count > 1 else { return family }
        return "\(provider.displayName) · \(family)"
    }

    @ViewBuilder
    private func addButton(for kind: MenuBarSegmentKind) -> some View {
        // Not disabled when unavailable: let the user pre-place a metric the
        // account does not have yet so the layout is future-proof; the
        // renderer keeps it hidden until the data actually shows up. The label
        // says why it would not draw, in the words of the actual reason.
        let blocked = unavailability(kind)
        Button {
            addSegment(kind)
        } label: {
            Label(
                blocked.map { "\(kind.localizedLabel) (\($0.label))" } ?? kind.localizedLabel,
                systemImage: kind.symbolName
            )
        }
    }

    /// Why this kind would draw nothing, or nil when it draws. Asked of the
    /// same gate the renderer uses, so the menu and the menu bar cannot
    /// disagree about what an account has.
    private func unavailability(_ kind: MenuBarSegmentKind) -> EditorUnavailability? {
        EditorUnavailability.reason(
            for: kind, settings: settingsStore, usage: usageStore, codex: codexStore
        )
    }

    private func addSegment(_ kind: MenuBarSegmentKind) {
        let style = kind.allowedStyles.first ?? .text
        let segment = MenuBarSegment(kind: kind, style: style)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            settingsStore.menuBarComposition.segments.insert(segment, at: 0)
        }
        selectedSegmentID = segment.id
    }

    private func editorLabel(_ key: String.LocalizationValue) -> some View {
        Text(String(localized: key))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

// MARK: - Template card

private struct MenuBarTemplateCard: View {
    let name: String
    let composition: MenuBarComposition
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
                MenuBarTemplateSchematic(composition: composition, highlighted: hovering || isActive)
                    .frame(height: 20)
                HStack(spacing: 3) {
                    if isUserTemplate {
                        Image(systemName: "person.fill").font(.system(size: 7)).foregroundStyle(.white.opacity(0.4))
                    }
                    Text(name).font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isActive || hovering ? .white : .white.opacity(0.65)).lineLimit(1)
                }
            }
            .padding(8)
            .frame(width: 88, height: 62)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(stroke, lineWidth: 1))
            )
            .overlay(alignment: .topTrailing) {
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Palette.accentStudio)
                        .padding(4)
                }
            }
            .scaleEffect(hovering && !isActive ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { hovering = h } }
    }
}

/// Menu bar equivalent of the popover's custom-state card. Shown at the top of
/// the template list when the composition diverges from every template; saves
/// the current one as a new user template on top.
private struct MenuBarCustomStateCard: View {
    let onSave: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSave) {
            VStack(spacing: 4) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.accentStudio)
                Text(String(localized: "editor.custom.modified"))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DS.Palette.accentStudio)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(String(localized: "editor.custom.save"))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(6)
            .frame(width: 88, height: 62)
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

/// Horizontal strip of little chips, one per visible segment, hinting at the
/// composition shape. Widths are proportional to each segment's relative
/// weight and laid out against the card's actual width (GeometryReader), so a
/// dense template like "Complete" always fits instead of spilling past the
/// card. Pills draw rounded, text segments squared.
private struct MenuBarTemplateSchematic: View {
    let composition: MenuBarComposition
    let highlighted: Bool

    private static let spacing: CGFloat = 3
    private static let maxChips = 8

    var body: some View {
        let segments = Array(composition.visibleSegments.prefix(Self.maxChips))
        let weights = segments.map { weight($0) }
        let total = max(weights.reduce(0, +), 0.001)

        GeometryReader { geo in
            let available = geo.size.width - Self.spacing * CGFloat(max(segments.count - 1, 0))
            HStack(spacing: Self.spacing) {
                ForEach(Array(segments.enumerated()), id: \.offset) { i, segment in
                    RoundedRectangle(cornerRadius: segment.effectiveStyle == .pill ? 4 : 2)
                        .fill(highlighted ? Color.blue.opacity(0.55) : Color.white.opacity(0.22))
                        .frame(width: max(available * weights[i] / total, 2), height: 10)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }

    /// Relative visual weight: pills / label+value read widest, dots narrowest.
    private func weight(_ segment: MenuBarSegment) -> CGFloat {
        switch segment.effectiveStyle {
        case .dot, .glyph: return 1.0
        case .valueOnly, .delta: return 1.6
        default: return 2.6
        }
    }
}

// MARK: - Live preview (NSImage + click-to-select)

private struct MenuBarLivePreview: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var codexStore: CodexUsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var vendorStatusStore: VendorStatusStore

    @Binding var selectedSegmentID: UUID?

    private let scale: CGFloat = 2

    var body: some View {
        let data = MenuBarRenderer.RenderData.live(
            usage: usageStore, theme: themeStore, settings: settingsStore, vendor: vendorStatusStore,
            codex: codexStore
        )
        let rendered = MenuBarRenderer.renderWithHitRects(data)
        let w = rendered.image.size.width * scale
        let h = rendered.image.size.height * scale

        return VStack(spacing: 6) {
            Text(String(localized: "menuBar.editor.preview"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4)).tracking(1)
                .frame(maxWidth: .infinity)

            // A wide composition can overflow the pane; let it scroll
            // horizontally instead of clipping the rightmost segment.
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    Image(nsImage: rendered.image)
                        .resizable()
                        .frame(width: w, height: h)

                    ForEach(rendered.hitRects, id: \.id) { hit in
                        let x = hit.rect.minX * scale
                        let cw = hit.rect.width * scale
                        ZStack {
                            if selectedSegmentID == hit.id {
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.blue, lineWidth: 1.5)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.blue.opacity(0.12)))
                            }
                            Color.clear.contentShape(Rectangle())
                        }
                        .frame(width: cw, height: h)
                        .offset(x: x)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                selectedSegmentID = (selectedSegmentID == hit.id) ? nil : hit.id
                            }
                        }
                    }
                }
                .frame(width: w, height: h)
            }
            .frame(maxWidth: w)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: NSColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08), lineWidth: 0.5))
            )
            .environment(\.colorScheme, .dark)

            // Key the hint off the composition, not the rendered hit-rects:
            // the preview also shows the logo (no hit-rects) during an
            // error / no-config state, where segments may still be configured.
            Text(String(localized: settingsStore.menuBarComposition.visibleSegments.isEmpty ? "menuBar.editor.empty" : "menuBar.editor.preview.hint"))
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Segment list

private struct MenuBarSegmentListEditor: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var codexStore: CodexUsageStore

    @Binding var selectedSegmentID: UUID?
    @State private var draggingID: UUID?

    var body: some View {
        VStack(spacing: 8) {
            if settingsStore.menuBarComposition.segments.isEmpty {
                emptyHint
            } else {
                segmentRows
            }
        }
        .onDrop(of: [.text], delegate: ReorderGapDropDelegate(draggingID: $draggingID))
    }

    private var emptyHint: some View {
        Text(String(localized: "menuBar.editor.emptyList"))
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private var segmentRows: some View {
        ForEach(settingsStore.menuBarComposition.segments) { segment in
            MenuBarSegmentRow(
                segment: segment,
                isSelected: selectedSegmentID == segment.id,
                isDragging: draggingID == segment.id,
                unavailable: unavailability(segment.kind),
                onSelect: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedSegmentID = (selectedSegmentID == segment.id) ? nil : segment.id
                    }
                },
                onToggleHidden: { mutate(segment.id) { $0.isHidden.toggle() } },
                onDelete: { delete(segment) },
                onStyle: { style in setStyle(style, for: segment) },
                onShape: { shape in mutate(segment.id) { $0.options.pacingShape = shape } },
                onFormat: { format in mutate(segment.id) { $0.options.resetFormat = format } }
            )
            .id(segment.id)
            .onDrag {
                draggingID = segment.id
                return NSItemProvider(object: segment.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: ReorderDropDelegate(item: segment.id, items: segmentsBinding, draggingID: $draggingID))
        }
    }

    private var segmentsBinding: Binding<[MenuBarSegment]> {
        $settingsStore.menuBarComposition.segments
    }

    /// Why this segment would not draw, or nil when it draws. The decision
    /// itself still belongs to `MenuBarSegmentAvailability`, which mirrors the
    /// renderer; this only picks the sentence that explains it.
    private func unavailability(_ kind: MenuBarSegmentKind) -> EditorUnavailability? {
        EditorUnavailability.reason(
            for: kind, settings: settingsStore, usage: usageStore, codex: codexStore
        )
    }

    private func mutate(_ id: UUID, _ transform: (inout MenuBarSegment) -> Void) {
        guard let idx = settingsStore.menuBarComposition.segments.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            transform(&settingsStore.menuBarComposition.segments[idx])
        }
    }

    private func delete(_ segment: MenuBarSegment) {
        if selectedSegmentID == segment.id { selectedSegmentID = nil }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            settingsStore.menuBarComposition.segments.removeAll { $0.id == segment.id }
        }
    }

    private func setStyle(_ style: MenuBarSegmentStyle, for segment: MenuBarSegment) {
        mutate(segment.id) { $0.style = style }
    }
}

// MARK: - Segment row

private struct MenuBarSegmentRow: View {
    let segment: MenuBarSegment
    let isSelected: Bool
    let isDragging: Bool
    let unavailable: EditorUnavailability?
    let onSelect: () -> Void
    let onToggleHidden: () -> Void
    let onDelete: () -> Void
    let onStyle: (MenuBarSegmentStyle) -> Void
    let onShape: (PacingShape) -> Void
    let onFormat: (ResetDisplayFormat) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.35)).frame(width: 14)
                Image(systemName: segment.kind.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(segment.isHidden ? .white.opacity(0.3) : .white.opacity(0.7)).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    KindLabel(
                        provider: segment.kind.provider,
                        text: segment.kind.localizedLabel,
                        color: segment.isHidden ? .white.opacity(0.35) : .white.opacity(0.9)
                    )
                    if let unavailable {
                        Text(unavailable.label)
                            .font(.system(size: 9)).foregroundStyle(.orange.opacity(0.7))
                    }
                }
                Spacer(minLength: 4)
                Button(action: onToggleHidden) {
                    Image(systemName: segment.isHidden ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(segment.isHidden ? .white.opacity(0.35) : .blue)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4)).frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                if segment.kind.allowedStyles.count > 1 { styleMenu }
                if segment.kind.family == .pacing { shapeMenu }
                if segment.kind == .sessionReset { formatMenu }
                Spacer(minLength: 0)
            }
            .padding(.leading, 24)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(rowFill).shadow(color: isDragging ? .black.opacity(0.4) : .clear, radius: 10, y: 4))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(rowStroke, lineWidth: 1))
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
        return segment.isHidden ? Color.white.opacity(0.015) : Color.white.opacity(0.04)
    }

    private var rowStroke: Color {
        if isDragging || isSelected { return Color.blue.opacity(0.6) }
        return segment.isHidden ? Color.white.opacity(0.04) : Color.white.opacity(0.08)
    }

    private var styleMenu: some View {
        Menu {
            ForEach(segment.kind.allowedStyles) { style in
                Button {
                    onStyle(style)
                } label: {
                    if style == segment.style { Label(style.localizedLabel, systemImage: "checkmark") }
                    else { Text(style.localizedLabel) }
                }
            }
        } label: {
            EditorPickerLabel(caption: "editor.pick.style", value: segment.effectiveStyle.localizedLabel)
        }
        .menuStyle(.button).buttonStyle(.bordered).controlSize(.small).tint(.secondary).menuIndicator(.hidden).fixedSize()
    }

    private var shapeMenu: some View {
        Menu {
            ForEach(PacingShape.allCases) { shape in
                Button {
                    onShape(shape)
                } label: {
                    if shape == segment.options.pacingShape { Label("\(shape.glyph)  \(shape.localizedLabel)", systemImage: "checkmark") }
                    else { Text("\(shape.glyph)  \(shape.localizedLabel)") }
                }
            }
        } label: {
            EditorPickerLabel(caption: "editor.pick.shape", value: segment.options.pacingShape.localizedLabel)
        }
        .menuStyle(.button).buttonStyle(.bordered).controlSize(.small).tint(.secondary).menuIndicator(.hidden).fixedSize()
    }

    private var formatMenu: some View {
        Menu {
            ForEach(ResetDisplayFormat.allCases) { format in
                Button {
                    onFormat(format)
                } label: {
                    if format == segment.options.resetFormat { Label(format.localizedLabel, systemImage: "checkmark") }
                    else { Text(format.localizedLabel) }
                }
            }
        } label: {
            EditorPickerLabel(caption: "editor.pick.format", value: segment.options.resetFormat.localizedLabel)
        }
        .menuStyle(.button).buttonStyle(.bordered).controlSize(.small).tint(.secondary).menuIndicator(.hidden).fixedSize()
    }
}

/// Label content for the segment / element picker menus. Kept minimal (a type
/// icon + the current value); the menu itself is rendered with the system
/// `.bordered` button + `.button` menu style at the call site, which draws a
/// real button frame and the native disclosure chevron - unmistakably a
/// control, unlike a custom `Menu` label whose background/chevron the
/// borderless style silently dropped. The control's plain name is a tooltip.
struct EditorPickerLabel: View {
    let caption: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .opacity(0.6)
        }
        .help(Text(caption))
    }
}

// MARK: - Availability

/// Whether a segment would be drawn at all, asked by the add menu and by the
/// segment list alike.
///
/// It mirrors `MenuBarRenderer.isSegmentAvailable`, which is the gate that
/// actually decides. The two had drifted: the editor knew only Claude's cases
/// and answered yes to every Codex one, so an OpenAI segment added while
/// editing a Claude layout sat in the list with no marker and never appeared
/// in the menu bar. The provider gate comes first for the same reason it does
/// there: a segment belonging to a provider this scope does not show draws
/// nothing, whatever the account has.
@MainActor
enum MenuBarSegmentAvailability {
    static func isAvailable(
        _ kind: MenuBarSegmentKind,
        settings: SettingsStore,
        usage: UsageStore,
        codex: CodexUsageStore
    ) -> Bool {
        if let provider = kind.provider {
            guard settings.activeProviders.contains(provider) else { return false }
            guard settings.activeProviderMode.shows(provider) else { return false }
        }
        switch kind {
        case .fable, .fablePacing: return usage.hasFable
        case .extraCredits: return usage.hasExtraCredits
        case .codexSession, .codexSessionPacing:
            return codex.windows.contains { $0.kind == .session }
        case .codexWeekly, .codexWeeklyPacing:
            return codex.windows.contains { $0.kind == .weekly }
        default: return true
        }
    }
}
