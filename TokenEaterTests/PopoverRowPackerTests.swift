import Testing
import Foundation

@Suite("PopoverRowPacker")
struct PopoverRowPackerTests {

    private func element(_ kind: PopoverElementKind, _ style: PopoverElementStyle, _ width: PopoverElementWidth) -> PopoverElement {
        PopoverElement(kind: kind, style: style, width: width)
    }

    @Test("empty input yields no rows")
    func emptyInput() {
        #expect(PopoverRowPacker.pack([]).isEmpty)
    }

    @Test("full-width elements each get their own row")
    func fullWidthRows() {
        let rows = PopoverRowPacker.pack([
            element(.session, .gaugeRing, .full),
            element(.sessionPacing, .paceBar, .full),
            element(.timestamp, .utilityRow, .full),
        ])
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.count == 1 })
    }

    @Test("consecutive halves pair up, two per row")
    func halvesPair() {
        let rows = PopoverRowPacker.pack([
            element(.session, .gaugeRing, .half),
            element(.weekly, .gaugeRing, .half),
            element(.sessionPacing, .paceTile, .half),
            element(.weeklyPacing, .paceTile, .half),
        ])
        #expect(rows.count == 2)
        #expect(rows[0].count == 2)
        #expect(rows[1].count == 2)
    }

    @Test("consecutive thirds pack three per row")
    func thirdsPack() {
        let rows = PopoverRowPacker.pack([
            element(.weekly, .chip, .third),
            element(.sonnet, .chip, .third),
            element(.fable, .chip, .third),
            element(.design, .chip, .third),
        ])
        #expect(rows.count == 2)
        #expect(rows[0].count == 3)
        #expect(rows[1].count == 1)
    }

    @Test("width change breaks the row")
    func widthChangeBreaksRow() {
        let rows = PopoverRowPacker.pack([
            element(.session, .gaugeRing, .half),
            element(.weekly, .chip, .third),
            element(.sonnet, .chip, .third),
        ])
        #expect(rows.count == 2)
        #expect(rows[0].count == 1)
        #expect(rows[0][0].kind == .session)
        #expect(rows[1].count == 2)
    }

    @Test("a lone half stays a single-element row")
    func loneHalf() {
        let rows = PopoverRowPacker.pack([
            element(.session, .gaugeRing, .full),
            element(.weekly, .gaugeRing, .half),
        ])
        #expect(rows.count == 2)
        #expect(rows[1].count == 1)
        #expect(rows[1][0].width == .half)
    }

    @Test("order within and across rows follows input order")
    func preservesOrder() {
        let a = element(.session, .chip, .half)
        let b = element(.weekly, .chip, .half)
        let c = element(.timestamp, .utilityRow, .full)
        let rows = PopoverRowPacker.pack([a, b, c])
        #expect(rows[0].map(\.id) == [a.id, b.id])
        #expect(rows[1].map(\.id) == [c.id])
    }

    @Test("illegal width is clamped via effectiveWidth before packing")
    func illegalWidthClamped() {
        // An arc only allows .full; a decoded .third must not create a
        // 3-capacity row.
        let arc = element(.session, .arc, .third)
        let rows = PopoverRowPacker.pack([arc, element(.weekly, .gaugeRing, .third)])
        #expect(rows.count == 2)
        #expect(rows[0][0].effectiveWidth == .full)
    }
}
