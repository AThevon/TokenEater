import SwiftUI

struct AppSidebar: View {
    @Binding var selection: AppSection

    private let sidebarBg = Color(red: 0.10, green: 0.10, blue: 0.12)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                ForEach(AppSection.allCases, id: \.rawValue) { section in
                    sidebarButton(for: section)
                }
            }
            .padding(.top, 12)

            Spacer()

            // Quit button
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "menubar.quit"))
            .padding(.bottom, 12)
        }
        .frame(width: 60)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(sidebarBg)
        )
    }

    // MARK: - Sidebar Button

    private func sidebarButton(for section: AppSection) -> some View {
        let isActive = selection == section

        return Button {
            selection = section
        } label: {
            Image(systemName: section.iconName)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(isActive ? 1.0 : 0.4))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(isActive ? 0.1 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section.label)
    }
}

// MARK: - AppSection Helpers

extension AppSection {
    var iconName: String {
        switch self {
        case .dashboard: "chart.bar.fill"
        case .display: "display"
        case .themes: "paintpalette.fill"
        case .agentWatchers: "eye.fill"
        case .performance: "gauge.with.dots.needle.33percent"
        case .settings: "gearshape.fill"
        }
    }

    var label: String {
        switch self {
        case .dashboard: String(localized: "sidebar.dashboard")
        case .display: String(localized: "sidebar.display")
        case .themes: String(localized: "sidebar.themes")
        case .agentWatchers: String(localized: "sidebar.agentWatchers")
        case .performance: String(localized: "sidebar.performance")
        case .settings: String(localized: "sidebar.settings")
        }
    }
}
