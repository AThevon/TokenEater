import Testing
import Foundation

/// History reads from `CombinedSessionHistoryService`, so its buckets hold both
/// providers' models mixed together. The mode selector in the window bar drives
/// the whole app, and these pin what it does here.
@Suite("History provider gate")
struct HistoryProviderGateTests {

    private static func bucket(
        _ day: Int,
        byModel: [ModelKind: Int],
        byProject: [String: Int] = [:],
        sessions: Int = 1
    ) -> HistoryBucket {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return HistoryBucket(
            date: cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12))!,
            tokensByModel: byModel,
            tokensByProject: byProject,
            sessionsCount: sessions,
            inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheCreateTokens: 0
        )
    }

    private static let codexKind = ModelKind(rawValue: "codex:gpt-5-codex")

    private static var mixed: [HistoryBucket] {
        [
            bucket(1, byModel: [.opus48: 100, codexKind: 40]),
            bucket(2, byModel: [.sonnet: 60]),
            bucket(3, byModel: [codexKind: 25]),
        ]
    }

    @Test("All mode changes nothing")
    func allPassesThrough() {
        let gated = HistoryStore.gate(Self.mixed, to: .all)
        #expect(gated.count == 3)
        #expect(gated.reduce(0) { $0 + $1.totalActive } == 225)
    }

    @Test("Claude mode drops Codex models and the buckets that held only those")
    func claudeMode() {
        let gated = HistoryStore.gate(Self.mixed, to: .claude)
        // Day 3 was Codex-only, so it goes entirely: an empty bucket would
        // draw a zero-height bar that reads as "I worked and logged nothing".
        #expect(gated.count == 2)
        #expect(gated.allSatisfy { $0.tokensByModel.keys.allSatisfy { !$0.isCodex } })
        #expect(gated.reduce(0) { $0 + $1.totalActive } == 160)
    }

    @Test("Codex mode is the exact mirror")
    func codexMode() {
        let gated = HistoryStore.gate(Self.mixed, to: .codex)
        #expect(gated.count == 2)
        #expect(gated.allSatisfy { $0.tokensByModel.keys.allSatisfy(\.isCodex) })
        #expect(gated.reduce(0) { $0 + $1.totalActive } == 65)
    }

    @Test("The two provider modes partition All, losing nothing and double counting nothing")
    func modesPartitionTheTotal() {
        let all = HistoryStore.gate(Self.mixed, to: .all).reduce(0) { $0 + $1.totalActive }
        let claude = HistoryStore.gate(Self.mixed, to: .claude).reduce(0) { $0 + $1.totalActive }
        let codex = HistoryStore.gate(Self.mixed, to: .codex).reduce(0) { $0 + $1.totalActive }
        #expect(claude + codex == all)
    }

    @Test("Per-bucket counters survive untouched, because they cannot be split")
    func unsplittableFieldsAreLeftAlone() {
        let source = [Self.bucket(1, byModel: [.opus48: 100, Self.codexKind: 40],
                                  byProject: ["/repo": 140], sessions: 3)]
        let gated = HistoryStore.gate(source, to: .claude)
        // Sessions and project totals are recorded per bucket, not per model.
        // Scaling them by the surviving token share would invent numbers, so
        // they pass through and stay honest only in All mode.
        #expect(gated.first?.sessionsCount == 3)
        #expect(gated.first?.tokensByProject["/repo"] == 140)
    }

    @Test("An empty range stays empty rather than turning into phantom buckets")
    func emptyStaysEmpty() {
        #expect(HistoryStore.gate([], to: .codex).isEmpty)
        #expect(HistoryStore.gate([Self.bucket(1, byModel: [:])], to: .all).count == 1)
        #expect(HistoryStore.gate([Self.bucket(1, byModel: [:])], to: .claude).isEmpty)
    }
}
