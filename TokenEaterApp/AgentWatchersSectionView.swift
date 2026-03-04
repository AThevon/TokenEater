import SwiftUI

struct AgentWatchersSectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var tmuxCopied = false
    @State private var kittyCopied = false

    private let tmuxLine = """
    set-option -g update-environment "TERM_PROGRAM"
    """
    private let kittyLine = "allow_remote_control yes"

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(String(localized: "sidebar.agentWatchers"))

            // Enable/Disable
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.overlay.title"))
                    darkToggle(String(localized: "settings.overlay.toggle"), isOn: $settingsStore.overlayEnabled)

                    Text("settings.watchers.description")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Overlay style picker
            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    cardLabel(String(localized: "settings.watchers.style"))

                    HStack(spacing: 12) {
                        stylePreviewCard(.frost)
                        stylePreviewCard(.neon)
                    }
                }
            }

            // Behavior
            glassCard {
                VStack(alignment: .leading, spacing: 12) {
                    cardLabel(String(localized: "settings.watchers.behavior"))
                    darkToggle(String(localized: "settings.watchers.dock"), isOn: $settingsStore.overlayDockEffect)
                    darkToggle(String(localized: "settings.watchers.leftside"), isOn: $settingsStore.overlayLeftSide)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(String(localized: "settings.watchers.size"))
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.8))
                            Spacer()
                            Text("\(Int(settingsStore.overlayScale * 100))%")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.4))
                                .monospacedDigit()
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "minus")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.3))
                            Slider(value: $settingsStore.overlayScale, in: 0.6...1.6, step: 0.05)
                                .tint(.blue)
                            Image(systemName: "plus")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.3))
                        }

                        if abs(settingsStore.overlayScale - 1.1) > 0.01 {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    settingsStore.overlayScale = 1.1
                                }
                            } label: {
                                Text("settings.watchers.size.reset")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.blue.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Status legend
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.watchers.legend"))

                    darkToggle(String(localized: "settings.watchers.detailed"), isOn: $settingsStore.watchersDetailedMode)

                    if settingsStore.watchersDetailedMode {
                        statusRow(
                            color: Color(red: 0.3, green: 0.78, blue: 0.52),
                            label: String(localized: "settings.watchers.idle")
                        )
                        statusRow(
                            color: Color(red: 0.95, green: 0.62, blue: 0.22),
                            label: String(localized: "settings.watchers.thinking")
                        )
                        statusRow(
                            color: Color(red: 0.38, green: 0.58, blue: 0.95),
                            label: String(localized: "settings.watchers.executing")
                        )
                        statusRow(
                            color: Color(red: 0.7, green: 0.45, blue: 0.95),
                            label: String(localized: "settings.watchers.waiting")
                        )
                        statusRow(
                            color: Color(red: 0.25, green: 0.85, blue: 0.85),
                            label: String(localized: "settings.watchers.subagent")
                        )
                        statusRow(
                            color: Color(red: 0.55, green: 0.55, blue: 0.60),
                            label: String(localized: "settings.watchers.compacting")
                        )
                    } else {
                        statusRow(
                            color: Color(red: 0.3, green: 0.78, blue: 0.52),
                            label: String(localized: "settings.watchers.simple.idle")
                        )
                        statusRow(
                            color: Color(red: 0.95, green: 0.62, blue: 0.22),
                            label: String(localized: "settings.watchers.simple.working")
                        )
                    }
                }
            }

            // tmux setup
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.watchers.tmux.title"))

                    Text("settings.watchers.tmux.hint")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Text(tmuxLine)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.black.opacity(0.3))
                            )

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(tmuxLine.trimmingCharacters(in: .whitespacesAndNewlines), forType: .string)
                            tmuxCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                tmuxCopied = false
                            }
                        } label: {
                            Image(systemName: tmuxCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "settings.watchers.tmux.copy"))
                    }
                }
            }

            // Kitty setup
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.watchers.kitty.title"))

                    Text("settings.watchers.kitty.hint")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Text(kittyLine)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.black.opacity(0.3))
                            )

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(kittyLine, forType: .string)
                            kittyCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                kittyCopied = false
                            }
                        } label: {
                            Image(systemName: kittyCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "settings.watchers.kitty.copy"))
                    }
                }
            }

        }
        .padding(24)
        }
    }

    // MARK: - Style preview cards

    private func stylePreviewCard(_ style: WatcherStyle) -> some View {
        let isSelected = settingsStore.watcherStyle == style
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                settingsStore.watcherStyle = style
            }
        } label: {
            VStack(spacing: 6) {
                stylePreviewContent(style, isSelected: isSelected)
                    .frame(width: 56, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.white : .clear, lineWidth: 2)
                    )
                    .shadow(color: isSelected ? Color.white.opacity(0.3) : .clear, radius: 6)

                Text(style.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(isSelected ? 0.9 : 0.5))
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    @ViewBuilder
    private func stylePreviewContent(_ style: WatcherStyle, isSelected: Bool) -> some View {
        let previewColor = Color(red: 0.95, green: 0.62, blue: 0.22)

        switch style {
        case .frost:
            ZStack {
                // Frosted background
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThinMaterial)
                // Mini accent bar
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(previewColor)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                        .padding(.leading, 6)
                    Spacer()
                }
                // Placeholder lines
                VStack(alignment: .leading, spacing: 3) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white.opacity(0.5))
                        .frame(width: 28, height: 3)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(previewColor.opacity(0.5))
                        .frame(width: 20, height: 2)
                }
                .padding(.leading, 14)
            }

        case .neon:
            let neonPreviewColor = Color(red: 1.0, green: 0.55, blue: 0.1)
            ZStack {
                // Dark background
                RoundedRectangle(cornerRadius: 6)
                    .fill(.black.opacity(0.85))
                // Neon border
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(neonPreviewColor.opacity(0.8), lineWidth: 1.5)
                // Placeholder lines (monospaced feel)
                VStack(alignment: .leading, spacing: 3) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white.opacity(0.5))
                        .frame(width: 28, height: 3)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(neonPreviewColor.opacity(0.5))
                        .frame(width: 20, height: 2)
                }
            }
            .shadow(color: neonPreviewColor.opacity(0.4), radius: 4)

        }
    }

    // MARK: - Status legend row

    private func statusRow(color: Color, label: String) -> some View {
        HStack(spacing: 8) {
            statusIndicator(color: color)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    @ViewBuilder
    private func statusIndicator(color: Color) -> some View {
        switch settingsStore.watcherStyle {
        case .frost:
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)
        case .neon:
            let neonVariant = color
            RoundedRectangle(cornerRadius: 2)
                .fill(.black.opacity(0.6))
                .frame(width: 12, height: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(neonVariant.opacity(0.8), lineWidth: 1.5)
                )
                .shadow(color: neonVariant.opacity(0.4), radius: 3)
        }
    }
}
