import Foundation

/// A monitored service provider
enum Vendor: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        }
    }

    /// Atlassian Statuspage v2 API base. We hardcode `status.claude.com`
    /// because `status.anthropic.com` 302-redirects here.
    var statusAPIBaseURL: URL {
        switch self {
        case .claude: return URL(string: "https://status.claude.com/api/v2")!
        }
    }

    var statusPageURL: URL {
        switch self {
        case .claude: return URL(string: "https://status.claude.com")!
        }
    }

    /// Component names (matched case-insensitively, substring) that drive this
    /// vendor's health. Unrelated components (web app, console) are ignored.
    var relevantComponentMatches: [String] {
        switch self {
        case .claude: return ["Claude Code", "api.anthropic.com"]
        }
    }
}

/// Three-state severity, ordered so `.max()` yields the worst component.
enum VendorHealth: Int, Comparable, Codable, Sendable {
    case healthy = 0
    case degraded = 1
    case down = 2

    static func < (lhs: VendorHealth, rhs: VendorHealth) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Map an Atlassian Statuspage component status string. Unknown values
    /// fail open to `.healthy` — we never invent an outage from a string we
    /// don't recognise.
    static func from(componentStatus status: String) -> VendorHealth {
        switch status {
        case "operational":         return .healthy
        case "major_outage":        return .down
        case "degraded_performance",
             "partial_outage",
             "under_maintenance":    return .degraded
        default:                    return .healthy
        }
    }
}

// MARK: - Atlassian Statuspage v2 DTOs

struct StatuspageStatus: Codable, Equatable, Sendable {
    let indicator: String
    let description: String
}

struct StatuspageComponent: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let status: String
}

struct StatuspageIncident: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let status: String
    let impact: String
    let shortlink: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status, impact, shortlink
        case updatedAt = "updated_at"
    }
}

/// `summary.json` top-level. Extra keys (`page`, `scheduled_maintenances`) are
/// ignored by the decoder.
struct StatuspageSummary: Codable, Equatable, Sendable {
    let status: StatuspageStatus
    let components: [StatuspageComponent]
    let incidents: [StatuspageIncident]
}

// MARK: - App-facing status

struct VendorStatus: Equatable, Sendable {
    let vendor: Vendor
    let health: VendorHealth
    let affectedComponents: [String]
    let activeIncidents: [StatuspageIncident]
    let lastChecked: Date
    /// Set when the most recent fetch failed and we're showing cached state.
    var isStale: Bool
    /// True when the only non-operational relevant components are
    /// `under_maintenance` (planned work) — shown in the UI but never notified.
    let isMaintenanceOnly: Bool

    var statusPageURL: URL { vendor.statusPageURL }

    /// Pure mapping from a Statuspage summary to app-facing status, scoped to
    /// the vendor's relevant components.
    static func from(summary: StatuspageSummary, vendor: Vendor, now: Date) -> VendorStatus {
        let needles = vendor.relevantComponentMatches.map { $0.lowercased() }
        let relevant = summary.components.filter { component in
            needles.contains { component.name.lowercased().contains($0) }
        }
        let health = relevant.map { VendorHealth.from(componentStatus: $0.status) }.max() ?? .healthy
        let nonOperational = relevant.filter { $0.status != "operational" }
        let affected = nonOperational.map(\.name)
        let isMaintenanceOnly = !nonOperational.isEmpty
            && nonOperational.allSatisfy { $0.status == "under_maintenance" }
        let active = summary.incidents.filter { $0.status != "resolved" && $0.status != "postmortem" }
        return VendorStatus(
            vendor: vendor,
            health: health,
            affectedComponents: affected,
            activeIncidents: active,
            lastChecked: now,
            isStale: false,
            isMaintenanceOnly: isMaintenanceOnly
        )
    }
}
