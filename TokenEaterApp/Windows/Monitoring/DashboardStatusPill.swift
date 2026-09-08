import SwiftUI

struct DashboardStatusPill: View {
    let icon: String
    var label: String = ""
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            if !label.isEmpty {
                Text(label.uppercased())
                    .font(DS.Typography.micro)
                    .tracking(1.2)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            Text(value)
                .font(DS.Typography.label)
                .fontWeight(.semibold)
                .foregroundStyle(DS.Palette.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                .fill(DS.Palette.glassFill)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                        .stroke(tint.opacity(0.25), lineWidth: 0.8)
                )
        )
    }
}
