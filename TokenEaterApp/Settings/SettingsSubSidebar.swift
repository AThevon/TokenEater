import SwiftUI

/// Secondary navigation column displayed inside the Settings space. Lists the
/// six settings sub-sections (general, display, themes, popover, agentWatchers,
/// performance). Slimmer than the primary sidebar (160pt vs 180pt) and uses
/// the settings module accent only.
struct SettingsSubSidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(String(localized: "sidebar.settings").uppercased())
                .font(DS.Typography.micro)
                .tracking(0.8)
                .foregroundStyle(DS.Palette.textTertiary)
                .padding(.leading, DS.Spacing.sm)
                .padding(.top, DS.Spacing.md)

            VStack(spacing: DS.Spacing.xxs) {
                ForEach(SettingsSection.allCases, id: \.rawValue) { section in
                    SubSidebarRow(section: section, isActive: section == selection) {
                        withAnimation(DS.Motion.springSnap) {
                            selection = section
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 160)
        .padding(.horizontal, DS.Spacing.xs)
        .background(
            // Sibling of the content panel -> same L1 to keep them visually
            // "in the same plane" instead of one feeling lifted relative to
            // the other.
            RoundedRectangle(cornerRadius: DS.Radius.card)
                .fill(DS.Palette.bgElevated.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card)
                        .stroke(DS.Palette.glassBorderLo, lineWidth: 1)
                )
        )
    }
}

// MARK: - Sub sidebar row

private struct SubSidebarRow: View {
    let section: SettingsSection
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: section.iconName)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16, alignment: .center)
                    .foregroundStyle(foregroundColor)

                Text(section.label)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(foregroundColor)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .contentShape(Rectangle())
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DS.Motion.springSnap) { isHovering = hovering }
        }
    }

    private var foregroundColor: Color {
        if isActive { return DS.Palette.textPrimary }
        if isHovering { return DS.Palette.textSecondary }
        return DS.Palette.textTertiary
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isActive {
            RoundedRectangle(cornerRadius: DS.Radius.input)
                .fill(DS.Palette.glassFillHi)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.input)
                        .stroke(DS.Palette.glassBorder, lineWidth: 1)
                )
        } else if isHovering {
            RoundedRectangle(cornerRadius: DS.Radius.input)
                .fill(DS.Palette.glassFill)
        }
    }
}
