@testable import AppBundle
import XCTest

final class WorkspaceSidebarHoverBehaviorTest: XCTestCase {
    @MainActor
    func testCursorProximityDoesNotChangeSidebarExpansionState() {
        setUpWorkspacesForTests()
        let panel = WorkspaceSidebarPanel.shared
        let collapsedWidth = CGFloat(config.workspaceSidebar.collapsedWidth)
        let expandedWidth = CGFloat(config.workspaceSidebar.width)

        panel.viewModel.isWorkspaceSidebarExpanded = false
        panel.viewModel.workspaceSidebarVisibleWidth = collapsedWidth
        panel.setHovering(true)

        XCTAssertFalse(panel.viewModel.isWorkspaceSidebarExpanded)
        XCTAssertEqual(panel.viewModel.workspaceSidebarVisibleWidth, collapsedWidth)

        panel.viewModel.isWorkspaceSidebarExpanded = true
        panel.viewModel.workspaceSidebarVisibleWidth = expandedWidth
        panel.setHovering(false)

        XCTAssertTrue(panel.viewModel.isWorkspaceSidebarExpanded)
        XCTAssertEqual(panel.viewModel.workspaceSidebarVisibleWidth, expandedWidth)
    }
}
