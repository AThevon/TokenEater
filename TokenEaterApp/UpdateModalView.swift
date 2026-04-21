import SwiftUI

struct UpdateModalView: View {
    @EnvironmentObject private var updateStore: UpdateStore
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var iconFloat: Bool = false
    @State private var shimmerOffset: CGFloat = -200
    @State private var checkmarkScale: CGFloat = 0
    @State private var contentOpacity: Double = 0

    var body: some View {
        ZStack {
            // Backdrop blur
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isBlockingState { updateStore.dismissUpdateModal() }
                }

            // Modal card
            VStack(spacing: 0) {
                switch updateStore.updateState {
                case .available(let version, _, _, _):
                    availableContent(newVersion: version)
                case .downloading(let progress):
                    downloadingContent(progress: progress)
                case .downloaded:
                    downloadedContent
                case .installing:
                    installingContent
                case .error(let message):
                    errorContent(message: message)
                default:
                    EmptyView()
                }
            }
            .padding(32)
            .frame(width: 440)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial.opacity(0.2))
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: accentColor.opacity(0.15), radius: 40, y: 10)
            .opacity(contentOpacity)
            .scaleEffect(contentOpacity == 0 ? 0.92 : 1.0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                contentOpacity = 1
            }
        }
    }

    // MARK: - Available State

    private func availableContent(newVersion: String) -> some View {
        VStack(spacing: 20) {
            // Floating app icon with glow
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.08))
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: accentColor.opacity(0.3), radius: 12)
                        .offset(y: iconFloat ? -3 : 3)
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    iconFloat = true
                }
            }

            // Title
            VStack(spacing: 8) {
                Text(String(localized: "update.available.title"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                Text(String(localized: "update.available.subtitle"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }

            // Version badges
            HStack(spacing: 16) {
                versionBadge(updateStore.currentVersion, isCurrent: true)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor.opacity(0.6))
                versionBadge(newVersion, isCurrent: false)
            }

            // Release notes
            releaseNotesSection(version: newVersion)

            // Buttons
            VStack(spacing: 12) {
                shimmerButton(String(localized: "update.download")) {
                    updateStore.downloadUpdate()
                }

                Button(String(localized: "update.later")) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        contentOpacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        updateStore.dismissUpdateModal()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    // MARK: - Release Notes

    /// "What's new" section: small tracked label + scrollable container with
    /// rendered markdown. Loading state shows a spinner, failure shows a
    /// "View on GitHub" fallback link so users always have a way to read the
    /// notes even if the API hiccups.
    @ViewBuilder
    private func releaseNotesSection(version: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accentColor.opacity(0.7))
                Text(String(localized: "update.notes.title").uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(1.3)
                Spacer()
                Button {
                    if let url = URL(string: "https://github.com/AThevon/TokenEater/releases/tag/v\(version)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(String(localized: "update.notes.viewOnGitHub"))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            releaseNotesBody
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.025))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.05), lineWidth: 0.5)
                        )
                )
        }
    }

    @ViewBuilder
    private var releaseNotesBody: some View {
        if updateStore.releaseNotesLoading {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                Text(String(localized: "update.notes.loading"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        } else if let notes = updateStore.releaseNotes, !notes.isEmpty {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(parseMarkdown(notes).enumerated()), id: \.offset) { _, block in
                        markdownLine(block)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
        } else {
            Text(String(localized: "update.notes.unavailable"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
    }

    // MARK: - Lightweight Markdown

    private enum MarkdownBlock {
        case h1(String), h2(String), h3(String)
        case bullet(String)
        case paragraph(String)
        case blank
    }

    /// Line-by-line markdown parser tuned for GitHub release notes. Full
    /// CommonMark is overkill here - release bodies are typically a short mix
    /// of headers, bullets, and paragraphs. Inline formatting (bold, italic,
    /// code, links) is delegated to `AttributedString(markdown:)` per block.
    private func parseMarkdown(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        for rawLine in source.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                blocks.append(.blank)
            } else if line.hasPrefix("### ") {
                blocks.append(.h3(String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                blocks.append(.h2(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                blocks.append(.h1(String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else {
                blocks.append(.paragraph(line))
            }
        }
        return blocks
    }

    @ViewBuilder
    private func markdownLine(_ block: MarkdownBlock) -> some View {
        switch block {
        case .h1(let text):
            Text(attributedInline(text))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.top, 6)
        case .h2(let text):
            Text(attributedInline(text))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 4)
        case .h3(let text):
            Text(attributedInline(text))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .tracking(0.3)
                .padding(.top, 2)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 7) {
                Text("•")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accentColor.opacity(0.7))
                Text(attributedInline(text))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 2)
        case .paragraph(let text):
            Text(attributedInline(text))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        case .blank:
            Spacer().frame(height: 4)
        }
    }

    /// Parse inline markdown (bold / italic / code / links) via Foundation's
    /// built-in parser. Falls back to plain text if parsing fails.
    private func attributedInline(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(text)
    }

    // MARK: - Downloading State

    private func downloadingContent(progress: Double) -> some View {
        VStack(spacing: 24) {
            // Ring gauge progress
            ZStack {
                // Background glow
                Circle()
                    .fill(accentColor.opacity(0.06))
                    .frame(width: 140, height: 140)
                    .blur(radius: 25)

                RingGauge(
                    percentage: Int(progress * 100),
                    gradient: themeStore.current.gaugeGradient(for: 30, thresholds: themeStore.thresholds),
                    size: 120,
                    glowColor: accentColor,
                    glowRadius: 8
                )

                // Percentage text
                VStack(spacing: 2) {
                    Text("\(Int(progress * 100))")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: accentColor.opacity(0.5), radius: 4)
                    Text("%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .contentTransition(.numericText(countsDown: false))
                .animation(.spring(response: 0.3), value: Int(progress * 100))
            }

            VStack(spacing: 6) {
                Text(String(localized: "update.downloading"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))

                Text(String(localized: "update.downloading.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    // MARK: - Downloaded State

    private var downloadedContent: some View {
        VStack(spacing: 24) {
            // Success checkmark
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.08))
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Circle()
                        .stroke(Color.green.opacity(0.3), lineWidth: 2)
                        .frame(width: 72, height: 72)
                    Image(systemName: "checkmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.green)
                        .shadow(color: .green.opacity(0.5), radius: 4)
                }
                .scaleEffect(checkmarkScale)
            }
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    checkmarkScale = 1
                }
            }

            VStack(spacing: 8) {
                Text(String(localized: "update.ready.title"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                Text(String(localized: "update.ready.subtitle"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            VStack(spacing: 12) {
                shimmerButton(String(localized: "update.install")) {
                    updateStore.installUpdate()
                }

                Text(String(localized: "update.install.hint"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
        }
    }

    // MARK: - Installing State

    @State private var installRotation: Double = 0

    private var installingContent: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.08))
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                ZStack {
                    Circle()
                        .stroke(accentColor.opacity(0.1), lineWidth: 3)
                        .frame(width: 72, height: 72)

                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(installRotation))

                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .shadow(color: accentColor.opacity(0.5), radius: 4)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    installRotation = 360
                }
            }

            VStack(spacing: 8) {
                Text(String(localized: "update.installing"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))

                Text(String(localized: "update.installing.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
    }

    // MARK: - Error State

    private func errorContent(message: String) -> some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.08))
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 2)
                        .frame(width: 72, height: 72)
                    Image(systemName: "xmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.red)
                }
            }

            VStack(spacing: 8) {
                Text("Install failed")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .lineLimit(5)
            }

            Button("Dismiss") {
                updateStore.dismissUpdateModal()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.35))
        }
    }

    // MARK: - Components

    private func versionBadge(_ version: String, isCurrent: Bool) -> some View {
        VStack(spacing: 4) {
            Text(isCurrent ? String(localized: "update.version.current") : String(localized: "update.version.new"))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
                .textCase(.uppercase)
                .tracking(0.5)
            Text("v\(version)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(isCurrent ? .white.opacity(0.5) : accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isCurrent ? .white.opacity(0.04) : accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isCurrent ? .white.opacity(0.06) : accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func shimmerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        Capsule()
                            .fill(accentColor.opacity(0.2))
                        Capsule()
                            .stroke(accentColor.opacity(0.4), lineWidth: 1)

                        // Shimmer
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.08), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .offset(x: shimmerOffset)
                            .mask(Capsule())
                    }
                )
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 400
            }
        }
    }

    // MARK: - Helpers

    private var accentColor: Color {
        themeStore.current.gaugeColor(for: 30, thresholds: themeStore.thresholds)
    }

    private var isBlockingState: Bool {
        switch updateStore.updateState {
        case .downloading, .installing: return true
        default: return false
        }
    }
}
