import Testing
import Foundation

@Suite("HistoryStore derivations")
struct HistoryStoreTests {

    private static func bucket(
        _ y: Int, _ m: Int, _ d: Int,
        byModel: [ModelKind: Int],
        byProject: [String: Int] = [:],
        sessions: Int = 1,
        input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheCreate: Int = 0
    ) -> HistoryBucket {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
        return HistoryBucket(
            date: date,
            tokensByModel: byModel,
            tokensByProject: byProject,
            sessionsCount: sessions,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheCreateTokens: cacheCreate
        )
    }

    @Test("totalsByKind sums tokens per ModelKind across buckets")
    func totalsByKindSums() {
        let buckets = [
            Self.bucket(2026, 5, 25, byModel: [.opus48: 100, .sonnet: 50]),
            Self.bucket(2026, 5, 26, byModel: [.opus48: 30, .haiku: 10])
        ]
        let totals = HistoryStore.totalsByKind(in: buckets)
        #expect(totals[.opus48] == 130)
        #expect(totals[.sonnet] == 50)
        #expect(totals[.haiku] == 10)
        #expect(totals[.fable] == nil)
    }

    @Test("totalsByKind is empty for empty input")
    func totalsByKindEmpty() {
        #expect(HistoryStore.totalsByKind(in: []).isEmpty)
    }

    @Test("bucketsForChart with .all returns buckets unchanged")
    func bucketsForChartAll() {
        let buckets = [Self.bucket(2026, 5, 25, byModel: [.opus48: 100, .sonnet: 50])]
        let out = HistoryStore.bucketsForChart(buckets, filter: .all)
        #expect(out.first?.tokensByModel == [.opus48: 100, .sonnet: 50])
    }

    @Test("bucketsForChart with a family keeps only that family's kinds")
    func bucketsForChartFamily() {
        let buckets = [
            Self.bucket(2026, 5, 25, byModel: [.opus48: 100, .opus46: 20, .sonnet: 50, .haiku: 5])
        ]
        let out = HistoryStore.bucketsForChart(buckets, filter: .family(.opus))
        // Opus 4.8 and 4.6 both fold into .opus and survive; sonnet/haiku drop.
        #expect(out.first?.tokensByModel == [.opus48: 100, .opus46: 20])
    }

    @Test("bucketsForChart leaves non-model fields untouched")
    func bucketsForChartPreservesOtherFields() {
        let buckets = [
            Self.bucket(2026, 5, 25, byModel: [.opus48: 100, .sonnet: 50],
                        byProject: ["/p": 150], sessions: 3, input: 10, output: 20)
        ]
        let out = HistoryStore.bucketsForChart(buckets, filter: .family(.opus))
        #expect(out.first?.tokensByProject == ["/p": 150])
        #expect(out.first?.sessionsCount == 3)
        #expect(out.first?.inputTokens == 10)
        #expect(out.first?.outputTokens == 20)
    }
}
