import SwiftUI
import AppKit

/// The identity colour of a Claude account: eight presets chosen to stay
/// clear of the risk colours, and a custom colour for anyone who wants
/// another. Colours already worn by another account are marked, not refused:
/// two accounts may share one if the user wants that.
struct AccountColorPicker: View {
    @Binding var colorHex: String
    /// The colours the other tracked accounts wear.
    var taken: [String] = []
    /// The gauges' risk colours in the active theme. A custom colour close to
    /// one of them is flagged, since a dot that looks like a warning next to
    /// a value invites a misreading.
    var riskColors: [String] = []

    /// The system picker's own value. Local state, pushed to `colorHex` on
    /// change, so no hand-made binding is needed.
    @State private var custom: Color = .white

    private var selected: String? { AccountPalette.normalizedHex(colorHex) }
    private var isCustom: Bool {
        guard let selected else { return false }
        return !AccountPalette.presets.contains(selected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            swatches
            if isCustom, let selected, AccountPalette.resemblesRiskColor(selected, riskColors: riskColors) {
                Label(String(localized: "accounts.color.nearRisk"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.semanticWarning.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var swatches: some View {
        HStack(spacing: 7) {
            ForEach(AccountPalette.presets, id: \.self) { hex in
                swatch(hex)
            }
            Rectangle()
                .fill(DS.Palette.glassBorder)
                .frame(width: 1, height: 16)
                .padding(.horizontal, 2)
            ColorPicker("", selection: $custom, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 26, height: 20)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isCustom ? DS.Palette.textPrimary.opacity(0.8) : .clear, lineWidth: 1.5)
                        .padding(-2)
                )
                .help(String(localized: "accounts.color.custom"))
        }
        .onAppear {
            if let selected { custom = Color(hex: selected) }
        }
        .onChange(of: custom) { _, picked in
            let hex = (NSColor(picked).usingColorSpace(.sRGB) ?? NSColor(picked)).hexString()
            if hex != selected { colorHex = hex }
        }
    }

    private func swatch(_ hex: String) -> some View {
        let isSelected = selected == hex
        let isTaken = taken.compactMap(AccountPalette.normalizedHex).contains(hex)
        return Button {
            colorHex = hex
        } label: {
            ZStack {
                Circle()
                    .stroke(isSelected ? DS.Palette.textPrimary.opacity(0.85) : .clear, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                AccountDot(colorHex: hex, size: 16)
                    .opacity(isTaken && !isSelected ? 0.4 : 1)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isTaken && !isSelected
              ? String(localized: "accounts.color.taken")
              : "")
        .accessibilityLabel(Text(hex))
    }
}
