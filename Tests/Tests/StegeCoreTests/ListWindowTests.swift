import Testing

@testable import StegeCore

struct ListWindowTests {
    /// The case that started this: a MacBook Air offers fourteen resolutions
    /// and uses the eighth, so the six largest do not include it.
    @Test func theCurrentItemIsAlwaysInTheWindow() {
        let range = ListWindow.range(count: 6, around: 7, total: 14)
        #expect(range.contains(7))
        #expect(range.count == 6)
    }

    @Test func theWindowIsCentredOnTheCurrentItem() {
        #expect(ListWindow.range(count: 6, around: 7, total: 14) == 5..<11)
    }

    @Test func aWindowAtTheStartSlidesInside() {
        #expect(ListWindow.range(count: 6, around: 0, total: 14) == 0..<6)
        #expect(ListWindow.range(count: 6, around: 1, total: 14) == 0..<6)
    }

    @Test func aWindowAtTheEndSlidesInside() {
        #expect(ListWindow.range(count: 6, around: 13, total: 14) == 8..<14)
        #expect(ListWindow.range(count: 6, around: 12, total: 14) == 8..<14)
    }

    @Test func aShortListIsReturnedWhole() {
        #expect(ListWindow.range(count: 6, around: 2, total: 4) == 0..<4)
        #expect(ListWindow.range(count: 6, around: nil, total: 6) == 0..<6)
    }

    @Test func withNothingToCentreOnTheWindowStartsAtTheTop() {
        #expect(ListWindow.range(count: 6, around: nil, total: 14) == 0..<6)
    }

    @Test func anIndexOutsideTheListIsIgnored() {
        #expect(ListWindow.range(count: 6, around: 99, total: 14) == 0..<6)
        #expect(ListWindow.range(count: 6, around: -1, total: 14) == 0..<6)
    }

    @Test func anEmptyListIsNoTrouble() {
        #expect(ListWindow.range(count: 6, around: nil, total: 0).isEmpty)
        #expect(ListWindow.range(count: 0, around: 0, total: 10).isEmpty)
    }

    /// Every window is exactly `count` long whatever it is centred on, which is
    /// the property the resolution list depends on.
    @Test func everyWindowIsTheRequestedLength() {
        for index in 0..<14 {
            #expect(ListWindow.range(count: 6, around: index, total: 14).count == 6)
        }
    }
}
