@testable import AppBundle
import Common
import XCTest

@MainActor
final class WorkspaceLifecycleTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testSystemOverlayDoesNotKeepWorkspaceAliveAfterLastRealWindowCloses() {
        let fallback = Workspace.get(byName: "fallback")
        TestWindow.new(id: 8101, parent: fallback.rootTilingContainer)
        let workspace = Workspace.get(byName: "closing")
        let realWindow = TestWindow.new(id: 8102, parent: workspace.rootTilingContainer)
        let overlay = TestWindow.new(id: 8103, parent: workspace)
        _ = workspace.focusWorkspace()

        XCTAssertTrue(normalizeSystemOverlayWindow(overlay, level: .unknown(windowLevel: 1001)))
        XCTAssertTrue(overlay.parent === macosPopupWindowsContainer)
        XCTAssertTrue(Workspace.existing(byName: workspace.name) === workspace)
        realWindow.closeAxWindow()
        XCTAssertNil(Workspace.existing(byName: workspace.name))
        XCTAssertTrue(focus.workspace === fallback)
    }

    func testRemovingRestoredOverlayClosesOtherwiseEmptyWorkspace() {
        let fallback = Workspace.get(byName: "fallback")
        TestWindow.new(id: 8111, parent: fallback.rootTilingContainer)
        let workspace = Workspace.get(byName: "overlay-only")
        let overlay = TestWindow.new(id: 8112, parent: workspace)
        _ = workspace.focusWorkspace()

        XCTAssertFalse(normalizeSystemOverlayWindow(overlay, level: nil))
        XCTAssertFalse(normalizeSystemOverlayWindow(overlay, level: .alwaysOnTopWindow))
        XCTAssertTrue(overlay.parent === workspace)
        XCTAssertTrue(normalizeSystemOverlayWindow(overlay, level: .unknown(windowLevel: 1001)))
        XCTAssertNil(Workspace.existing(byName: workspace.name))
    }

    func testNewDialogIsRaisedWhenItsAppIsAlreadyActive() {
        XCTAssertTrue(shouldRaiseNewlyDetectedDialog(
            isStartup: false,
            wasRestored: false,
            wasDetectedAsDialog: true,
            appIsActive: true,
            appWasFrontmostWhenDetected: true,
        ))
    }

    func testNewDialogIsRaisedWhenFrontmostStatePrecedesActiveState() {
        XCTAssertTrue(shouldRaiseNewlyDetectedDialog(
            isStartup: false,
            wasRestored: false,
            wasDetectedAsDialog: true,
            appIsActive: false,
            appWasFrontmostWhenDetected: true,
        ))
    }

    func testNewDialogDoesNotStealAttentionFromBackgroundApp() {
        XCTAssertFalse(shouldRaiseNewlyDetectedDialog(
            isStartup: false,
            wasRestored: false,
            wasDetectedAsDialog: true,
            appIsActive: false,
            appWasFrontmostWhenDetected: false,
        ))
    }

    func testRestoredOrStartupDialogsAreNotRaised() {
        XCTAssertFalse(shouldRaiseNewlyDetectedDialog(
            isStartup: true,
            wasRestored: false,
            wasDetectedAsDialog: true,
            appIsActive: true,
            appWasFrontmostWhenDetected: true,
        ))
        XCTAssertFalse(shouldRaiseNewlyDetectedDialog(
            isStartup: false,
            wasRestored: true,
            wasDetectedAsDialog: true,
            appIsActive: true,
            appWasFrontmostWhenDetected: true,
        ))
    }

    func testNewDialogRaiseIsDeferredUntilAfterFocusSync() {
        let queue = NewlyDetectedDialogRaiseQueue()
        var raisedWindowIds: [UInt32] = []

        queue.schedule(windowId: 41) { raisedWindowIds.append(41) }

        XCTAssertTrue(raisedWindowIds.isEmpty)
        queue.drain()
        XCTAssertEqual(raisedWindowIds, [41])
    }

    func testNewDialogTakesLogicalAndNativeFocusAfterPreviousWindowSync() {
        let workspace = focus.workspace
        let previous = TestWindow.new(id: 501, parent: workspace.rootTilingContainer)
        let dialog = TestWindow.new(id: 502, parent: workspace)
        _ = previous.focusWindow()
        previous.nativeFocus()
        let queue = NewlyDetectedDialogRaiseQueue()
        queue.schedule(windowId: dialog.windowId) { focusNewlyDetectedDialog(dialog) }

        queue.drain()

        XCTAssertEqual(focus.windowOrNil?.windowId, dialog.windowId)
        XCTAssertEqual(TestApp.shared.focusedWindow?.windowId, dialog.windowId)
        updateFocusCache(dialog)
        XCTAssertEqual(focus.windowOrNil?.windowId, dialog.windowId)
    }

    func testNewDialogInHiddenWorkspaceDoesNotStealFocus() {
        let previous = TestWindow.new(id: 501, parent: focus.workspace.rootTilingContainer)
        _ = previous.focusWindow()
        previous.nativeFocus()
        let hiddenWorkspace = Workspace.get(byName: "hidden-dialog")
        let dialog = TestWindow.new(id: 502, parent: hiddenWorkspace)

        focusNewlyDetectedDialog(dialog)

        XCTAssertEqual(focus.windowOrNil?.windowId, previous.windowId)
        XCTAssertEqual(TestApp.shared.focusedWindow?.windowId, previous.windowId)
    }

    func testNewDialogRaiseQueueKeepsLatestActionForWindow() {
        let queue = NewlyDetectedDialogRaiseQueue()
        var actions: [String] = []

        queue.schedule(windowId: 41) { actions.append("stale") }
        queue.schedule(windowId: 41) { actions.append("latest") }
        queue.drain()

        XCTAssertEqual(actions, ["latest"])
    }

    func testReconcilePrunesUnfocusedEmptyWorkspacesWhenProjectHasOccupiedWorkspace() {
        let occupied = Workspace.get(byName: "1")
        occupied.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 1, parent: occupied.rootTilingContainer)
        let adjacentEmpty = Workspace.get(byName: "2")
        adjacentEmpty.markAsTransientBlank()
        let extraEmpty = Workspace.get(byName: "3")
        extraEmpty.markAsTransientBlank()
        _ = occupied.focusWorkspace()

        Workspace.reconcileWorkspaceState()

        XCTAssertNil(Workspace.existing(byName: "2"))
        XCTAssertNil(Workspace.existing(byName: "3"))
        XCTAssertEqual(emptyUserFacingWorkspaces(in: occupied.projectId), [])
        _ = adjacentEmpty
    }

    func testReconcileKeepsOnlyVisibleWorkspaceWhenAllWorkspacesAreEmpty() {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        let visible = Workspace.get(byName: "2")
        visible.markAsAutomaticallyNamed()
        let last = Workspace.get(byName: "3")
        last.markAsAutomaticallyNamed()
        _ = visible.focusWorkspace()

        Workspace.reconcileWorkspaceState()

        XCTAssertNil(Workspace.existing(byName: first.name))
        XCTAssertTrue(Workspace.existing(byName: visible.name) === visible)
        XCTAssertNil(Workspace.existing(byName: last.name))
        XCTAssertEqual(Workspace.all, [visible])
    }

    func testFocusedAdjacentBlankWorkspaceCreationReusesExistingEmptySlot() async throws {
        let occupied = Workspace.get(byName: "1")
        occupied.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 2, parent: occupied.rootTilingContainer)
        _ = occupied.focusWorkspace()
        assertEquals(
            try await WorkspaceCommand(args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())))
                .run(.defaultEnv, .emptyStdin)
                .exitCode,
            0,
        )
        let existingBlank = try XCTUnwrap(Workspace.existing(byName: "2"))

        let blank = getOrCreateAdjacentBlankWorkspace(projectId: occupied.projectId, monitor: occupied.workspaceMonitor)

        XCTAssertTrue(blank === existingBlank)
        XCTAssertNil(Workspace.existing(byName: "3"))
    }

    func testFreshAdjacentBlankWorkspaceDoesNotReuseExistingEmptySlotAndInsertsAfterActiveTab() async throws {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 21, parent: first.rootTilingContainer)
        let existingBlank = Workspace.get(byName: "2")
        existingBlank.markAsTransientBlank()
        let second = Workspace.get(byName: "3")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 22, parent: second.rootTilingContainer)
        XCTAssertTrue(first.focusWorkspace())

        let fresh = createFreshAdjacentBlankWorkspace(
            projectId: workspaceProjectDefaultId,
            monitor: first.workspaceMonitor,
            after: first
        )

        XCTAssertFalse(fresh === existingBlank)
        XCTAssertTrue(fresh.isEffectivelyEmpty)
        let relevantNames = Set([first.name, fresh.name, existingBlank.name, second.name])
        XCTAssertEqual(
            orderedWorkspacesForPresentation()
                .filter { !$0.isArchived && relevantNames.contains($0.name) }
                .map(\.name),
            [first.name, fresh.name, existingBlank.name, second.name]
        )
    }

    func testAdjacentBlankWorkspaceCreationDoesNotReuseOtherMonitorEmptyTab() {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main])
        let mainOccupied = Workspace.get(byName: "main")
        mainOccupied.markAsAutomaticallyNamed()
        mainOccupied.seedMonitorIfNeeded(main)
        _ = TestWindow.new(id: 24, parent: mainOccupied.rootTilingContainer)
        XCTAssertTrue(main.setActiveWorkspace(mainOccupied))
        Workspace.reconcileWorkspaceState()
        setMonitorsForTests([main, secondary])
        let secondaryBlank = Workspace.get(byName: "secondary-blank")
        secondaryBlank.markAsTransientBlank()
        secondaryBlank.seedMonitorIfNeeded(secondary)
        XCTAssertTrue(secondary.setActiveWorkspace(secondaryBlank))

        let mainBlank = getOrCreateAdjacentBlankWorkspace(projectId: workspaceProjectDefaultId, monitor: main)

        XCTAssertFalse(mainBlank === secondaryBlank)
        XCTAssertEqual(mainBlank.workspaceMonitor.rect.topLeftCorner, main.rect.topLeftCorner)
        XCTAssertTrue(secondary.activeWorkspace === secondaryBlank)
    }

    func testSidebarDragReusesRawAdjacentNameAfterUnfocusedBlankIsCollected() async throws {
        let sourceWorkspace = Workspace.get(byName: "1")
        sourceWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 3, parent: sourceWorkspace.rootTilingContainer)
        let movedWindow = TestWindow.new(id: 4, parent: sourceWorkspace.rootTilingContainer)
        _ = sourceWorkspace.focusWorkspace()
        assertEquals(
            try await WorkspaceCommand(args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())))
                .run(.defaultEnv, .emptyStdin)
                .exitCode,
            0,
        )
        let deletedBlank = try XCTUnwrap(Workspace.existing(byName: "2"))
        _ = sourceWorkspace.focusWorkspace()
        Workspace.reconcileWorkspaceState()

        XCTAssertTrue(createWorkspaceFromSidebarDrag(sourceNode: movedWindow, sourceWindow: movedWindow))

        XCTAssertFalse(Workspace.existing(byName: deletedBlank.name) === deletedBlank)
        XCTAssertEqual(movedWindow.nodeWorkspace?.name, "2")
        XCTAssertNil(Workspace.existing(byName: "3"))
        XCTAssertTrue(emptyUserFacingWorkspaces(in: sourceWorkspace.projectId).isEmpty)
    }

    func testMovingLastProjectWindowAwayDeletesEmptyProject() async throws {
        let defaultTarget = Workspace.get(byName: "default-target")
        _ = TestWindow.new(id: 5, parent: defaultTarget.rootTilingContainer)
        let project = createWorkspaceProject()
        let projectWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: mainMonitor))
        let projectWindow = TestWindow.new(id: 6, parent: projectWorkspace.rootTilingContainer)
        _ = projectWindow.focusWindow()

        assertEquals(
            try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: defaultTarget.name))
                .run(.defaultEnv, .emptyStdin)
                .exitCode,
            0,
        )
        Workspace.reconcileWorkspaceState()

        XCTAssertEqual(mainMonitor.activeWorkspace.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(projectWindow.nodeWorkspace?.projectId, workspaceProjectDefaultId)
        XCTAssertFalse(Workspace.existing(byName: projectWorkspace.name) === projectWorkspace)
        XCTAssertNil(winMuxWorkspaceState.workspaceFoldersById[project.unfoldedFolderId])
        XCTAssertNil(winMuxWorkspaceState.projectsById[project.id])
    }

    func testWorkspaceNextFromExistingBlankDoesNotCreateAnotherBlank() async throws {
        let occupied = Workspace.get(byName: "1")
        occupied.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 7, parent: occupied.rootTilingContainer)
        _ = occupied.focusWorkspace()
        assertEquals(
            try await WorkspaceCommand(args: WorkspaceCmdArgs(target: .relative(.next)))
                .run(.defaultEnv, .emptyStdin)
                .exitCode,
            0,
        )

        let result = try await WorkspaceCommand(args: WorkspaceCmdArgs(target: .relative(.next)))
            .run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertNil(Workspace.existing(byName: "3"))
        XCTAssertEqual(emptyUserFacingWorkspaces(in: occupied.projectId).map(\.name), ["2"])
    }

    func testEmptyAdjacentWorkspaceIsDeletedAfterLeavingIt() async throws {
        let occupied = Workspace.get(byName: "1")
        occupied.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 8, parent: occupied.rootTilingContainer)
        _ = occupied.focusWorkspace()

        assertEquals(
            try await WorkspaceCommand(args: WorkspaceCmdArgs(target: .relative(.next)))
                .run(.defaultEnv, .emptyStdin)
                .exitCode,
            0,
        )
        let emptyWorkspace = try XCTUnwrap(Workspace.existing(byName: "2"))

        _ = occupied.focusWorkspace()
        Workspace.reconcileWorkspaceState()

        XCTAssertNil(Workspace.existing(byName: emptyWorkspace.name))
        XCTAssertEqual(userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace), [occupied])
    }

    func testRenamedVisibleEmptyWorkspaceIsDeletedWhenItBecomesEmpty() throws {
        let occupied = Workspace.get(byName: "1")
        occupied.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 9, parent: occupied.rootTilingContainer)
        let renamed = Workspace.get(byName: "2")
        renamed.markAsAutomaticallyNamed()
        try renameWorkspaceForSidebar(workspaceName: renamed.name, displayName: "Code")
        _ = renamed.focusWorkspace()

        Workspace.reconcileWorkspaceState()

        XCTAssertNil(Workspace.existing(byName: renamed.name))
        XCTAssertEqual(config.workspaceSidebar.workspaceLabels[renamed.name], "Code")
        XCTAssertTrue(mainMonitor.activeWorkspace === occupied)
        XCTAssertEqual(userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace), [occupied])
    }

    func testConnectingSecondMonitorCreatesVisibleWorkspaceForDefaultProject() {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        setMonitorsForTests([main])
        let workspace = Workspace.get(byName: "1")
        workspace.markAsAutomaticallyNamed()
        XCTAssertTrue(main.setActiveWorkspace(workspace))
        Workspace.reconcileWorkspaceState()

        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])

        Workspace.reconcileWorkspaceState()

        XCTAssertTrue(main.activeWorkspace === workspace)
        XCTAssertNotNil(secondary.activeWorkspace)
        XCTAssertFalse(secondary.activeWorkspace === workspace)
        XCTAssertEqual(secondary.activeWorkspace.projectId, workspaceProjectDefaultId)
        XCTAssertTrue(secondary.activeWorkspace.isOrdinaryEmptySlot)
        XCTAssertEqual(Workspace.all.filter { $0.projectId == workspaceProjectDefaultId && !$0.isArchived }.count, 2)
    }

    func testReconcileRepairsCurrentMonitorViewportWithMissingActiveWorkspace() {
        let workspace = Workspace.get(byName: "1")
        workspace.markAsAutomaticallyNamed()
        XCTAssertTrue(mainMonitor.setActiveWorkspace(workspace))
        let viewportId = MonitorViewportId(mainMonitor)
        var viewport = winMuxWorkspaceState.monitorViewportsById[viewportId].orDie()
        viewport.activeWorkspaceId = nil
        winMuxWorkspaceState.monitorViewportsById[viewportId] = viewport

        Workspace.reconcileWorkspaceState()

        XCTAssertNotNil(winMuxWorkspaceState.monitorViewportsById[viewportId]?.activeWorkspaceId)
        XCTAssertEqual(mainMonitor.activeWorkspace.projectId, workspaceProjectDefaultId)
    }

    func testEachMonitorKeepsDefaultTabWhenEmptyTabGroupDissolves() {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        let defaultWorkspace = Workspace.get(byName: "default")
        XCTAssertTrue(main.setActiveWorkspace(defaultWorkspace))
        let project = createWorkspaceProject()
        let projectWorkspace = createBlankWorkspace(projectId: project.id, monitor: secondary)
        XCTAssertTrue(secondary.setActiveWorkspace(projectWorkspace))

        Workspace.reconcileWorkspaceState()

        XCTAssertTrue(main.activeWorkspace === defaultWorkspace)
        XCTAssertTrue(secondary.activeWorkspace === projectWorkspace)
        XCTAssertEqual(defaultWorkspace.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(secondary.activeWorkspace.projectId, project.id)
        XCTAssertTrue(secondary.activeWorkspace.isOrdinaryEmptySlot)
        XCTAssertTrue(Workspace.existing(byName: projectWorkspace.name) === projectWorkspace)
        XCTAssertNotNil(winMuxWorkspaceState.workspaceFoldersById[project.unfoldedFolderId])
    }

    func testSameProjectCanBeActiveOnDifferentMonitorsWithDifferentWorkspaces() {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        let first = Workspace.get(byName: "project-workspace-a")
        let second = Workspace.get(byName: "project-workspace-b")
        first.assignProject(workspaceProjectDefaultId)
        second.assignProject(workspaceProjectDefaultId)

        XCTAssertTrue(main.setActiveWorkspace(first))
        XCTAssertTrue(secondary.setActiveWorkspace(second))

        XCTAssertTrue(main.activeWorkspace === first)
        XCTAssertTrue(secondary.activeWorkspace === second)
        XCTAssertEqual(main.activeWorkspace.projectId, secondary.activeWorkspace.projectId)
        checkWorkspaceHierarchyInvariants(requireActiveMonitorViewports: true)
    }

    func testSameWorkspaceCannotBeActiveOnTwoMonitorViewports() {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        let workspace = Workspace.get(byName: "shared-workspace")
        let otherWorkspace = Workspace.get(byName: "other-workspace")

        XCTAssertTrue(main.setActiveWorkspace(workspace))
        XCTAssertTrue(secondary.setActiveWorkspace(otherWorkspace))
        XCTAssertFalse(secondary.setActiveWorkspace(workspace))

        XCTAssertTrue(main.activeWorkspace === workspace)
        XCTAssertTrue(secondary.activeWorkspace === otherWorkspace)
        checkWorkspaceHierarchyInvariants(requireActiveMonitorViewports: true)
    }

    func testSidebarWorkspaceModelsKeepSeparateMonitorScopesForSameProject() async {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        let first = Workspace.get(byName: "project-workspace-a")
        let second = Workspace.get(byName: "project-workspace-b")
        XCTAssertTrue(main.setActiveWorkspace(first))
        XCTAssertTrue(secondary.setActiveWorkspace(second))

        let models = await buildWorkspaceSidebarWorkspaceViewModels(
            currentFocus: focus,
            workspaceLabels: [:],
            availableMonitors: sortedMonitors,
        )
        let projectModels = Dictionary(uniqueKeysWithValues: models
            .filter { $0.name == first.name || $0.name == second.name }
            .map { ($0.name, $0) })

        XCTAssertEqual(projectModels[first.name]?.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(projectModels[second.name]?.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(projectModels[first.name]?.monitorScopeId, workspaceSidebarMonitorScopeId(for: main))
        XCTAssertEqual(projectModels[second.name]?.monitorScopeId, workspaceSidebarMonitorScopeId(for: secondary))
        XCTAssertTrue(projectModels[first.name]?.isVisible == true)
        XCTAssertTrue(projectModels[second.name]?.isVisible == true)
    }

    func testNewWindowWithRectTargetsActiveWorkspaceOnWindowMonitor() {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        let focusedWorkspace = Workspace.get(byName: "main-tab")
        let secondaryActiveWorkspace = Workspace.get(byName: "secondary-tab")
        XCTAssertTrue(main.setActiveWorkspace(focusedWorkspace))
        XCTAssertTrue(secondary.setActiveWorkspace(secondaryActiveWorkspace))
        XCTAssertTrue(focusedWorkspace.focusWorkspace())

        let target = targetWorkspaceForNewWindow(
            isStartup: false,
            windowRect: Rect(topLeftX: 2100, topLeftY: 100, width: 800, height: 600),
            focusedWorkspace: focusedWorkspace,
        )

        XCTAssertTrue(target === secondaryActiveWorkspace)
    }

    func testNewWindowOnSecondaryMonitorCreatesAdjacentTabInActiveFolder() {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        let mainWorkspace = Workspace.get(byName: "main-tab")
        let secondaryWorkspace = Workspace.get(byName: "secondary-tab")
        secondaryWorkspace.seedMonitorIfNeeded(secondary)
        let folder = createWorkspaceFolder()
        secondaryWorkspace.assignProject(folder.projectId)
        _ = TestWindow.new(id: 38, parent: secondaryWorkspace.rootTilingContainer)
        XCTAssertTrue(main.setActiveWorkspace(mainWorkspace))
        XCTAssertTrue(secondary.setActiveWorkspace(secondaryWorkspace))

        let anchor = targetWorkspaceForNewWindow(
            isStartup: false,
            windowRect: Rect(topLeftX: 2100, topLeftY: 100, width: 800, height: 600),
            focusedWorkspace: mainWorkspace,
        )
        let destination = workspaceForNewTilingWindow(defaultWorkspace: anchor, placement: .freshTab)

        XCTAssertTrue(anchor === secondaryWorkspace)
        XCTAssertEqual(destination.folderId, secondaryWorkspace.folderId)
        XCTAssertEqual(destination.workspaceMonitor.rect.topLeftCorner, secondary.rect.topLeftCorner)
        let folderWorkspaceNames = orderedWorkspaces(in: folder.projectId)
            .filter { !$0.isArchived }
            .map(\.name)
        guard let secondaryIndex = folderWorkspaceNames.firstIndex(of: secondaryWorkspace.name) else {
            return XCTFail("Expected the active secondary tab in its folder order")
        }
        XCTAssertEqual(folderWorkspaceNames.getOrNil(atIndex: secondaryIndex + 1), destination.name)
        XCTAssertTrue(secondary.activeWorkspace === destination)
    }

    func testNewTilingWindowCreatesFreshAdjacentTabAfterOccupiedCurrentTab() {
        let occupied = focus.workspace
        occupied.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 34, parent: occupied.rootTilingContainer)
        XCTAssertTrue(mainMonitor.setActiveWorkspace(occupied))

        let destination = workspaceForNewTilingWindow(
            defaultWorkspace: occupied,
            placement: .freshTab
        )

        XCTAssertFalse(destination === occupied)
        XCTAssertTrue(destination.isEffectivelyEmpty)
        XCTAssertEqual(destination.lifecycle, .transient)
        XCTAssertTrue(mainMonitor.activeWorkspace === destination)
        XCTAssertEqual(destination.workspaceMonitor.rect.topLeftCorner, occupied.workspaceMonitor.rect.topLeftCorner)
        XCTAssertEqual(
            orderedWorkspacesForPresentation().filter { !$0.isArchived }.map(\.name),
            [occupied.name, destination.name]
        )
    }

    func testDefaultNewTilingWindowPlacementKeepsCurrentTab() {
        let current = focus.workspace
        _ = TestWindow.new(id: 3401, parent: current.rootTilingContainer)
        let workspaceIdsBefore = Set(Workspace.all.map(\.id))

        let destination = workspaceForNewTilingWindow(
            defaultWorkspace: current,
            placement: defaultNewTilingWindowPlacement()
        )

        XCTAssertEqual(defaultNewTilingWindowPlacement(), .targetWorkspace)
        XCTAssertTrue(destination === current)
        XCTAssertEqual(Set(Workspace.all.map(\.id)), workspaceIdsBefore)
    }

    func testNewTilingWindowCreatesFreshTabAfterEmptyCurrentTab() {
        let empty = focus.workspace
        empty.markAsTransientBlank()
        XCTAssertTrue(mainMonitor.setActiveWorkspace(empty))

        let destination = workspaceForNewTilingWindow(
            defaultWorkspace: empty,
            placement: .freshTab
        )

        XCTAssertFalse(destination === empty)
        XCTAssertTrue(destination.isEffectivelyEmpty)
        XCTAssertEqual(
            orderedWorkspacesForPresentation().filter { !$0.isArchived }.map(\.name),
            [empty.name, destination.name]
        )
        XCTAssertTrue(mainMonitor.activeWorkspace === destination)
    }

    func testNewTilingWindowCreatesFreshTabAfterPersistentEmptyCurrentTab() {
        let empty = focus.workspace
        empty.markAsAutomaticallyNamed()
        config.persistentWorkspaces = [empty.name]
        XCTAssertTrue(mainMonitor.setActiveWorkspace(empty))

        let destination = workspaceForNewTilingWindow(
            defaultWorkspace: empty,
            placement: .freshTab
        )

        XCTAssertFalse(destination === empty)
        XCTAssertEqual(
            orderedWorkspacesForPresentation().filter { !$0.isArchived }.map(\.name),
            [empty.name, destination.name]
        )
        XCTAssertTrue(mainMonitor.activeWorkspace === destination)
    }

    func testConsecutiveNewTilingWindowsCreateContiguousTabsInCurrentFolder() {
        let current = focus.workspace
        current.markAsAutomaticallyNamed()
        let folder = createWorkspaceFolder()
        current.assignProject(folder.projectId)
        _ = TestWindow.new(id: 36, parent: current.rootTilingContainer)
        XCTAssertTrue(mainMonitor.setActiveWorkspace(current))

        let first = workspaceForNewTilingWindow(defaultWorkspace: current, placement: .freshTab)
        _ = TestWindow.new(id: 37, parent: first.rootTilingContainer)
        let second = workspaceForNewTilingWindow(defaultWorkspace: first, placement: .freshTab)

        XCTAssertEqual(first.folderId, current.folderId)
        XCTAssertEqual(second.folderId, current.folderId)
        XCTAssertEqual(
            orderedWorkspaces(in: folder.projectId).filter { !$0.isArchived }.map(\.name),
            [current.name, first.name, second.name]
        )
        XCTAssertTrue(mainMonitor.activeWorkspace === second)
    }

    func testTargetWorkspacePlacementKeepsExistingTabForRelayout() {
        let occupied = focus.workspace
        occupied.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 35, parent: occupied.rootTilingContainer)
        XCTAssertTrue(mainMonitor.setActiveWorkspace(occupied))

        let destination = workspaceForNewTilingWindow(
            defaultWorkspace: occupied,
            placement: .targetWorkspace
        )

        XCTAssertTrue(destination === occupied)
        XCTAssertEqual(Workspace.all.filter { !$0.isArchived }.map(\.name), [occupied.name])
        XCTAssertTrue(mainMonitor.activeWorkspace === occupied)
    }

    func testNewWindowWithoutRectTargetsFocusedMonitorActiveTabOutsideStartup() {
        let activeWorkspace = Workspace.get(byName: "active-tab")
        let focusedWorkspace = Workspace.get(byName: "focused-tab")
        XCTAssertTrue(mainMonitor.setActiveWorkspace(activeWorkspace))

        let target = targetWorkspaceForNewWindow(
            isStartup: false,
            windowRect: nil,
            focusedWorkspace: focusedWorkspace,
        )

        XCTAssertTrue(target === activeWorkspace)
    }

    func testNewWindowWithoutRectCreatesTransientBlankTabWhenFocusedMonitorHasNoActiveTab() {
        let occupiedWorkspace = focus.workspace
        occupiedWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 33, parent: occupiedWorkspace.rootTilingContainer)
        XCTAssertTrue(mainMonitor.setActiveWorkspace(occupiedWorkspace))
        let viewportId = MonitorViewportId(mainMonitor)
        var viewport = winMuxWorkspaceState.monitorViewportsById[viewportId].orDie()
        viewport.activeWorkspaceId = nil
        winMuxWorkspaceState.monitorViewportsById[viewportId] = viewport

        let target = targetWorkspaceForNewWindow(
            isStartup: false,
            windowRect: nil,
            focusedWorkspace: occupiedWorkspace,
        )

        XCTAssertFalse(target === occupiedWorkspace)
        XCTAssertTrue(target.isEffectivelyEmpty)
        XCTAssertEqual(target.lifecycle, .transient)
        XCTAssertTrue(mainMonitor.activeWorkspace === target)
    }

    func testStartupNewWindowWithoutRectTargetsMainMonitorActiveWorkspace() {
        let startupWorkspace = Workspace.get(byName: "startup-tab")
        let focusedWorkspace = Workspace.get(byName: "focused-tab")
        XCTAssertTrue(mainMonitor.setActiveWorkspace(startupWorkspace))

        let target = targetWorkspaceForNewWindow(
            isStartup: true,
            windowRect: nil,
            focusedWorkspace: focusedWorkspace,
        )

        XCTAssertTrue(target === startupWorkspace)
    }

    func testNewWindowCreatesTransientBlankTabWhenMonitorHasNoActiveTab() {
        let occupiedWorkspace = focus.workspace
        occupiedWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 31, parent: occupiedWorkspace.rootTilingContainer)
        XCTAssertTrue(mainMonitor.setActiveWorkspace(occupiedWorkspace))
        let viewportId = MonitorViewportId(mainMonitor)
        var viewport = winMuxWorkspaceState.monitorViewportsById[viewportId].orDie()
        viewport.activeWorkspaceId = nil
        winMuxWorkspaceState.monitorViewportsById[viewportId] = viewport

        let target = targetWorkspaceForNewWindow(
            isStartup: false,
            windowRect: Rect(topLeftX: 100, topLeftY: 100, width: 800, height: 600),
            focusedWorkspace: occupiedWorkspace,
        )

        XCTAssertFalse(target === occupiedWorkspace)
        XCTAssertTrue(target.isEffectivelyEmpty)
        XCTAssertEqual(target.lifecycle, .transient)
        XCTAssertTrue(mainMonitor.activeWorkspace === target)
    }

    func testStartupNewWindowCreatesTransientBlankTabWhenMainMonitorHasNoActiveTab() {
        let focusedWorkspace = focus.workspace
        focusedWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 32, parent: focusedWorkspace.rootTilingContainer)
        XCTAssertTrue(mainMonitor.setActiveWorkspace(focusedWorkspace))
        let viewportId = MonitorViewportId(mainMonitor)
        var viewport = winMuxWorkspaceState.monitorViewportsById[viewportId].orDie()
        viewport.activeWorkspaceId = nil
        winMuxWorkspaceState.monitorViewportsById[viewportId] = viewport

        let target = targetWorkspaceForNewWindow(
            isStartup: true,
            windowRect: nil,
            focusedWorkspace: focusedWorkspace,
        )

        XCTAssertFalse(target === focusedWorkspace)
        XCTAssertTrue(target.isEffectivelyEmpty)
        XCTAssertEqual(target.lifecycle, .transient)
        XCTAssertTrue(mainMonitor.activeWorkspace === target)
    }

    private func emptyUserFacingWorkspaces(in projectId: WorkspaceProjectId) -> [Workspace] {
        userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace)
            .filter { $0.projectId == projectId && $0.isOrdinaryEmptySlot }
    }
}
