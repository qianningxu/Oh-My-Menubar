import AppKit
@testable import AppBundle
import XCTest

final class MenuBarProjectLeadingWidgetLayoutTest: XCTestCase {
    func testPeriodAndProjectsStayTogetherOnLeadingSide() {
        XCTAssertEqual(
            menuBarProjectLeadingWidgetPlacements([80, 60, 40], availableWidth: 300, separation: 12),
            [
                MenuBarWidgetPlacement(x: 0, width: 80),
                MenuBarWidgetPlacement(x: 92, width: 60),
                MenuBarWidgetPlacement(x: 260, width: 40),
            ]
        )
    }

    func testCameraAreaSeparatesAndConstrainsBothGroups() {
        let placements = menuBarProjectLeadingWidgetPlacements(
            [100, 200, 180, 120],
            availableWidth: 800,
            separation: 6,
            projectCount: 3,
            cameraSafeEdges: 350 ... 450
        )

        XCTAssertLessThanOrEqual(placements[1].x + placements[1].width, 350)
        XCTAssertGreaterThanOrEqual(placements[2].x, 450)
    }
}
