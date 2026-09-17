@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class MinimumWindowSizeTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testMinimumProbeRejectsAnUnchangedWindowSize() {
        XCTAssertNil(confirmedMinimumSizeAfterNativeProbe(
            original: CGSize(width: 1200, height: 900),
            observed: CGSize(width: 1200, height: 900)))
        XCTAssertEqual(confirmedMinimumSizeAfterNativeProbe(
            original: CGSize(width: 1200, height: 900),
            observed: CGSize(width: 900, height: 900)),
        CGSize(width: 900, height: 0))
        XCTAssertEqual(confirmedMinimumSizeAfterNativeProbe(
            original: CGSize(width: 1200, height: 900),
            observed: CGSize(width: 900, height: 600)),
        CGSize(width: 900, height: 600))
    }

    func testUnequalMinimumsReplaceHalfSplitWithoutOverflow() {
        XCTAssertEqual(constrainedTileWeights(proposed: [500, 500], minimums: [650, 100], available: 1000), [650, 350])
        XCTAssertEqual(constrainedTileWeights(proposed: [100, 700, 200], minimums: [300, 100, 250], available: 1000), [300, 450, 250])
    }

    func testUnconstrainedAndImpossibleAllocations() {
        XCTAssertEqual(constrainedTileWeights(proposed: [600, 400], minimums: [100, 100], available: 1000), [600, 400])
        XCTAssertEqual(constrainedTileWeights(proposed: [50, 50], minimums: [200, 300], available: 100), [200, 300])
        XCTAssertEqual(constrainedTileWeights(proposed: [], minimums: [], available: 100), [])
    }

    func testStackIncludesInactiveWindowMinimumAndShell() {
        let workspace = Workspace.get(byName: name)
        let stack = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .tabGroup, index: INDEX_BIND_LAST)
        let small = TestWindow.new(id: 1, parent: stack)
        let large = TestWindow.new(id: 2, parent: stack)
        small.minimumSize = CGSize(width: 100, height: 100)
        large.minimumSize = CGSize(width: 650, height: 400)
        _ = small.focusWindow()
        let gaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
        let size = stack.minimumLayoutSize(gaps: gaps)
        XCTAssertGreaterThanOrEqual(size.width, 650)
        XCTAssertGreaterThanOrEqual(size.height, 400)
    }

    func testResizeStopsAtSiblingMinimum() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let first = TestWindow.new(id: 1, parent: root, adaptiveWeight: 500)
        let second = TestWindow.new(id: 2, parent: root, adaptiveWeight: 500)
        first.minimumSize = CGSize(width: 100, height: 100)
        second.minimumSize = CGSize(width: 400, height: 100)
        _ = workspace.focusWorkspace()
        _ = workspace.workspaceMonitor.setActiveWorkspace(workspace)
        try await workspace.layoutWorkspace()
        let base = try XCTUnwrap(first.lastAppliedLayoutPhysicalRect)
        let proposal = try XCTUnwrap(resizeProposal(first, rect: Rect(topLeftX: base.minX, topLeftY: base.minY, width: base.width + 1000, height: base.height)))
        XCTAssertGreaterThanOrEqual(proposal.weights.weight(for: second, orientation: .h), second.resizeMinimumWeight)
        XCTAssertLessThan(proposal.rect.width, base.width + 1000)
    }

    func testStackResizeUsesOneConstrainedDividerForBothSides() async throws {
        config.windowTabs.enabled = true
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.changeOrientation(.h)
        root.layout = .tiles

        let leftStack = TilingContainer(
            parent: root, adaptiveWeight: 500, .h, .tabGroup, index: INDEX_BIND_LAST)
        let left = TestWindow.new(id: 1, parent: leftStack)
        _ = TestWindow.new(id: 2, parent: leftStack)
        let rightStack = TilingContainer(
            parent: root, adaptiveWeight: 500, .h, .tabGroup, index: INDEX_BIND_LAST)
        let right = TestWindow.new(id: 3, parent: rightStack)
        let constrainedInactiveTab = TestWindow.new(id: 4, parent: rightStack)
        left.minimumSize = CGSize(width: 100, height: 100)
        right.minimumSize = CGSize(width: 100, height: 100)
        constrainedInactiveTab.minimumSize = CGSize(width: 650, height: 100)
        _ = left.focusWindow()
        _ = workspace.workspaceMonitor.setActiveWorkspace(workspace)
        try await workspace.layoutWorkspace()

        let base = try XCTUnwrap(left.lastAppliedLayoutPhysicalRect)
        let proposal = try XCTUnwrap(resizeProposal(
            left,
            rect: Rect(
                topLeftX: base.minX,
                topLeftY: base.minY,
                width: base.width + 1000,
                height: base.height)))
        let items = windowResizePreviewItems(
            in: workspace,
            weightMap: proposal.weights,
            excludingActiveWindowId: left.windowId)
        let rightFrame = try XCTUnwrap(items.first(where: { $0.isTabGroup })?.frame.monitorFrameNormalized())
        let gap = ResolvedGaps(
            gaps: config.gaps,
            monitor: workspace.workspaceMonitor,
            canvasGap: config.workspaceSidebar.enabled ? Int(WinMuxSpacing.comfortable) : nil
        ).inner.horizontal.toDouble()
        let leftStackFrame = windowTabGroupFrameRect(forActiveWindowContentRect: proposal.rect)

        XCTAssertGreaterThanOrEqual(rightFrame.width, rightStack.minimumLayoutSize(
            gaps: ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)).width)
        XCTAssertEqual(rightFrame.minX - leftStackFrame.maxX, gap, accuracy: 0.5)
    }

    func testFullInventoryCollectsWindowsWhoseAppWasRemoved() {
        XCTAssertTrue(shouldReconcileWindowInventory(isFullInventory: true, appWasRefreshed: false))
        XCTAssertFalse(shouldReconcileWindowInventory(isFullInventory: false, appWasRefreshed: false))
        XCTAssertTrue(shouldReconcileWindowInventory(isFullInventory: false, appWasRefreshed: true))
    }
}
