import SwiftUI

/// Studio's fourth surface: the order and visibility of the home page's blocks.
///
/// Deliberately blocks rather than cards. The dashboard's cards are not
/// interchangeable the way the popover's cells are, and an editor that
/// pretended otherwise would have to lay out five different heights and
/// promise arrangements the page cannot render. Ordering and hiding is the
/// part that was actually missing.
struct DashboardEditorView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draggingID: String?

    private var entriesBinding: Binding<[DashboardComposition.Entry]> {
        $settingsStore.dashboardComposition.entries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("dashboard.editor.title")
                        .font(DS.Typography.title2)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text("dashboard.editor.hint")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                Spacer()
                darkButton("dashboard.editor.reset") {
                    withAnimation(reduceMotion ? nil : DS.Motion.glide) {
                        settingsStore.dashboardComposition = .default
                    }
                }
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(settingsStore.dashboardComposition.entries) { entry in
                        row(entry)
                            .id(entry.id)
                            // Same drag machinery as the popover and menu bar
                            // editors, down to the delegate: three editors
                            // with three feels is three things to learn.
                            .onDrag {
                                draggingID = entry.id
                                return NSItemProvider(object: entry.id as NSString)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: ReorderDropDelegate(
                                    item: entry.id,
                                    items: entriesBinding,
                                    draggingID: $draggingID
                                )
                            )
                    }
                }
                // Catch-all so a drop released in the gaps between rows still
                // ends the session instead of leaving a row stuck lifted.
                .onDrop(of: [.text], delegate: ReorderGapDropDelegate(draggingID: $draggingID))
            }

            Spacer(minLength: 0)
        }
    }

    /// The last visible block cannot be hidden. The dashboard has no
    /// empty-state of its own, so hiding all five leaves the header floating
    /// over nothing, in every mode, and Studio is the only way back.
    private func canHide(_ entry: DashboardComposition.Entry) -> Bool {
        if entry.isHidden { return true }
        return settingsStore.dashboardComposition.entries.filter { !$0.isHidden }.count > 1
    }

    private func row(_ entry: DashboardComposition.Entry) -> some View {
        let isDragging = draggingID == entry.id
        return HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Palette.textTertiary.opacity(0.7))

            // A wireframe of the block, not a render of it: the real views own
            // history and insight stores and warm a scan on appear, so a live
            // thumbnail would do real work every time Studio opened. The shape
            // is what you are moving, and the shape is what this draws.
            BlockWireframe(block: entry.block)
                .frame(width: 46, height: 30)
                .opacity(entry.isHidden ? 0.35 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.block.localizedName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(entry.isHidden ? DS.Palette.textTertiary : DS.Palette.textPrimary)
                // Marks, not prose. "Claude only" becomes "Claude, OpenAI and
                // Gemini only" at four providers; a row of glyphs stays a row
                // of glyphs however many there are.
                if entry.block.providers.count < MetricProvider.allCases.count {
                    ProviderSupportBadge(
                        providers: entry.block.providers,
                        describes: entry.block.localizedName,
                        size: 9
                    )
                }
            }

            Spacer()

            Button {
                guard canHide(entry) else { return }
                guard let index = settingsStore.dashboardComposition.entries
                    .firstIndex(where: { $0.id == entry.id }) else { return }
                withAnimation(reduceMotion ? nil : DS.Motion.springSnap) {
                    settingsStore.dashboardComposition.entries[index].isHidden.toggle()
                }
            } label: {
                Image(systemName: entry.isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(entry.isHidden ? DS.Palette.textTertiary : DS.Palette.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(DS.Palette.glassFill))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canHide(entry))
            .opacity(canHide(entry) ? 1 : 0.35)
            .help(canHide(entry) ? "" : String(localized: "dashboard.editor.lastBlock"))
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                .fill(Color.white.opacity(entry.isHidden ? 0.02 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                        .stroke(Color.white.opacity(isDragging ? 0.22 : 0.07), lineWidth: 1)
                )
        )
        .opacity(isDragging ? 0.45 : (entry.isHidden ? 0.6 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isDragging)
    }
}

/// A schematic of one dashboard block, at thumbnail size.
///
/// Three lines of shapes per block rather than a scaled render: the real cards
/// need their stores, and a preview that fetches is a preview that costs.
struct BlockWireframe: View {
    let block: DashboardBlock

    private let ink = Color.white.opacity(0.26)
    private let inkSoft = Color.white.opacity(0.13)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            switch block {
            case .hero:
                HStack(spacing: 3) {
                    VStack(alignment: .leading, spacing: 2) {
                        bar(width: w * 0.30, height: 2.5, color: inkSoft)
                        bar(width: w * 0.42, height: 7, color: ink)
                        bar(width: w * 0.26, height: 2.5, color: inkSoft)
                    }
                    Spacer(minLength: 0)
                    Circle()
                        .strokeBorder(ink, lineWidth: 2.5)
                        .frame(width: h * 0.62, height: h * 0.62)
                }
            case .windows:
                VStack(spacing: 3) {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(spacing: 3) {
                            ForEach(0..<2, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(inkSoft)
                                    .overlay(
                                        Circle().strokeBorder(ink, lineWidth: 1.5)
                                            .frame(width: h * 0.24, height: h * 0.24)
                                    )
                            }
                        }
                    }
                }
            case .pacing:
                VStack(spacing: 5) {
                    ForEach(0..<2, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 2) {
                            bar(width: w * (index == 0 ? 0.34 : 0.28), height: 2, color: inkSoft)
                            ZStack(alignment: .leading) {
                                Capsule().fill(inkSoft).frame(height: 3.5)
                                Capsule().fill(ink)
                                    .frame(width: w * (index == 0 ? 0.55 : 0.34), height: 3.5)
                            }
                        }
                    }
                }
            case .extraCredits:
                VStack(alignment: .leading, spacing: 4) {
                    bar(width: w * 0.44, height: 2.5, color: inkSoft)
                    ZStack(alignment: .leading) {
                        Capsule().fill(inkSoft).frame(height: 6)
                        Capsule().fill(ink).frame(width: w * 0.4, height: 6)
                    }
                    bar(width: w * 0.3, height: 2.5, color: inkSoft)
                }
            case .footer:
                HStack(spacing: 3) {
                    ForEach([0.30, 0.24, 0.30], id: \.self) { fraction in
                        Capsule()
                            .strokeBorder(ink, lineWidth: 1.5)
                            .frame(width: w * fraction, height: h * 0.34)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.black.opacity(0.28))
        )
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, height: CGFloat, color: Color) -> some View {
        Capsule().fill(color).frame(width: width, height: height)
    }
}
