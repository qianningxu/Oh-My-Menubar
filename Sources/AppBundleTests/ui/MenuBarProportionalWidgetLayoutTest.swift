import AppKit
@testable import AppBundle
import XCTest

final class MenuBarProportionalWidgetLayoutTest: XCTestCase {
    func testWidgetsKeepContentWidthsWhenTheyFit() {
        XCTAssertEqual(
            menuBarProportionalWidgetWidths([80, 120, 60], availableWidth: 500),
            [80, 120, 60]
        )
    }

    func testWidgetsShrinkProportionallyWhenContentOverflows() {
        let widths = menuBarProportionalWidgetWidths([100, 200], availableWidth: 150)

        XCTAssertEqual(widths[0], 50, accuracy: 0.001)
        XCTAssertEqual(widths[1], 100, accuracy: 0.001)
    }
}
