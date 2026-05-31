import Testing
import Foundation

@Suite("MetricsGridLayout.rows")
struct MetricsGridLayoutTests {

    private func shape(_ n: Int) -> [Int] {
        MetricsGridLayout.rows(Array(0..<n)).map(\.count)
    }

    /// Rows must fill the full width: no row shape that would leave a trailing
    /// empty cell in a 3-wide layout, for any tile count the dashboard produces.
    @Test("rows fill the full width with no trailing gap")
    func fillsRowsWithoutTrailingGap() {
        #expect(shape(0) == [])
        #expect(shape(1) == [1])
        #expect(shape(2) == [2])
        #expect(shape(3) == [3])
        #expect(shape(4) == [2, 2])   // 2x2, not 3 + 1 lone tile
        #expect(shape(5) == [3, 2])
        #expect(shape(6) == [3, 3])
    }

    @Test("preserves item order across rows")
    func preservesOrder() {
        let rows = MetricsGridLayout.rows([10, 20, 30, 40, 50])
        #expect(rows == [[10, 20, 30], [40, 50]])
    }
}
