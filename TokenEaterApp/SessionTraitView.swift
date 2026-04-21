import SwiftUI

// MARK: - Session Trait View

struct SessionTraitView: View {
    let session: ClaudeSession
    let proximity: CGFloat // 0 = collapsed capsule, 1 = fully expanded card
    var scale: CGFloat = 1.0
    var leftSide: Bool = false
    var onTap: (() -> Void)?

    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var isPressed = false
    @State private var breathing = false
    @State private var glowing = false
    @State private var nudging = false
    @State private var nudgePhase = false

    // MARK: - Display logic (simple vs detailed)

    private var isDetailed: Bool { settingsStore.watchersDetailedMode }
    private var style: WatcherStyle { settingsStore.watcherStyle }
    private var displayMode: WatcherDisplayMode { settingsStore.watcherDisplayMode }

    private var needsAttention: Bool {
        session.state == .idle || session.state == .waiting
    }

    private var isActive: Bool {
        if isDetailed {
            switch session.state {
            case .thinking, .toolExec, .waiting, .subagent: return true
            case .idle, .compacting: return false
            }
        } else {
            switch session.state {
            case .idle, .waiting: return false
            case .thinking, .toolExec, .subagent, .compacting: return true
            }
        }
    }

    private var stateColor: Color {
        if isDetailed {
            switch session.state {
            case .idle: return Color(red: 0.3, green: 0.78, blue: 0.52)
            case .thinking: return Color(red: 0.95, green: 0.62, blue: 0.22)
            case .toolExec: return Color(red: 0.38, green: 0.58, blue: 0.95)
            case .waiting: return Color(red: 0.7, green: 0.45, blue: 0.95)
            case .subagent: return Color(red: 0.25, green: 0.85, blue: 0.85)
            case .compacting: return Color(red: 0.55, green: 0.55, blue: 0.60)
            }
        } else {
            switch session.state {
            case .idle, .waiting: return Color(red: 0.3, green: 0.78, blue: 0.52)
            case .thinking, .toolExec, .subagent, .compacting: return Color(red: 0.95, green: 0.62, blue: 0.22)
            }
        }
    }

    /// Neon: more saturated version of stateColor
    private var neonColor: Color {
        if isDetailed {
            switch session.state {
            case .idle: return Color(red: 0.2, green: 1.0, blue: 0.55)
            case .thinking: return Color(red: 1.0, green: 0.55, blue: 0.1)
            case .toolExec: return Color(red: 0.3, green: 0.5, blue: 1.0)
            case .waiting: return Color(red: 0.8, green: 0.35, blue: 1.0)
            case .subagent: return Color(red: 0.1, green: 1.0, blue: 1.0)
            case .compacting: return Color(red: 0.5, green: 0.5, blue: 0.6)
            }
        } else {
            switch session.state {
            case .idle, .waiting: return Color(red: 0.2, green: 1.0, blue: 0.55)
            case .thinking, .toolExec, .subagent, .compacting: return Color(red: 1.0, green: 0.55, blue: 0.1)
            }
        }
    }

    /// Active color depends on style
    private var activeColor: Color {
        switch style {
        case .neon: return neonColor
        case .frost: return stateColor
        }
    }

    private var stateLabel: String {
        if isDetailed {
            switch session.state {
            case .idle: return "idle"
            case .thinking: return "thinking…"
            case .toolExec: return "executing"
            case .waiting: return "waiting…"
            case .subagent: return "subagent"
            case .compacting: return "compacting"
            }
        } else {
            switch session.state {
            case .idle, .waiting: return "idle"
            case .thinking, .toolExec, .subagent, .compacting: return "working…"
            }
        }
    }

    // MARK: - Style-dependent properties

    private var fontDesign: Font.Design {
        style == .neon ? .monospaced : .rounded
    }

    // MARK: - Interpolated dimensions

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * max(0, min(1, t))
    }

    private var itemWidth: CGFloat { lerp(5 * scale, 185 * scale, proximity) }
    private var itemHeight: CGFloat { lerp(22 * scale, 46 * scale, proximity) }
    private var cornerRadius: CGFloat { lerp(2.5, 10, proximity) }
    private var textOpacity: Double { min(1, max(0, Double(proximity - 0.35) / 0.3)) }
    private var materialOpacity: Double { min(1, max(0, Double(proximity - 0.15) / 0.5)) }
    private var barWidth: CGFloat { lerp(5 * scale, 3 * scale, proximity) }

    /// Trailing (or leading, in left-dock mode) padding used to keep the
    /// source icon from visually overlapping truncated branch names. Only
    /// applied in projectAndBranch mode where the branch sits on the row
    /// the icon occupies; branchPriority mode puts the branch on the title
    /// row above the icon and doesn't need it.
    private var reservedIconPadding: CGFloat {
        session.sourceKind != .unknown && proximity > 0.5 ? 14 * scale : 0
    }

    /// Nudge: horizontal scale for the whole capsule (expands outward)
    private var nudgeScaleX: CGFloat {
        guard nudging, nudgePhase else { return 1.0 }
        return 1.8
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: proximity > 0.15 ? 8 : 0) {
            if leftSide {
                textContent
                accentIndicator
            } else {
                accentIndicator
                textContent
            }
        }
        .padding(.horizontal, lerp(0, 10 * scale, proximity))
        .padding(.vertical, lerp(2 * scale, 8 * scale, proximity))
        .frame(
            width: itemWidth,
            height: itemHeight,
            alignment: leftSide ? .trailing : .leading
        )
        .background { backgroundForStyle }
        .overlay(alignment: .bottom) { neonContextProgressBar }
        .overlay(alignment: leftSide ? .bottomLeading : .bottomTrailing) { sourceIcon }
        .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
        .scaleEffect(x: nudgeScaleX, y: 1.0, anchor: leftSide ? .leading : .trailing)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .onTapGesture {
            guard proximity > 0.3 else { return }
            withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    isPressed = false
                }
                onTap?()
            }
        }
        .onAppear {
            updateAnimations()
        }
        .onChange(of: session.state) { oldState, newState in
            let wasAttention = (oldState == .idle || oldState == .waiting)
            let isAttention = (newState == .idle || newState == .waiting)
            if !wasAttention && isAttention && proximity <= 0.15 {
                startNudge()
            } else if !isAttention {
                stopNudge()
            }
            updateAnimations()
        }
        .onChange(of: proximity > 0.15) { _, isNear in
            if isNear && nudging {
                stopNudge()
            }
        }
        .onChange(of: settingsStore.watcherAnimationsEnabled) { _, enabled in
            if enabled {
                updateAnimations()
            } else {
                stopNudge()
                withAnimation(.easeInOut(duration: 0.3)) {
                    breathing = false
                    glowing = false
                }
            }
        }
    }

    // MARK: - Background per style

    @ViewBuilder
    private var backgroundForStyle: some View {
        switch style {
        case .frost:
            frostBackground
        case .neon:
            neonBackground
        }
    }

    @ViewBuilder
    private var frostBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.black.opacity(0.55))
                .opacity(materialOpacity)

            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
                .opacity(materialOpacity)

            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(stateColor)
                .opacity(max(0, 1 - materialOpacity) * 0.85)

            if proximity > 0.3 {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(stateColor.opacity(0.15), lineWidth: 0.5)
                    .opacity(materialOpacity)
            }
        }
    }

    @ViewBuilder
    private var neonBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.black.opacity(0.85))
                .opacity(materialOpacity)

            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(neonColor)
                .opacity(max(0, 1 - materialOpacity) * 0.9)

            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(neonColor.opacity(0.8), lineWidth: 1.5)
                .opacity(materialOpacity)
        }
    }

    // MARK: - Shadow per style

    private var shadowColor: Color {
        switch style {
        case .frost:
            if isActive && proximity < 0.3 {
                return stateColor.opacity(glowing ? 0.7 : 0.2)
            }
            return .black.opacity(Double(proximity) * 0.1)
        case .neon:
            if isActive && proximity < 0.3 {
                return neonColor.opacity(glowing ? 0.9 : 0.3)
            }
            return neonColor.opacity(Double(proximity) * 0.25)
        }
    }

    private var shadowRadius: CGFloat {
        switch style {
        case .frost:
            return isActive && proximity < 0.3 ? (glowing ? 8 : 3) : 6
        case .neon:
            return isActive && proximity < 0.3 ? (glowing ? 12 : 5) : 8
        }
    }

    private var shadowY: CGFloat {
        switch style {
        case .frost:
            return isActive && proximity < 0.3 ? 0 : 2
        case .neon:
            return 0
        }
    }

    // MARK: - Accent indicator

    /// Context consumption ratio on 0.0 - 1.0 scale. Nil until the session has
    /// produced at least one assistant message with token usage data.
    private var contextFraction: CGFloat? {
        session.contextFraction.map { CGFloat($0) }
    }

    @ViewBuilder
    private var accentIndicator: some View {
        switch style {
        case .frost:
            // Vertical bottom-up bar: dim full-height track shows the status
            // colour at reduced opacity; a bright filled segment from the
            // bottom reflects context usage. When no context data is available
            // yet (brand-new session), fall back to the original full-height
            // solid bar so the state colour still reads at a glance.
            GeometryReader { geo in
                let radius = lerp(2.5, 1.5, proximity)
                let liveOpacity = session.state == .thinking ? (breathing ? 1.0 : 0.65) : 0.9
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(activeColor.opacity(contextFraction == nil ? 1.0 : 0.22))
                        .frame(width: barWidth, height: geo.size.height)
                        .opacity(contextFraction == nil ? liveOpacity : 1.0)
                    if let fraction = contextFraction {
                        RoundedRectangle(cornerRadius: radius)
                            .fill(activeColor)
                            .frame(width: barWidth, height: geo.size.height * fraction)
                            .opacity(liveOpacity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(width: barWidth)
        case .neon:
            EmptyView()
        }
    }

    // MARK: - Context progress bar (Neon only)

    /// Thin horizontal progress strip at the bottom edge. Neon-exclusive - the
    /// Frost theme shows context via the vertical accent bar. Kept subtle at
    /// rest so it doesn't compete with the tile content; a soft neon glow
    /// makes it readable without a value label, matching the arcade-ish look.
    @ViewBuilder
    private var neonContextProgressBar: some View {
        if style == .neon, let fraction = contextFraction, fraction > 0 {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(neonColor)
                        .frame(width: geo.size.width * fraction)
                        .shadow(color: neonColor.opacity(0.8), radius: 2)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 1.5)
            .padding(.horizontal, 2)
            .padding(.bottom, 1)
            .opacity(min(1, max(0.4, Double(proximity))))
        }
    }

    // MARK: - Source icon

    @ViewBuilder
    private var sourceIcon: some View {
        if session.sourceKind != .unknown && proximity > 0.5 {
            let icon = session.sourceKind == .ide
                ? "chevron.left.forwardslash.chevron.right"
                : "terminal"
            Image(systemName: icon)
                .font(.system(size: 7.5 * scale, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))
                .padding(leftSide ? .leading : .trailing, 8 * scale)
                .padding(.bottom, 4 * scale)
                .opacity(min(1, Double(proximity - 0.5) / 0.3))
        }
    }

    // MARK: - Text content

    @ViewBuilder
    private var textContent: some View {
        if proximity > 0.15 {
            if leftSide {
                Spacer(minLength: 0)
            }

            VStack(alignment: leftSide ? .trailing : .leading, spacing: 2 * scale) {
                switch displayMode {
                case .branchPriority:
                    Text(session.displayName)
                        .font(.system(size: 11.5 * scale, weight: .semibold, design: fontDesign))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(stateLabel)
                        .font(.system(size: 9 * scale, weight: .medium, design: fontDesign))
                        .foregroundStyle(activeColor.opacity(0.85))

                case .projectAndBranch:
                    Text(session.projectName)
                        .font(.system(size: 11.5 * scale, weight: .semibold, design: fontDesign))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 4 * scale) {
                        Text(stateLabel)
                            .font(.system(size: 9 * scale, weight: .medium, design: fontDesign))
                            .foregroundStyle(activeColor.opacity(0.85))
                            .layoutPriority(1)

                        if let branch = session.visibleBranch {
                            Text("·")
                                .font(.system(size: 9 * scale, weight: .bold, design: fontDesign))
                                .foregroundStyle(.white.opacity(0.3))
                            Text(branch)
                                .font(.system(size: 9 * scale, weight: .regular, design: fontDesign))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    // Reserve space for the source icon in the corner so a long
                    // branch name doesn't get visually chewed by it. The icon
                    // sits at bottom-leading or bottom-trailing depending on the
                    // dock side, so pad the matching side of this inner row.
                    .padding(leftSide ? .leading : .trailing, reservedIconPadding)
                }
            }
            .opacity(textOpacity)

            if !leftSide {
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Animations

    private func startNudge() {
        guard settingsStore.watcherAnimationsEnabled else { return }
        nudgePhase = false
        nudging = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.4).repeatForever(autoreverses: true)) {
            nudgePhase = true
        }
    }

    private func stopNudge() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            nudging = false
            nudgePhase = false
        }
    }

    private func updateAnimations() {
        guard settingsStore.watcherAnimationsEnabled else {
            breathing = false
            glowing = false
            return
        }

        if session.state == .thinking {
            breathing = false
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                breathing = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                breathing = false
            }
        }

        if isActive {
            glowing = false
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                glowing = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                glowing = false
            }
        }
    }
}
