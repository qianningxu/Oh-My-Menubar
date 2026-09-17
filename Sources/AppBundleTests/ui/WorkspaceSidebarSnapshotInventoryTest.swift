@testable import AppBundle
import XCTest

@MainActor
final class WorkspaceSidebarSnapshotInventoryTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testWindowInventoryIsRebuiltAfterClosingAWindow() async {
        let workspace = focus.workspace
        let first = TestWindow.new(id: 9101, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 9102, parent: workspace.rootTilingContainer)
        _ = first.focusWindow()
        let before = await buildWorkspaceSidebarWorkspaceViewModels(
            from: [workspace], currentFocus: focus, workspaceLabels: [:], availableMonitors: [mainMonitor]
        )
        XCTAssertEqual(before.first?.tabSummary.windowCount, 2)
        second.unbindFromParent()
        let after = await buildWorkspaceSidebarWorkspaceViewModels(
            from: [workspace], currentFocus: focus, workspaceLabels: [:], availableMonitors: [mainMonitor]
        )
        XCTAssertEqual(after.first?.tabSummary.windowCount, 1)
        XCTAssertFalse(after.first?.tabSummary.isEmpty ?? true)
    }

    func testLabelsDoNotChangeWindowCounts() async {
        let workspace = focus.workspace
        let window = TestWindow.new(id: 9103, parent: workspace.rootTilingContainer)
        _ = window.focusWindow()
        let models = await buildWorkspaceSidebarWorkspaceViewModels(
            from: [workspace], currentFocus: focus,
            workspaceLabels: [workspace.name: "Reference"], availableMonitors: [mainMonitor]
        )
        XCTAssertEqual(models.first?.displayName, "Reference")
        XCTAssertEqual(models.first?.tabSummary.windowCount, 1)
    }
    func testBarWidthNormalizationDoesNotScheduleWindowLayout() async throws {
        var refreshCount = 0
        setScheduledRefreshOverrideForTests { _, _ in refreshCount += 1 }
        defer { setScheduledRefreshOverrideForTests(nil) }
        let panel = WorkspaceSidebarPanel.shared
        panel.animateVisibleSidebarWidth(panel.frame.width, animation: nil)
        try await waitForScheduledRefreshForTests()
        XCTAssertEqual(refreshCount, 0)
    }
}
