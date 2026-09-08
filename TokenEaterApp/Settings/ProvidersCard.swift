import SwiftUI

struct ProvidersCard: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var codexStore: CodexUsageStore

    @State private var isTesting = false
    @State private var testResult: ConnectionTestResult?

    var body: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel(String(localized: "settings.providers.title"))
                darkToggle("Codex", isOn: $settingsStore.codexEnabled)
                Text(codexStore.connectionStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !settingsStore.codexEnabled, codexStore.authState.isTrackable {
                    Text("codex.tracking.off")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                HStack {
                    darkButton("codex.test.button") {
                        isTesting = true
                        testResult = nil
                        Task {
                            codexStore.handleAuthChange()
                            testResult = await codexStore.testConnection()
                            isTesting = false
                        }
                    }
                    .disabled(isTesting)
                    .opacity(isTesting ? 0.5 : 1)
                    if isTesting { ProgressView().controlSize(.small).tint(DS.Palette.textSecondary) }
                    Spacer()
                    CopyDiagnosticButton()
                }
                if let testResult {
                    Text(testResult.message)
                        .font(.system(size: 11))
                        .foregroundStyle(testResult.success ? .green : .orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
