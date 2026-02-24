import SwiftUI

struct UpdateModalView: View {
    @Environment(UpdateStore.self) private var updateStore

    private let sheetBg = Color(hex: "#141416")
    private let sheetCard = Color.white.opacity(0.04)
    private let accent = Color(hex: "#FF9F0A")

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
        .frame(width: 420, height: 340)
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
                Text(notes)
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
