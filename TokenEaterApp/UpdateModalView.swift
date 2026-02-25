import SwiftUI

struct UpdateModalView: View {
    @EnvironmentObject private var updateStore: UpdateStore
    @State private var copied = false

    private let sheetBg = Color(hex: "#141416")
    private let sheetCard = Color.white.opacity(0.04)
    private let accent = Color(hex: "#FF9F0A")
    private let brewCommand = "brew update && brew upgrade --cask --greedy tokeneater"

    var body: some View {
        ZStack {
            sheetBg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.bottom, 20)

                if let notes = updateStore.releaseNotes, !notes.isEmpty {
                    releaseNotesSection(notes)
                        .padding(.bottom, 20)
                }

                terminalSection
                    .padding(.bottom, 16)

                if let error = updateStore.updateError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.bottom, 12)
                }

                actions
            }
            .padding(24)
        }
        .frame(width: 440, height: 400)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(accent)
                    Text("update.available")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                HStack(spacing: 8) {
                    let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                    Text("v\(current)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("v\(updateStore.latestVersion ?? "?")")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(accent)
                }
            }
            Spacer()
            Button {
                updateStore.dismissUpdate()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Release Notes

    private func releaseNotesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("update.releasenotes")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            ScrollView {
                Text(renderMarkdown(notes))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(sheetCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
            .frame(maxHeight: 150)
        }
    }

    // MARK: - Markdown

    private func renderMarkdown(_ raw: String) -> AttributedString {
        let processed = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("## ") {
                    return "**\(trimmed.dropFirst(3))**"
                } else if trimmed.hasPrefix("# ") {
                    return "**\(trimmed.dropFirst(2))**"
                } else if trimmed.hasPrefix("* ") {
                    return "• \(trimmed.dropFirst(2))"
                } else if trimmed.hasPrefix("- ") {
                    return "• \(trimmed.dropFirst(2))"
                }
                return String(line)
            }
            .joined(separator: "\n")

        if let attr = try? AttributedString(
            markdown: processed,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attr
        }
        return AttributedString(raw)
    }

    // MARK: - Terminal Command

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("update.terminal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))

            HStack(spacing: 8) {
                Text(brewCommand)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(brewCommand, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(copied ? .green : .white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Button("update.skip") {
                updateStore.skipCurrentUpdate()
            }
            .foregroundStyle(.secondary)

            Spacer()

            Button("update.later") {
                updateStore.dismissUpdate()
            }

            Button {
                updateStore.performUpdate()
            } label: {
                if updateStore.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("update.now", systemImage: "arrow.down.circle.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(updateStore.isUpdating)
        }
    }
}
