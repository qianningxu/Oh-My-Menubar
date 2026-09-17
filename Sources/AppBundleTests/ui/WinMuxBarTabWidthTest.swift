@testable import AppBundle
import XCTest

final class WinMuxBarTabWidthTest: XCTestCase {
    func testSparseTabsStayCappedAndCrowdedTabsShrink() {
        XCTAssertEqual(winMuxBarTabWidth(availableWidth: 1000, count: 1, spacing: 4, maximumWidth: 240), 240)
        XCTAssertEqual(winMuxBarTabWidth(availableWidth: 1000, count: 2, spacing: 4, maximumWidth: 240), 240)
        XCTAssertEqual(winMuxBarTabWidth(availableWidth: 360, count: 2, spacing: 4, maximumWidth: 240), 178)
        XCTAssertEqual(winMuxBarTabWidth(availableWidth: 1000, count: 10, spacing: 4, maximumWidth: 240), 96.4)
    }

    func testEmptyAndNarrowLayoutsNeverProduceNegativeWidths() {
        XCTAssertEqual(winMuxBarTabWidth(availableWidth: 1000, count: 0, spacing: 4, maximumWidth: 240), 0)
        XCTAssertEqual(winMuxBarTabWidth(availableWidth: 0, count: 2, spacing: 4, maximumWidth: 240), 0)
        XCTAssertEqual(winMuxBarTabWidth(availableWidth: 2, count: 3, spacing: 4, maximumWidth: 240), 0)
    }
}
