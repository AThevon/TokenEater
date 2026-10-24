import SwiftUI

/// The name of a Claude account, as the user types it.
///
/// Bound to the caller's own draft, never to a store: the field cuts input at
/// `AccountNameRules.maxLength` as it is typed, and `onCommit` runs on Return
/// and when the field loses focus, which is when Settings saves it. A name
/// shows in full here and in tooltips; narrow surfaces shorten it.
struct AccountNameField: View {
    @Binding var name: String
    var placeholder: String = String(localized: "accounts.name.placeholder")
    var onCommit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Palette.textPrimary)
                .focused($focused)
                .onSubmit(onCommit)
            Text("\(name.count)/\(AccountNameRules.maxLength)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                        .stroke(focused ? DS.Palette.glassBorderHi : DS.Palette.glassBorder, lineWidth: 1)
                )
        )
        .onChange(of: name) { _, typed in
            let flat = typed.replacingOccurrences(of: "\n", with: " ")
            let cut = flat.count > AccountNameRules.maxLength
                ? String(flat.prefix(AccountNameRules.maxLength))
                : flat
            if cut != typed { name = cut }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { onCommit() }
        }
    }
}
