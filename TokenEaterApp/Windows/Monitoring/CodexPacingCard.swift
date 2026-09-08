import SwiftUI

struct CodexPacingCard: View {
    @EnvironmentObject private var themeStore: ThemeStore

    let pacing: PacingResult

    var body: some View {
        let tint = themeStore.current.pacingColor(for: pacing.zone)
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top, spacing: DS.Spacing.xs) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tint)
                        Text(String(localized: "pacing.weekly.label").uppercased())
                            .font(DS.Typography.micro)
                            .tracking(1.4)
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                    HStack(spacing: DS.Spacing.xxs) {
                        Circle().fill(tint).frame(width: 5, height: 5)
                        Text(zoneLabel)
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(tint)
                    }
                }
                Spacer()
                Text("\(pacing.delta >= 0 ? "+" : "")\(Int(pacing.delta))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(value: pacing.delta))
            }
            PacingBar(
                actual: pacing.actualUsage, expected: pacing.expectedUsage,
                zone: pacing.zone, gradient: themeStore.current.pacingGradient(for: pacing.zone),
                compact: true
            )
            Text(pacing.message)
                .font(DS.Typography.label)
                .foregroundStyle(tint.opacity(0.85))
                .lineLimit(1)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 124)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .fill(DS.Palette.bgElevated.opacity(0.85))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.card))
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .fill(LinearGradient(colors: [tint.opacity(0.06), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(tint.opacity(0.2), lineWidth: 1))
        .dsShadow(DS.Shadow.subtle)
    }

    private var zoneLabel: String {
        switch pacing.zone {
        case .chill: String(localized: "pacing.zone.chill")
        case .onTrack: String(localized: "pacing.zone.ontrack")
        case .warning: String(localized: "pacing.zone.warning")
        case .hot: String(localized: "pacing.zone.hot")
        }
    }
}
