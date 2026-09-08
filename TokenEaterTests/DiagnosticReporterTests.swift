import Testing
import Foundation

@MainActor
@Suite("Diagnostic Reporter")
struct DiagnosticReporterTests {

    private func makeStores(
        errorState: AppErrorState = .none,
        hasConfig: Bool = true,
        lastUpdate: Date? = nil,
        proxyEnabled: Bool = false
    ) -> (UsageStore, SettingsStore) {
        let store = UsageStore(
            repository: MockUsageRepository(),
            tokenProvider: MockTokenProvider(),
            sharedFileService: MockSharedFileService(),
            notificationService: MockNotificationService()
        )
        store.errorState = errorState
        store.hasConfig = hasConfig
        store.lastUpdate = lastUpdate
        if proxyEnabled {
            store.proxyConfig = ProxyConfig(enabled: true, host: "10.0.0.5", port: 1080)
        }
        let settings = SettingsStore(notificationService: MockNotificationService(), tokenProvider: MockTokenProvider())
        return (store, settings)
    }

    private func makeStoresWithError(
        apiError: APIError,
        lastUpdate: Date? = nil
    ) async -> (UsageStore, SettingsStore) {
        let repo = MockUsageRepository()
        repo.stubbedError = apiError
        let tokenProvider = MockTokenProvider()
        tokenProvider.token = "fake-token"
        let store = UsageStore(
            repository: repo,
            tokenProvider: tokenProvider,
            sharedFileService: MockSharedFileService(),
            notificationService: MockNotificationService()
        )
        store.lastUpdate = lastUpdate
        await store.refresh(force: true)
        let settings = SettingsStore(notificationService: MockNotificationService(), tokenProvider: MockTokenProvider())
        return (store, settings)
    }

    @Test("Codex diagnostics contain operational state without account identity or credentials")
    func codexDiagnostics() async {
        let (usage, settings) = makeStores()
        let provider = MockCodexTokenProvider()
        provider.credentials = CodexFixtures.credentials()
        provider.stubbedAuthState = .chatgpt(accountId: "private-account-identity", planType: "pro", expiresAt: nil)
        let codex = CodexUsageStore(
            repository: MockCodexUsageRepository(), tokenProvider: provider,
            sharedFileService: MockCodexSharedFileService(), notificationService: MockNotificationService()
        )
        codex.setEnabled(true)
        await codex.refresh(force: true)
        let report = DiagnosticReporter.makeReport(usageStore: usage, settingsStore: settings, codexStore: codex)
        #expect(report.contains("**Codex**"))
        #expect(report.contains("Auth state: chatgpt"))
        #expect(report.contains("duration 604800s"))
        #expect(!report.contains("private-account-identity"))
        #expect(!report.contains(provider.credentials!.accessToken))
        codex.setEnabled(false)
    }

    @Test("includes app version, build, and architecture")
    func includesAppMetadata() {
        let (store, settings) = makeStores()
        let report = DiagnosticReporter.makeReport(usageStore: store, settingsStore: settings)
        #expect(report.contains("**App**"))
        #expect(report.contains("Version:"))
        #expect(report.contains("Bundle:"))
        #expect(report.contains("Architecture:"))
    }

    @Test("includes macOS version")
    func includesSystemSection() {
        let (store, settings) = makeStores()
        let report = DiagnosticReporter.makeReport(usageStore: store, settingsStore: settings)
        #expect(report.contains("**System**"))
        #expect(report.contains("macOS:"))
    }

    @Test("rate-limited error captures HTTP 429 and raw Retry-After header")
    func rateLimitedRendersAllFields() async {
        let (store, settings) = await makeStoresWithError(
            apiError: .rateLimited(retryAfter: 0, retryAfterRaw: "0", endpoint: "/api/oauth/usage")
        )
        let report = DiagnosticReporter.makeReport(usageStore: store, settingsStore: settings)
        #expect(report.contains("Error state: rateLimited"))
        #expect(report.contains("HTTP status: 429"))
        #expect(report.contains("Retry-After header (raw): \"0\""))
        #expect(report.contains("Endpoint: /api/oauth/usage"))
    }

    @Test("token-expired error renders status code in API error block")
    func tokenExpiredRendersStatus() async {
        let (store, settings) = await makeStoresWithError(
            apiError: .tokenExpired(endpoint: "/api/oauth/usage", statusCode: 401)
        )
        let report = DiagnosticReporter.makeReport(usageStore: store, settingsStore: settings)
        #expect(report.contains("HTTP status: 401"))
        #expect(report.contains("Endpoint: /api/oauth/usage"))
    }

    @Test("network error renders underlying message")
    func networkErrorRendersUnderlying() async {
        let (store, settings) = await makeStoresWithError(
            apiError: .networkError(endpoint: "/api/oauth/usage", underlying: "The Internet connection appears to be offline.")
        )
        let report = DiagnosticReporter.makeReport(usageStore: store, settingsStore: settings)
        #expect(report.contains("Underlying error: The Internet connection appears to be offline."))
    }

    @Test("missing last API error renders 'None captured'")
    func noLastAPIErrorRendersGracefully() {
        let (store, settings) = makeStores()
        let report = DiagnosticReporter.makeReport(usageStore: store, settingsStore: settings)
        #expect(report.contains("None captured"))
    }

    @Test("nil optional fields render as a dash, not 'Optional(nil)'")
    func nilFieldsRenderAsDash() {
        let (store, settings) = makeStores()
        let report = DiagnosticReporter.makeReport(usageStore: store, settingsStore: settings)
        #expect(!report.contains("Optional("))
        #expect(report.contains("Last successful update: never"))
        #expect(report.contains("Rate limit tier: -"))
    }

    @Test("report never contains the OAuth bearer token")
    func neverLeaksToken() async {
        let (store, settings) = await makeStoresWithError(
            apiError: .rateLimited(retryAfter: 0, retryAfterRaw: "0", endpoint: "/api/oauth/usage")
        )
        let report = DiagnosticReporter.makeReport(usageStore: store, settingsStore: settings)
        #expect(!report.contains("fake-token"))
        #expect(!report.contains("Bearer "))
    }

    @Test("report never contains proxy host or port")
    func neverLeaksProxyCreds() {
        let (store, settings) = makeStores(proxyEnabled: true)
        let report = DiagnosticReporter.makeReport(usageStore: store, settingsStore: settings)
        #expect(!report.contains("10.0.0.5"))
        #expect(!report.contains("1080"))
        #expect(report.contains("Proxy configured: yes"))
    }
}
