import Testing
import Foundation

@Suite("StatusService mapping")
struct StatusServiceMappingTests {

    private func decode(_ json: String) throws -> StatuspageSummary {
        try JSONDecoder().decode(StatuspageSummary.self, from: Data(json.utf8))
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("all operational -> healthy, no affected components")
    func healthy() throws {
        let summary = try decode("""
        {
          "status": { "indicator": "none", "description": "All Systems Operational" },
          "components": [
            { "id": "a", "name": "Claude Code", "status": "operational" },
            { "id": "b", "name": "Claude API (api.anthropic.com)", "status": "operational" },
            { "id": "c", "name": "claude.ai", "status": "operational" }
          ],
          "incidents": []
        }
        """)
        let status = VendorStatus.from(summary: summary, vendor: .claude, now: now)
        #expect(status.health == .healthy)
        #expect(status.affectedComponents.isEmpty)
        #expect(status.isMaintenanceOnly == false)
    }

    @Test("relevant component degraded -> degraded")
    func degraded() throws {
        let summary = try decode("""
        {
          "status": { "indicator": "minor", "description": "Partial degradation" },
          "components": [
            { "id": "a", "name": "Claude Code", "status": "degraded_performance" },
            { "id": "b", "name": "Claude API (api.anthropic.com)", "status": "operational" }
          ],
          "incidents": []
        }
        """)
        let status = VendorStatus.from(summary: summary, vendor: .claude, now: now)
        #expect(status.health == .degraded)
        #expect(status.affectedComponents == ["Claude Code"])
    }

    @Test("relevant component major_outage -> down, carries unresolved incident")
    func down() throws {
        let summary = try decode("""
        {
          "status": { "indicator": "critical", "description": "Major outage" },
          "components": [
            { "id": "b", "name": "Claude API (api.anthropic.com)", "status": "major_outage" }
          ],
          "incidents": [
            { "id": "i1", "name": "API errors", "status": "investigating", "impact": "critical", "shortlink": "http://x", "updated_at": "2026-06-24T00:00:00Z" },
            { "id": "i0", "name": "Old", "status": "resolved", "impact": "minor", "shortlink": null, "updated_at": null }
          ]
        }
        """)
        let status = VendorStatus.from(summary: summary, vendor: .claude, now: now)
        #expect(status.health == .down)
        #expect(status.activeIncidents.count == 1)
        #expect(status.activeIncidents.first?.name == "API errors")
    }

    @Test("only an UNRELATED component degraded stays healthy")
    func unrelatedIgnored() throws {
        let summary = try decode("""
        {
          "status": { "indicator": "minor", "description": "Web app issues" },
          "components": [
            { "id": "c", "name": "claude.ai", "status": "major_outage" },
            { "id": "a", "name": "Claude Code", "status": "operational" }
          ],
          "incidents": []
        }
        """)
        let status = VendorStatus.from(summary: summary, vendor: .claude, now: now)
        #expect(status.health == .healthy)
    }

    @Test("maintenance-only relevant component is degraded + flagged maintenance")
    func maintenanceOnly() throws {
        let summary = try decode("""
        {
          "status": { "indicator": "maintenance", "description": "Scheduled maintenance" },
          "components": [
            { "id": "a", "name": "Claude Code", "status": "under_maintenance" }
          ],
          "incidents": []
        }
        """)
        let status = VendorStatus.from(summary: summary, vendor: .claude, now: now)
        #expect(status.health == .degraded)
        #expect(status.isMaintenanceOnly == true)
    }
}
