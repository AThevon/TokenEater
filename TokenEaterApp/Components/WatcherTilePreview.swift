import SwiftUI

/// Reusable preview tile that renders a fake watcher in the user's chosen
/// `WatcherStyle`. Single source of truth for both the Settings > Watchers
/// style picker and the onboarding Watchers card scene - guarantees pixel
/// parity between the preview and the real overlay rendering.
///
/// Pass mock data via the initializer; the chrome (Frost / Neon) matches the
/// production rendering in `OverlayView` / `SessionTraitView`.
struct WatcherTilePreview: View {
    let style: WatcherStyle
    let project: String
    let branch: String
    let percentage: Int
    let statusColor: Color

    init(
        style: WatcherStyle,
        project: String = "TokenEater",
        branch: String = "feat/menu-bar",
        percentage: Int = 18,
        statusColor: Color = Color(red: 0.95, green: 0.62, blue: 0.22)
    ) {
        self.style = style
        self.project = project
        self.branch = branch
        self.percentage = percentage
        self.statusColor = statusColor
    }

    var body: some View {
        switch style {
        case .frost:
            HStack(spacing: 10) {
                statusDot(color: statusColor, neon: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(branch)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(project)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Text("\(percentage)%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    )
            )

        case .neon:
            HStack(spacing: 10) {
                statusDot(color: statusColor, neon: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(branch)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor)
                    Text(project)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(statusColor.opacity(0.55))
                }
                Spacer()
                Text("\(percentage)%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.black.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(statusColor.opacity(0.7), lineWidth: 1)
                    )
            )
            .shadow(color: statusColor.opacity(0.5), radius: 6)
        }
    }

    private func statusDot(color: Color, neon: Bool) -> some View {
        Circle()
            .fill(neon ? .clear : color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color.opacity(neon ? 0.95 : 0), lineWidth: neon ? 1.5 : 0)
            )
            .shadow(color: color.opacity(neon ? 0.7 : 0), radius: 4)
    }
}
