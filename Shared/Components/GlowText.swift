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

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.5), radius: glowRadius)
    }
}
