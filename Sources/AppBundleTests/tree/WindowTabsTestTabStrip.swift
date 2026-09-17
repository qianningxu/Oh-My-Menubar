@testable import AppBundle
import AppKit
import CoreGraphics
import SwiftUI
import XCTest

private final class WindowTabRenameTestState {
    var text = ""
    var commitCount = 0
    var cancelCount = 0
}

@MainActor extension WindowTabsTest {
    func testWindowTabStripOnlyAcceptsKeyInputWhileRenaming() {
        let panel = WindowTabStripPanel(id: ObjectIdentifier(WindowTabsTest.self))

        XCTAssertFalse(panel.canBecomeKey)
        panel.beginTabRename()
        XCTAssertTrue(panel.canBecomeKey)
        panel.endTabRename()
        XCTAssertFalse(panel.canBecomeKey)
    }

    func testWindowTabRenameCommitsWhenEditingEndsAndDoesNotCommitAfterEscape() {
        let committed = WindowTabRenameTestState()
        let committedCoordinator = WindowTabRenameTextField.Coordinator(
            text: Binding(get: { committed.text }, set: { committed.text = $0 }),
            onCommit: { committed.commitCount += 1 },
            onCancel: { committed.cancelCount += 1 }
        )
        let committedField = NSTextField(string: "Remembered")
        committedCoordinator.controlTextDidEndEditing(Notification(
            name: NSControl.textDidEndEditingNotification,
            object: committedField
        ))
        XCTAssertEqual(committed.text, "Remembered")
        XCTAssertEqual(committed.commitCount, 1)
        XCTAssertEqual(committed.cancelCount, 0)

        let cancelled = WindowTabRenameTestState()
        let cancelledCoordinator = WindowTabRenameTextField.Coordinator(
            text: Binding(get: { cancelled.text }, set: { cancelled.text = $0 }),
            onCommit: { cancelled.commitCount += 1 },
            onCancel: { cancelled.cancelCount += 1 }
        )
        let cancelledField = NSTextField(string: "Discarded")
        let editor = NSTextView()
        editor.string = "Discarded"
        XCTAssertTrue(cancelledCoordinator.control(
            cancelledField,
            textView: editor,
            doCommandBy: #selector(NSResponder.cancelOperation(_:))
        ))
        cancelledCoordinator.controlTextDidEndEditing(Notification(
            name: NSControl.textDidEndEditingNotification,
            object: cancelledField
        ))
        XCTAssertEqual(cancelled.commitCount, 0)
        XCTAssertEqual(cancelled.cancelCount, 1)
    }

    func testCrossWorkspaceCenterBodyDropIsDisabled() {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        let main = WindowTabsTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WindowTabsTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        defer { clearPendingWindowDragIntent() }

        let sourceWorkspace = Workspace.get(byName: "source")
        XCTAssertTrue(sourceWorkspace.focusWorkspace())
        let source = TestWindow.new(id: 1, parent: sourceWorkspace.rootTilingContainer)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 220, height: 180)

        let targetWorkspace = Workspace.get(byName: "target")
        targetWorkspace.seedMonitorIfNeeded(secondary)
        XCTAssertTrue(secondary.setActiveWorkspace(targetWorkspace))
        let mouseLocation = targetWorkspace.workspaceMonitor.visibleRectPaddedByOuterGaps.center

        XCTAssertFalse(updatePendingWindowDragIntent(
            sourceWindow: source,
            mouseLocation: mouseLocation,
            subject: .window,
            detachOrigin: .window,
        ))

        XCTAssertNil(debugPendingWindowDragIntentSummary())
    }

    @MainActor
    func testCrossWorkspaceDragOverTargetWindowOffersSurfaceIntent() {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        defer { clearPendingWindowDragIntent() }

        let sourceWorkspace = Workspace.get(byName: "source")
        let source = TestWindow.new(id: 1, parent: sourceWorkspace.rootTilingContainer)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 220, height: 180)

        let targetWorkspace = Workspace.get(byName: "target")
        let target = TestWindow.new(id: 2, parent: targetWorkspace.rootTilingContainer)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 120, topLeftY: 80, width: 420, height: 300)
        XCTAssertTrue(targetWorkspace.focusWorkspace())

        XCTAssertTrue(updatePendingWindowDragIntent(
            sourceWindow: source,
            mouseLocation: target.stackSplitDropZoneRect(position: .left).orDie().center,
            subject: .window,
            detachOrigin: .window,
        ))

        XCTAssertEqual(
            debugPendingWindowDragIntentSummary()?.kind,
            .stackSplit(targetWindowId: target.windowId, position: .left)
        )
    }

    @MainActor
    func testWindowTabStripGroupDragDefersToDetachedTabDrag() {
        setUpWorkspacesForTests()
        cancelManipulatedWithMouseState()

        XCTAssertTrue(beginWindowMoveWithMouseSessionIfNeeded(
            windowId: 42,
            subject: .window,
            detachOrigin: .tabStrip,
            startedInSidebar: false,
            anchorRect: nil,
        ))

        XCTAssertTrue(shouldDeferWindowTabStripGroupDragToDetachedTabDrag())
    }

    @MainActor
    func testWindowTabStripGroupDragEndIsIgnoredForDetachedTabDrags() {
        setUpWorkspacesForTests()
        cancelManipulatedWithMouseState()

        XCTAssertTrue(beginWindowMoveWithMouseSessionIfNeeded(
            windowId: 42,
            subject: .window,
            detachOrigin: .tabStrip,
            startedInSidebar: false,
            anchorRect: nil,
        ))

        XCTAssertFalse(shouldHandleWindowTabStripGroupDragEnd())
    }

    @MainActor
    func testWindowTabStripGroupDragEndRunsForGroupDrags() {
        setUpWorkspacesForTests()
        cancelManipulatedWithMouseState()

        XCTAssertTrue(beginWindowMoveWithMouseSessionIfNeeded(
            windowId: 42,
            subject: .group,
            detachOrigin: .window,
            startedInSidebar: false,
            anchorRect: nil,
        ))

        XCTAssertTrue(shouldHandleWindowTabStripGroupDragEnd())
    }

    func testWindowTabStripDragInProgressRecognizesDetachedTabDrag() {
        XCTAssertTrue(isWindowTabStripDragInProgress(
            kind: .move,
            subject: .window,
            detachOrigin: .tabStrip,
            startedInSidebar: false,
        ))
    }

    func testWindowTabStripDragInProgressRecognizesGroupDrag() {
        XCTAssertTrue(isWindowTabStripDragInProgress(
            kind: .move,
            subject: .group,
            detachOrigin: .window,
            startedInSidebar: false,
        ))
    }

    func testTabStripOriginatedDragKeepsTabStripMouseEventsEnabled() {
        XCTAssertFalse(shouldIgnoreWindowTabStripMouseEventsDuringDrag(detachOrigin: .tabStrip))
        XCTAssertTrue(shouldIgnoreWindowTabStripMouseEventsDuringDrag(detachOrigin: .window))
    }

    func testTabStripReentryTargetIndexTracksPointerPosition() {
        let stripRect = Rect(topLeftX: 100, topLeftY: 20, width: 420, height: 44)
        let tabWidth = windowTabStripTabWidth(stripWidth: stripRect.width, count: 3)
        let firstTabMinX = stripRect.minX + windowTabStripContentHorizontalPadding
        let secondTabCenterX = firstTabMinX + tabWidth + windowTabStripTabSpacing + tabWidth / 2

        XCTAssertEqual(
            tabReentryTargetIndex(mouseLocation: CGPoint(x: 120, y: 40), tabStripRect: stripRect, tabCount: 3, sourceIndex: 0),
            0
        )
        XCTAssertEqual(
            tabReentryTargetIndex(mouseLocation: CGPoint(x: secondTabCenterX - 1, y: 40), tabStripRect: stripRect, tabCount: 3, sourceIndex: 0),
            0
        )
        XCTAssertEqual(
            tabReentryTargetIndex(mouseLocation: CGPoint(x: secondTabCenterX + 1, y: 40), tabStripRect: stripRect, tabCount: 3, sourceIndex: 0),
            1
        )
    }

    func testTabStripReentryTargetIndexAdjustsForSourceRemovalWhenDraggingBackward() {
        let stripRect = Rect(topLeftX: 100, topLeftY: 20, width: 420, height: 44)
        let tabWidth = windowTabStripTabWidth(stripWidth: stripRect.width, count: 3)
        let firstTabCenterX = stripRect.minX + windowTabStripContentHorizontalPadding + tabWidth / 2

        XCTAssertEqual(
            tabReentryTargetIndex(mouseLocation: CGPoint(x: firstTabCenterX - 1, y: 40), tabStripRect: stripRect, tabCount: 3, sourceIndex: 2),
            0
        )
        XCTAssertEqual(
            tabReentryTargetIndex(mouseLocation: CGPoint(x: firstTabCenterX + 1, y: 40), tabStripRect: stripRect, tabCount: 3, sourceIndex: 2),
            1
        )
    }

    func testTabReorderTargetIndexMovesFirstTabToExplicitFinalInsertionSlot() {
        let tabWidth: CGFloat = 96
        let firstTabMinX: CGFloat = 5
        let effectiveTabWidth = tabWidth + windowTabStripTabSpacing
        let lastTabCenterX = firstTabMinX + CGFloat(3) * effectiveTabWidth + tabWidth / 2

        XCTAssertEqual(
            tabReorderTargetIndex(
                pointerX: lastTabCenterX + 1,
                firstTabMinX: firstTabMinX,
                tabWidth: tabWidth,
                tabCount: 4,
                sourceIndex: 0,
            ),
            3
        )
        XCTAssertEqual(
            tabReorderTargetIndex(
                pointerX: lastTabCenterX + tabWidth,
                firstTabMinX: firstTabMinX,
                tabWidth: tabWidth,
                tabCount: 4,
                sourceIndex: 0,
            ),
            3
        )
    }

    func testTabReorderTargetIndexUsesTabMidpointsInBothDirections() {
        let tabWidth: CGFloat = 100
        let firstTabMinX: CGFloat = 5
        let effectiveTabWidth = tabWidth + windowTabStripTabSpacing
        let firstTabCenterX = firstTabMinX + tabWidth / 2
        let thirdTabCenterX = firstTabMinX + CGFloat(2) * effectiveTabWidth + tabWidth / 2

        XCTAssertEqual(
            tabReorderTargetIndex(
                pointerX: firstTabCenterX - 1,
                firstTabMinX: firstTabMinX,
                tabWidth: tabWidth,
                tabCount: 4,
                sourceIndex: 3,
            ),
            0
        )
        XCTAssertEqual(
            tabReorderTargetIndex(
                pointerX: thirdTabCenterX - 1,
                firstTabMinX: firstTabMinX,
                tabWidth: tabWidth,
                tabCount: 4,
                sourceIndex: 0,
            ),
            1
        )
        XCTAssertEqual(
            tabReorderTargetIndex(
                pointerX: thirdTabCenterX + 1,
                firstTabMinX: firstTabMinX,
                tabWidth: tabWidth,
                tabCount: 4,
                sourceIndex: 0,
            ),
            2
        )
    }

    func testTabReorderFrameTargetMovesSiblingsAroundDraggedTab() {
        let order: [UInt32] = [10, 20, 30, 40]
        let frames = Dictionary(uniqueKeysWithValues: order.enumerated().map { index, id in
            (id, CGRect(x: CGFloat(index) * 106, y: 0, width: 100, height: 24))
        })

        XCTAssertEqual(
            tabReorderTargetIndexForFrames(
                pointerXInViewport: 370,
                tabOrder: order,
                tabFramesById: frames,
                sourceIndex: 0,
            ),
            3
        )
        XCTAssertEqual(
            tabReorderTargetIndexForFrames(
                pointerXInViewport: 35,
                tabOrder: order,
                tabFramesById: frames,
                sourceIndex: 3,
            ),
            0
        )
    }

    func testWindowTabAutoScrollDirectionActivatesOnlyAtScrollableEdges() {
        XCTAssertEqual(
            windowTabAutoScrollDirection(pointerXInViewport: 27, viewportWidth: 180, isScrollable: true),
            .leading
        )
        XCTAssertEqual(
            windowTabAutoScrollDirection(pointerXInViewport: 152, viewportWidth: 180, isScrollable: true),
            .trailing
        )
        XCTAssertNil(windowTabAutoScrollDirection(pointerXInViewport: 90, viewportWidth: 180, isScrollable: true))
        XCTAssertNil(windowTabAutoScrollDirection(pointerXInViewport: 1, viewportWidth: 180, isScrollable: false))
    }

    func testTabStripReentrySourceVisualOffsetTracksPointerSmoothly() {
        let stripRect = Rect(topLeftX: 100, topLeftY: 20, width: 420, height: 54)
        let middle = tabReentrySourceVisualOffset(
            mouseLocation: CGPoint(x: 310, y: 40),
            tabStripRect: stripRect,
            tabCount: 3,
            sourceIndex: 1
        )
        let right = tabReentrySourceVisualOffset(
            mouseLocation: CGPoint(x: 350, y: 40),
            tabStripRect: stripRect,
            tabCount: 3,
            sourceIndex: 1
        )

        XCTAssertGreaterThan(right, middle)
    }

    @MainActor
    func testDetachedTabReentryReordersWithinCurrentTabGroup() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let tabGroup = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let first = TestWindow.new(id: 1, parent: tabGroup)
        let second = TestWindow.new(id: 2, parent: tabGroup)
        let third = TestWindow.new(id: 3, parent: tabGroup)

        XCTAssertTrue(reorderWindowTabInCurrentGroup(third, toIndex: 1))
        XCTAssertEqual(tabGroup.children.compactMap { ($0 as? AppBundle.Window)?.windowId }, [first.windowId, third.windowId, second.windowId])
    }

    @MainActor
    func testWindowTabAliasResolutionAndReset() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let window = TestWindow.new(id: 41, parent: workspace.rootTilingContainer)
        let key = windowTabLabelKey(for: window)

        let fallbackTitle = await tabDisplayTitle(for: window)
        XCTAssertEqual(fallbackTitle, window.description)

        config.windowTabs.tabLabels[key] = "Persisted"
        let persistedTitle = await tabDisplayTitle(for: window)
        XCTAssertEqual(persistedTitle, "Persisted")

        try await renameWindowTab(windowId: window.windowId, displayName: "Session")
        let sessionTitle = await tabDisplayTitle(for: window)
        XCTAssertEqual(sessionTitle, "Session")
        XCTAssertEqual(config.windowTabs.tabLabels[key], "Session")

        let frozenWindow = FrozenWindow(window)
        resetWindowTabLabelsForTests()
        let configRestoredTitle = await tabDisplayTitle(for: window)
        XCTAssertEqual(configRestoredTitle, "Session")
        config.windowTabs.tabLabels.removeValue(forKey: key)
        restoreWindowTabLabelForRestart(windowId: window.windowId, label: frozenWindow.tabLabel)
        let snapshotRestoredTitle = await tabDisplayTitle(for: window)
        XCTAssertEqual(snapshotRestoredTitle, "Session")

        try await renameWindowTab(windowId: window.windowId, displayName: "   ")
        let resetTitle = await tabDisplayTitle(for: window)
        XCTAssertEqual(resetTitle, window.description)
        XCTAssertNil(config.windowTabs.tabLabels[key])
    }

    @MainActor
    func testWindowTabAliasesStayInTabStripWhileSidebarSummarizesComposedTab() async throws {
        setUpWorkspacesForTests()
        config.windowTabs.enabled = true
        let workspace = Workspace.get(byName: "tabs")
        let tabGroup = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let first = TestWindow.new(id: 51, parent: tabGroup)
        _ = TestWindow.new(id: 52, parent: tabGroup)
        tabGroup.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 500, height: 300)
        XCTAssertTrue(workspace.focusWorkspace())
        XCTAssertTrue(first.focusWindow())

        try await renameWindowTab(windowId: first.windowId, displayName: "Docs")

        let strips = await buildWindowTabStripViewModelsFromChromeItems()
        XCTAssertEqual(strips.singleOrNil()?.tabs.first(where: { $0.windowId == first.windowId })?.title, "Docs")

        let sidebarTabs = await buildWorkspaceSidebarWorkspaceViewModels(
            currentFocus: focus,
            workspaceLabels: [:],
            availableMonitors: [mainMonitor],
        )
        let sidebarTab = try XCTUnwrap(sidebarTabs.first { $0.name == workspace.name })
        XCTAssertEqual(sidebarTab.tabSummary.title, "bobko.WinMux.test-app & 1 other")
        XCTAssertEqual(sidebarTab.items.map(\.id), ["group:51"])
    }

    func testCompositedGroupPreviewOnlyRunsForTabStripOriginatedGroupDrags() {
        XCTAssertTrue(shouldShowCompositedGroupMovePreview(
            subject: .group,
            startedInSidebar: false,
        ))
        XCTAssertFalse(shouldShowCompositedGroupMovePreview(
            subject: .group,
            startedInSidebar: true,
        ))
        XCTAssertFalse(shouldShowCompositedGroupMovePreview(
            subject: .window,
            startedInSidebar: false,
        ))
    }

    func testWindowTabStripCapsWidthAndShrinksToFit() {
        XCTAssertEqual(windowTabStripTabWidth(stripWidth: 1000, count: 1), 200)
        XCTAssertEqual(windowTabStripTabWidth(stripWidth: 1000, count: 2), 200)
        let width: CGFloat = 360
        XCTAssertEqual(windowTabStripScrollViewportWidth(stripWidth: width), width)
        XCTAssertEqual(windowTabStripTabWidth(stripWidth: width, count: 2), 178)
        let threeTabWidth = windowTabStripTabWidth(stripWidth: width, count: 3)
        XCTAssertEqual(threeTabWidth, (width - windowTabStripTabSpacing * 2) / 3)
        XCTAssertEqual(threeTabWidth * 3 + windowTabStripTabSpacing * 2, width, accuracy: 0.001)
        XCTAssertEqual(windowTabStripTabWidth(stripWidth: 0, count: 3), 0)
    }

    func testWindowTabStripScrollBackgroundDragIgnoresTabPills() {
        let tabWidth: CGFloat = 120
        let tabsStart = windowTabStripContentHorizontalPadding
        let tabsEnd = tabsStart + tabWidth * 2 + windowTabStripTabSpacing

        XCTAssertFalse(isWindowTabStripScrollBackgroundDragStart(
            localX: tabsStart + 12,
            contentMinX: 0,
            tabWidth: tabWidth,
            tabCount: 2,
        ))
        XCTAssertFalse(isWindowTabStripScrollBackgroundDragStart(
            localX: tabsEnd - 12,
            contentMinX: 0,
            tabWidth: tabWidth,
            tabCount: 2,
        ))
        XCTAssertTrue(isWindowTabStripScrollBackgroundDragStart(
            localX: tabsEnd + 12,
            contentMinX: 0,
            tabWidth: tabWidth,
            tabCount: 2,
        ))
    }

    func testWindowTabStripLeadingFadeOnlyAppearsAfterScrollingFromLeftEdge() {
        let stripWidth: CGFloat = 240

        XCTAssertEqual(windowTabLeadingScrollFadeWidth(
            isScrollable: true,
            contentMinX: 0,
            stripWidth: stripWidth,
        ), 0)
        XCTAssertEqual(windowTabLeadingScrollFadeWidth(
            isScrollable: true,
            contentMinX: -windowTabStripContentHorizontalPadding - 0.5,
            stripWidth: stripWidth,
        ), 0)
        XCTAssertEqual(windowTabLeadingScrollFadeWidth(
            isScrollable: false,
            contentMinX: -12,
            stripWidth: stripWidth,
        ), 0)
        XCTAssertGreaterThan(windowTabLeadingScrollFadeWidth(
            isScrollable: true,
            contentMinX: -windowTabStripContentHorizontalPadding - 2,
            stripWidth: stripWidth,
        ), 0)
    }

    func testWindowTabStripTrailingFadeTracksScrollableContent() {
        let stripWidth: CGFloat = 240
        let viewportWidth: CGFloat = 180

        XCTAssertEqual(windowTabTrailingScrollFadeWidth(
            isScrollable: false,
            contentMaxX: viewportWidth + 24,
            viewportWidth: viewportWidth,
            stripWidth: stripWidth,
        ), 0)
        XCTAssertEqual(windowTabTrailingScrollFadeWidth(
            isScrollable: true,
            contentMaxX: viewportWidth,
            viewportWidth: viewportWidth,
            stripWidth: stripWidth,
        ), 0)
        XCTAssertEqual(windowTabTrailingScrollFadeWidth(
            isScrollable: true,
            contentMaxX: viewportWidth + windowTabStripContentHorizontalPadding + 0.5,
            viewportWidth: viewportWidth,
            stripWidth: stripWidth,
        ), 0)
        XCTAssertGreaterThan(windowTabTrailingScrollFadeWidth(
            isScrollable: true,
            contentMaxX: viewportWidth + windowTabStripContentHorizontalPadding + 2,
            viewportWidth: viewportWidth,
            stripWidth: stripWidth,
        ), 0)
    }

    @MainActor
    func testHudPanelBaseDoesNotPaintSystemHudBackdrop() {
        let panel = NSPanelHud()

        XCTAssertFalse(panel.styleMask.contains(.hudWindow))
        XCTAssertFalse(panel.isOpaque)
    }

    @MainActor
    func testResizePreviewWeightMapDoesNotMutateWeightsUntilCommit() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        root.changeOrientation(.h)
        root.layout = .tiles

        let left = TestWindow.new(id: 1, parent: root, adaptiveWeight: 500)
        let right = TestWindow.new(id: 2, parent: root, adaptiveWeight: 500)
        left.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 500, height: 400)
        left.lastAppliedLayoutVirtualRect = left.lastAppliedLayoutPhysicalRect
        right.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 500, topLeftY: 0, width: 500, height: 400)
        right.lastAppliedLayoutVirtualRect = right.lastAppliedLayoutPhysicalRect

        let proposedRect = Rect(topLeftX: 0, topLeftY: 0, width: 620, height: 400)
        let weightMap = proposedResizeWeightMap(left, rect: proposedRect).orDie()

        XCTAssertEqual(left.hWeight, 500)
        XCTAssertEqual(right.hWeight, 500)
        XCTAssertEqual(weightMap.weight(for: left, orientation: .h), 620)
        XCTAssertEqual(weightMap.weight(for: right, orientation: .h), 380)

        applyResizeWithMouse(left, rect: proposedRect)

        XCTAssertEqual(left.hWeight, 620)
        XCTAssertEqual(right.hWeight, 380)
        cancelManipulatedWithMouseState()
    }

    func testWindowTabStripDragInProgressIgnoresRegularWindowMove() {
        XCTAssertFalse(isWindowTabStripDragInProgress(
            kind: .move,
            subject: .window,
            detachOrigin: .window,
            startedInSidebar: false,
        ))
        XCTAssertFalse(isWindowTabStripDragInProgress(
            kind: .move,
            subject: .group,
            detachOrigin: .window,
            startedInSidebar: true,
        ))
    }

}
