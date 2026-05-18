import Foundation

/// Builds a Markdown diagnostic report from the current TokenEater state.
/// Used by the "Copy diagnostic" button in `PopoverErrorBanner`. The output
/// is meant to be pasted into a GitHub issue, so it is English-only and
/// never contains the OAuth bearer token, proxy credentials, organization
/// name, or any other PII.
enum DiagnosticReporter {

    /// Public entry point.
    @MainActor
    static func makeReport(usageStore: UsageStore, settingsStore: SettingsStore) -> String {
        let app = appSection()
        let system = systemSection()
        let state = stateSection(usageStore: usageStore, settingsStore: settingsStore)
        let apiError = apiErrorSection(usageStore.lastAPIError)

        return """
        ## TokenEater diagnostic

        \(app)

        \(system)

        \(state)

        \(apiError)
        """
    }

    // MARK: - Sections

    private static func appSection() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        let bundleID = Bundle.main.bundleIdentifier ?? "-"
        let arch: String = {
            #if arch(arm64)
            return "arm64"
            #elseif arch(x86_64)
            return "x86_64"
            #else
            return "unknown"
            #endif
        }()
        return """
        **App**
        - Version: \(version) (build \(build))
        - Bundle: \(bundleID)
        - Architecture: \(arch)
        """
    }

    private static func systemSection() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return """
        **System**
        - macOS: \(os)
        """
    }

    @MainActor
    private static func stateSection(usageStore: UsageStore, settingsStore: SettingsStore) -> String {
        let errorState = errorStateName(usageStore.errorState)
        let speed = speedName(usageStore.currentSpeed)
        let interval = Int(usageStore.effectiveInterval)
        let lastUpdate = formatDate(usageStore.lastUpdate, relative: true) ?? "never"
        let retryAfter = formatDate(usageStore.retryAfterDate, relative: true) ?? "-"
        let plan = String(describing: usageStore.planType)
        let tier = usageStore.rateLimitTier ?? "-"
        let tokenPresent = usageStore.hasConfig ? "yes" : "no"
        let proxyConfigured: String
        if let proxy = usageStore.proxyConfig, proxy.isValidForUse {
            proxyConfigured = "yes"
        } else {
            proxyConfigured = "no"
        }

        return """
        **State**
        - Error state: \(errorState)
        - Refresh speed: \(speed)
        - Effective interval: \(interval)s
        - Last successful update: \(lastUpdate)
        - Retry-after deadline: \(retryAfter)
        - Plan: \(plan)
        - Rate limit tier: \(tier)
        - Token present: \(tokenPresent)
        - Proxy configured: \(proxyConfigured)
        """
    }

    private static func apiErrorSection(_ error: LastAPIError?) -> String {
        guard let error else {
            return """
            **Last API error**
            - None captured
            """
        }
        let status = error.httpStatusCode.map(String.init) ?? "-"
        let retryHeader = error.retryAfterHeader.map { "\"\($0)\"" } ?? "-"
        let timestamp = formatDate(error.timestamp, relative: false) ?? "-"
        let underlying = error.underlyingError ?? "-"
        return """
        **Last API error**
        - Endpoint: \(error.endpoint)
        - HTTP status: \(status)
        - Retry-After header (raw): \(retryHeader)
        - Timestamp: \(timestamp)
        - Underlying error: \(underlying)
        """
    }

    // MARK: - Helpers

    private static func errorStateName(_ state: AppErrorState) -> String {
        switch state {
        case .none: return "none"
        case .tokenUnavailable: return "tokenUnavailable"
        case .rateLimited: return "rateLimited"
        case .networkError: return "networkError"
        }
    }

    private static func speedName(_ speed: RefreshSpeed) -> String {
        switch speed {
        case .fast: return "fast"
        case .normal: return "normal"
        case .slow: return "slow"
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    private static func formatDate(_ date: Date?, relative: Bool) -> String? {
        guard let date else { return nil }
        let iso = isoFormatter.string(from: date)
        if relative {
            let rel = relativeFormatter.localizedString(for: date, relativeTo: Date())
            return "\(iso) (\(rel))"
        }
        return iso
    }
}
