import AppKit
@testable import AppBundle
import XCTest

final class MenuBarBalancedWidgetLayoutTest: XCTestCase {
    func testPeriodLeadsAndRemainingWidgetsTrail() {
        let placements = menuBarBalancedWidgetPlacements(
            [80, 60, 40],
            availableWidth: 300,
            separation: 12
        )

        XCTAssertEqual(placements, [
            MenuBarWidgetPlacement(x: 0, width: 80),
            MenuBarWidgetPlacement(x: 188, width: 60),
            MenuBarWidgetPlacement(x: 260, width: 40),
        ])
    }

    func testWidgetsShrinkWithoutOverlappingWhenSpaceIsTight() {
        let placements = menuBarBalancedWidgetPlacements(
            [100, 100],
            availableWidth: 150,
            separation: 10
        )

        XCTAssertEqual(placements[0].x, 0)
        XCTAssertEqual(placements[0].width, 70, accuracy: 0.001)
        XCTAssertEqual(placements[1].x, 80, accuracy: 0.001)
        XCTAssertEqual(placements[1].width, 70, accuracy: 0.001)
    }
}
