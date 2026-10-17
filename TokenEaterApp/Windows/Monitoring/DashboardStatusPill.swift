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
                // One line, always: a label broken mid-word ("ORGANI" over
                // "ZATION") is what a narrow column used to get.
                Text(label.uppercased())
                    .font(DS.Typography.micro)
                    .tracking(1.2)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(value)
                .font(DS.Typography.label)
                .fontWeight(.semibold)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
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

/// One pill of a footer row.
struct DashboardPill: Identifiable {
    let id: String
    let icon: String
    var label: String = ""
    let value: String
    let tint: Color
}

/// A footer's pills: on one line while they fit whole, else one under the
/// other, and only then without their labels, the value cut last.
struct DashboardPillRow: View {
    let pills: [DashboardPill]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.xs) {
                ForEach(pills) { pill($0, labelled: true).fixedSize() }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(pills) { pill($0, labelled: true).fixedSize() }
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(pills) { pill($0, labelled: false) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pill(_ pill: DashboardPill, labelled: Bool) -> some View {
        DashboardStatusPill(icon: pill.icon, label: labelled ? pill.label : "", value: pill.value, tint: pill.tint)
    }
}
