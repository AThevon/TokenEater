import SwiftUI

/// Popover banner shown when a monitored vendor is degraded/down. Uses the
/// popover's own raw-colour idiom (not DS tokens), mirroring PopoverErrorBanner.
struct VendorStatusBanner: View {
    @EnvironmentObject private var vendorStatusStore: VendorStatusStore

    var body: some View {
        if vendorStatusStore.isDegraded, let status = vendorStatusStore.claudeStatus {
            content(for: status)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    private func tint(_ health: VendorHealth) -> Color {
        health == .down ? Color(red: 0.97, green: 0.44, blue: 0.44) : .orange
    }

    @ViewBuilder
    private func content(for status: VendorStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint(status.health))
                Text(headline(for: status.health))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 8)
                Link(String(localized: "status.banner.view"), destination: status.statusPageURL)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint(status.health))
            }
            if let incident = status.activeIncidents.first {
                Text(incident.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
        }
    }

    private func headline(for health: VendorHealth) -> String {
        health == .down
            ? String(localized: "status.banner.down")
            : String(localized: "status.banner.degraded")
    }
}
