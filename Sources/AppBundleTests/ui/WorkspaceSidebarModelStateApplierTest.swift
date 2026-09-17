@testable import AppBundle
import XCTest

final class WorkspaceSidebarModelStateApplierTest: XCTestCase {
    func testDataAndFocusedMonitorChangesSyncVisiblePanelModels() {
        XCTAssertEqual(
            workspaceSidebarPanelModelUpdate(
                didGeometryChange: false,
                didMonitorConfigurationChange: false,
                hasVisiblePanels: true,
            ),
            .syncVisibleModels
        )
    }

    func testGeometryChangeRefreshesAllPanels() {
        XCTAssertEqual(
            workspaceSidebarPanelModelUpdate(
                didGeometryChange: true,
                didMonitorConfigurationChange: false,
                hasVisiblePanels: true,
            ),
            .refreshAll
        )
    }

    func testMonitorConfigurationChangeRefreshesAllPanels() {
        XCTAssertEqual(
            workspaceSidebarPanelModelUpdate(
                didGeometryChange: false,
                didMonitorConfigurationChange: true,
                hasVisiblePanels: true,
            ),
            .refreshAll
        )
    }

    func testMissingVisiblePanelsRefreshesLifecycle() {
        XCTAssertEqual(
            workspaceSidebarPanelModelUpdate(
                didGeometryChange: false,
                didMonitorConfigurationChange: false,
                hasVisiblePanels: false,
            ),
            .refreshAll
        )
    }
}
