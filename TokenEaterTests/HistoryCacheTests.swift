import Testing
import Foundation

@Suite("HistoryCache versioning")
struct HistoryCacheTests {

    /// Every schema bump (#199, #259/#261) relies on version-mismatched caches
    /// being rejected so already-parsed history is re-scanned and
    /// reclassified; the loader's discard path was previously untested.
    @Test func outdatedCacheIsRejected() throws {
        let v2JSON = Data(#"{"version":2,"entries":{}}"#.utf8)
        let decoded = try JSONDecoder().decode(HistoryCache.self, from: v2JSON)
        #expect(!decoded.isCurrentVersion)
    }

    @Test func emptyCacheIsCurrent() {
        #expect(HistoryCache.empty.isCurrentVersion)
        #expect(HistoryCache.currentVersion == 3)
    }
}
