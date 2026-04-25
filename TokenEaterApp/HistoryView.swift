import SwiftUI

/// History space -> JSONL session history browser. Placeholder until we land
/// the implementation from issue #145 (historical token usage graphs from
/// local JSONL session files). We already have the parser infra in
/// `JSONLParser.swift`; issue #145 describes the aggregation + chart layer.
struct HistoryView: View {
    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(DS.Palette.accentHistory.opacity(0.7))
                .dsGlow(color: DS.Palette.accentHistory, token: DS.Glow.subtle)

            VStack(spacing: DS.Spacing.xs) {
                Text("history.placeholder.title")
                    .font(DS.Typography.title1)
                    .foregroundStyle(DS.Palette.textPrimary)

                Text("history.placeholder.subtitle")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Spacing.xxl)
    }
}
