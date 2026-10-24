import SwiftUI

/// A Claude account's identity mark: a dot in the colour the user picked for
/// it. It names the account and nothing else; risk colour stays on the
/// values next to it (Smart Color and the thresholds, `docs/design/COLORING.md`).
/// The thin light rim keeps a dark pick visible on the app's dark chrome.
struct AccountDot: View {
    let colorHex: String
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex))
            .overlay(
                Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: max(0.5, size / 14))
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
