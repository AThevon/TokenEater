import SwiftUI

struct GlowText: View {
    let text: String
    let font: Font
    let color: Color
    let glowRadius: CGFloat

    init(_ text: String, font: Font = .title, color: Color = .white, glowRadius: CGFloat = 4) {
        self.text = text
        self.font = font
        self.color = color
        self.glowRadius = glowRadius
    }

    /// A `glowRadius` of 0 or less draws plain text, with no shadow pass at
    /// all (a 0-radius shadow would still thicken the glyph edges).
    var body: some View {
        if glowRadius > 0 {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .dsGlow(color, radius: glowRadius, opacity: 0.5)
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(color)
        }
    }
}
