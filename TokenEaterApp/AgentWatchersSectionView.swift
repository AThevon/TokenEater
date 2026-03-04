import SwiftUI

struct AgentWatchersSectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var tmuxCopied = false

    private let tmuxLine = """
    set-option -g update-environment "TERM_PROGRAM"
    """

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

                        if abs(settingsStore.overlayScale - 1.0) > 0.01 {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    settingsStore.overlayScale = 1.0
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

        }
        .padding(24)
        }
    }

    private func statusRow(color: Color, label: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
