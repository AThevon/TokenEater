import Foundation

extension UsageBucket {
    /// Test-only initializer via JSON decoding (properties are `let`)
    static func fixture(utilization: Double = 0, resetsAt: String? = nil) -> UsageBucket {
        let json: [String: Any] = {
            var d: [String: Any] = ["utilization": utilization]
            if let r = resetsAt { d["resets_at"] = r }
            return d
        }()
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(UsageBucket.self, from: data)
    }
}

extension UsageResponse {
    static func fixture(
        fiveHourUtil: Double = 42,
        sevenDayUtil: Double = 65,
        sonnetUtil: Double = 30,
        fiveHourResetsAt: String? = nil,
        sevenDayResetsAt: String? = nil,
        sonnetResetsAt: String? = nil,
        extraUsage: ExtraUsage? = nil
    ) -> UsageResponse {
        UsageResponse(
            fiveHour: .fixture(utilization: fiveHourUtil, resetsAt: fiveHourResetsAt),
            sevenDay: .fixture(utilization: sevenDayUtil, resetsAt: sevenDayResetsAt),
            sevenDaySonnet: .fixture(utilization: sonnetUtil, resetsAt: sonnetResetsAt),
            extraUsage: extraUsage
        )
    }
}

extension ExtraUsage {
    /// Test-only convenience builder for the paid Extra Credits pool.
    static func fixture(
        isEnabled: Bool = true,
        monthlyLimit: Double? = 40000,
        usedCredits: Double? = 27000,
        utilization: Double? = 67.5,
        currency: String? = "USD",
        disabledReason: String? = nil
    ) -> ExtraUsage {
        ExtraUsage(
            isEnabled: isEnabled,
            monthlyLimit: monthlyLimit,
            usedCredits: usedCredits,
            utilization: utilization,
            currency: currency,
            disabledReason: disabledReason
        )
    }
}
