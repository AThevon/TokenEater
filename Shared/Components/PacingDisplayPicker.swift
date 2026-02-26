import SwiftUI

struct PacingDisplayPicker: View {
    @Binding var selection: PacingDisplayMode

    private let modes: [(mode: PacingDisplayMode, preview: String)] = [
        (.dot, "\u{25CF}"),
        (.dotDelta, "\u{25CF} +3%"),
        (.delta, "+3%"),
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(modes, id: \.mode) { item in
                Button {
                    selection = item.mode
                } label: {
                    Text(item.preview)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(selection == item.mode ? Color.green : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selection == item.mode ? Color.green.opacity(0.12) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(selection == item.mode ? Color.green.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
