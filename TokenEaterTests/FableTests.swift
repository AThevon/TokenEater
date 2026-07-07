import Testing
import Foundation

struct FableTests {
    @Test("seven_day_fable decodes into sevenDayFable bucket")
    func decodesFableBucket() throws {
        let json = """
        {
          "five_hour": { "utilization": 11, "resets_at": null },
          "seven_day": { "utilization": 14, "resets_at": null },
          "seven_day_fable": { "utilization": 23, "resets_at": "2026-07-08T00:00:00Z" }
        }
        """.data(using: .utf8)!
        let usage = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(usage.sevenDayFable != nil)
        #expect(Int(usage.sevenDayFable?.utilization ?? 0) == 23)
        #expect(usage.sevenDayFable?.resetsAtDate != nil)
    }

    @Test("absent seven_day_fable decodes to nil (tolerant)")
    func absentFableIsNil() throws {
        let json = #"{ "five_hour": { "utilization": 0, "resets_at": null } }"#.data(using: .utf8)!
        let usage = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(usage.sevenDayFable == nil)
    }

    // MARK: - limits[] fallback (migrated accounts)

    /// The live `/api/oauth/usage` shape on migrated accounts: no
    /// `seven_day_fable` key; Fable arrives inside `limits` as a
    /// `weekly_scoped` entry tagged with `scope.model.display_name`.
    @Test("Fable resolves from the limits[] weekly_scoped entry when the top-level key is absent")
    func fableFromLimitsArray() throws {
        let json = """
        {
          "five_hour": { "utilization": 19, "resets_at": null },
          "seven_day": { "utilization": 15, "resets_at": null },
          "seven_day_fable": null,
          "limits": [
            { "kind": "session", "group": "session", "percent": 19, "resets_at": null,
              "scope": null, "is_active": false },
            { "kind": "weekly_all", "group": "weekly", "percent": 15, "resets_at": null,
              "scope": null, "is_active": false },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 23,
              "resets_at": "2026-07-08T07:00:00.052047+00:00",
              "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
              "is_active": true }
          ]
        }
        """.data(using: .utf8)!
        let usage = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(usage.sevenDayFable != nil)
        #expect(Int(usage.sevenDayFable?.utilization ?? 0) == 23)
        #expect(usage.sevenDayFable?.resetsAtDate != nil)
    }

    @Test("dedicated seven_day_fable bucket wins over the limits[] entry")
    func topLevelFableWinsOverLimits() throws {
        let json = """
        {
          "seven_day_fable": { "utilization": 42, "resets_at": null },
          "limits": [
            { "kind": "weekly_scoped", "group": "weekly", "percent": 23, "resets_at": null,
              "scope": { "model": { "display_name": "Fable" } }, "is_active": true }
          ]
        }
        """.data(using: .utf8)!
        let usage = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(Int(usage.sevenDayFable?.utilization ?? 0) == 42)
    }

    @Test("limits[] without a Fable entry leaves sevenDayFable nil")
    func limitsWithoutFableIsNil() throws {
        let json = """
        {
          "limits": [
            { "kind": "weekly_scoped", "group": "weekly", "percent": 30, "resets_at": null,
              "scope": { "model": { "display_name": "Sonnet" } }, "is_active": true }
          ]
        }
        """.data(using: .utf8)!
        let usage = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(usage.sevenDayFable == nil)
        #expect(Int(usage.sevenDaySonnet?.utilization ?? 0) == 30)
    }

    @Test("MetricID.fable exposes label and short label")
    func fableMetricLabels() {
        #expect(MetricID.fable.rawValue == "fable")
        #expect(MetricID.fable.shortLabel == "F")
        #expect(!MetricID.fable.label.isEmpty)
    }
}
