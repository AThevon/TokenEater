import SwiftUI

/// Settings panel for the popover. Users pick a variant, see a live preview,
/// and reorder / hide individual blocks in each zone. Writes go back to
/// `settingsStore.popoverConfig`, which both this view and the real popover
/// observe.
struct PopoverSectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left column (50%) - header, variant picker, scrollable editor list.
            VStack(alignment: .leading, spacing: 16) {
                header
                VariantPickerView()
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        generalOptions
                        variantEditor
                        Spacer(minLength: 12)
                    }
                    .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 24)
            .padding(.top, 24)

            // Right column (50%) - sticky preview + reset action below.
            VStack(alignment: .center, spacing: 14) {
                LivePopoverPreview()
                resetButton
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.trailing, 24)
            .padding(.top, 24)
        }
    }

    private var resetButton: some View {
        Button {
            withAnimation {
                settingsStore.popoverConfig.resetLayout(for: settingsStore.popoverConfig.activeVariant)
            }
        } label: {
            Label(String(localized: "popover.settings.reset"), systemImage: "arrow.uturn.backward")
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.55))
    }

    private var header: some View {
        sectionTitle(
            String(localized: "popover.settings.title"),
            subtitle: String(localized: "popover.settings.subtitle")
        )
    }

    /// Non-variant-specific toggles rendered above the zone editors.
    private var generalOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "popover.zone.general"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.8)

            HStack(spacing: 10) {
                Toggle("", isOn: $settingsStore.popoverConfig.showPlanBadge)
                    .toggleStyle(.switch)
                    .tint(.blue)
                    .labelsHidden()
                Text(String(localized: "popover.option.showPlanBadge"))
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
    }

    @ViewBuilder
    private var variantEditor: some View {
        switch settingsStore.popoverConfig.activeVariant {
        case .classic:
            ClassicVariantEditor()
        case .compact:
            CompactVariantEditor()
        case .focus:
            FocusVariantEditor()
        }
    }
}

// MARK: - Variant picker

private struct VariantPickerView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PopoverVariant.allCases) { variant in
                let isActive = settingsStore.popoverConfig.activeVariant == variant
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        settingsStore.popoverConfig.activeVariant = variant
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: iconName(for: variant))
                            .font(.system(size: 16))
                        Text(variant.localizedLabel)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(isActive ? .white : .white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isActive ? Color.blue.opacity(0.2) : Color.white.opacity(0.03))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isActive ? Color.blue.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func iconName(for variant: PopoverVariant) -> String {
        switch variant {
        case .classic: return "circle.grid.2x1.fill"
        case .compact: return "square.grid.2x2.fill"
        case .focus:   return "target"
        }
    }
}

// MARK: - Live preview

private struct LivePopoverPreview: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        VStack(spacing: 8) {
            Text(String(localized: "popover.settings.preview"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(1)
                .frame(maxWidth: .infinity)

            // Render the same dispatcher used by the real popover.
            MenuBarPopoverView()
                .fixedSize()
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                .id(settingsStore.popoverConfig.activeVariant)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Classic editor

private struct ClassicVariantEditor: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZoneEditor(
                title: String(localized: "popover.zone.hero"),
                blocks: Binding(
                    get: { settingsStore.popoverConfig.classic.hero },
                    set: { settingsStore.popoverConfig.classic.hero = $0 }
                )
            )
            ZoneEditor(
                title: String(localized: "popover.zone.content"),
                blocks: Binding(
                    get: { settingsStore.popoverConfig.classic.middle },
                    set: { settingsStore.popoverConfig.classic.middle = $0 }
                )
            )
        }
    }
}

// MARK: - Compact editor

private struct CompactVariantEditor: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        ZoneEditor(
            title: String(localized: "popover.zone.content"),
            blocks: Binding(
                get: { settingsStore.popoverConfig.compact.middle },
                set: { settingsStore.popoverConfig.compact.middle = $0 }
            )
        )
    }
}

// MARK: - Focus editor

private struct FocusVariantEditor: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FocusHeroPicker()
            ZoneEditor(
                title: String(localized: "popover.zone.content"),
                blocks: Binding(
                    get: { settingsStore.popoverConfig.focus.middle },
                    set: { settingsStore.popoverConfig.focus.middle = $0 }
                )
            )
        }
    }
}

// MARK: - Focus hero radio

private struct FocusHeroPicker: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "popover.zone.hero"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.8)

            VStack(spacing: 4) {
                ForEach(FocusHeroChoice.allCases) { choice in
                    let isActive = settingsStore.popoverConfig.focusHero == choice
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            settingsStore.popoverConfig.focusHero = choice
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 14))
                                .foregroundStyle(isActive ? Color.blue : .white.opacity(0.3))
                            Text(choice.localizedLabel)
                                .font(.system(size: 12))
                                .foregroundStyle(isActive ? .white : .white.opacity(0.7))
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isActive ? Color.blue.opacity(0.08) : Color.white.opacity(0.02))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Zone editor (card-style reorderable toggle list)

private struct ZoneEditor: View {
    let title: String
    @Binding var blocks: [BlockState]

    @State private var draggingID: PopoverBlockID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.8)

            VStack(spacing: 8) {
                ForEach(blocks) { state in
                    BlockCard(
                        state: state,
                        isDragging: draggingID == state.id,
                        onToggle: {
                            if let idx = blocks.firstIndex(where: { $0.id == state.id }) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    blocks[idx].hidden.toggle()
                                }
                            }
                        }
                    )
                    .onDrag {
                        draggingID = state.id
                        return NSItemProvider(object: state.id.rawValue as NSString)
                    } preview: {
                        BlockCard(state: state, isDragging: true, onToggle: {})
                            .frame(width: 260)
                    }
                    .onDrop(
                        of: [.text],
                        delegate: BlockDropDelegate(
                            item: state.id,
                            list: $blocks,
                            draggingID: $draggingID
                        )
                    )
                }
            }
        }
    }
}

private struct BlockCard: View {
    let state: BlockState
    let isDragging: Bool
    let onToggle: () -> Void

    @State private var wiggle = false

    var body: some View {
        HStack(spacing: 12) {
            // Drag handle - visual affordance
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 16)

            // Label
            Text(state.id.localizedLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(state.hidden ? .white.opacity(0.35) : .white.opacity(0.9))

            Spacer()

            // Visibility toggle (eye / eye.slash) on the right side.
            // The whole card is also tappable for convenience.
            Image(systemName: state.hidden ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state.hidden ? .white.opacity(0.35) : .blue)
                .frame(width: 22, height: 22)
                .contentTransition(.symbolEffect(.replace))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(cardFill)
                .shadow(color: isDragging ? .black.opacity(0.4) : .clear, radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isDragging
                    ? Color.blue.opacity(0.6)
                    : state.hidden ? Color.white.opacity(0.04) : Color.white.opacity(0.08),
                    lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .rotationEffect(.degrees(wiggle ? -0.8 : 0.8))
        .scaleEffect(isDragging ? 1.03 : 1.0)
        .opacity(isDragging ? 0.9 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .onChange(of: isDragging) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.12).repeatForever(autoreverses: true)) {
                    wiggle.toggle()
                }
            } else {
                withAnimation(.easeInOut(duration: 0.1)) {
                    wiggle = false
                }
            }
        }
    }

    private var cardFill: Color {
        if isDragging {
            return Color.blue.opacity(0.12)
        }
        return state.hidden ? Color.white.opacity(0.015) : Color.white.opacity(0.04)
    }
}

/// Handles drop targets for reordering blocks within a zone. Swaps the
/// dragged block into the hovered slot on every drag tick for instant
/// feedback (no "release to commit" surprise).
private struct BlockDropDelegate: DropDelegate {
    let item: PopoverBlockID
    @Binding var list: [BlockState]
    @Binding var draggingID: PopoverBlockID?

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingID, dragging != item else { return }
        guard let from = list.firstIndex(where: { $0.id == dragging }),
              let to = list.firstIndex(where: { $0.id == item })
        else { return }
        if from != to {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                list.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
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
