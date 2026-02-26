import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        ZStack {
            Color(nsColor: NSColor(red: 0.04, green: 0.04, blue: 0.10, alpha: 1))
                .ignoresSafeArea()
            Text("Dashboard — Coming Soon")
                .font(.title)
                .foregroundStyle(.white)
        }
        .frame(width: 650, height: 550)
    }
}
