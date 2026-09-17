@testable import AppBundle
import Common
import CoreGraphics
import XCTest

@MainActor
final class WorkspaceSidebarReorderTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testWindowDropOnFolderCreatesTabInThatExactFolder() {
        let sourceWorkspace = focus.workspace
        let sourceWindow = TestWindow.new(id: 490, parent: sourceWorkspace.rootTilingContainer)
        let folder = createWorkspaceFolder()

        XCTAssertTrue(applySidebarSourceToNewWorkspace(
            sourceWindow.windowId,
            subject: .window,
            folderId: folder.id,
            monitorScopeId: workspaceSidebarDefaultScopeId
        ))

        XCTAssertEqual(sourceWindow.nodeWorkspace?.folderId, folder.id)
    }

    func testTabGroupDropOnFolderCreatesWholeTabInThatExactFolder() {
        let sourceWorkspace = focus.workspace
        let tabGroup = TilingContainer(
            parent: sourceWorkspace.rootTilingContainer,
            adaptiveWeight: WEIGHT_AUTO,
            .v,
            .tabGroup,
            index: INDEX_BIND_LAST
        )
        let first = TestWindow.new(id: 491, parent: tabGroup)
        let second = TestWindow.new(id: 492, parent: tabGroup)
        let folder = createWorkspaceFolder()

        XCTAssertTrue(applySidebarSourceToNewWorkspace(
            first.windowId,
            subject: .group,
            folderId: folder.id,
            monitorScopeId: workspaceSidebarDefaultScopeId
        ))

        XCTAssertEqual(first.nodeWorkspace?.folderId, folder.id)
        XCTAssertEqual(second.nodeWorkspace?.folderId, folder.id)
        XCTAssertTrue(first.parent === tabGroup)
        XCTAssertTrue(second.parent === tabGroup)
    }

    func testWorkspaceDragTargetKeepsLastValidSlotForTransientSidebarFrameMiss() {
        let stableTarget = WorkspaceSidebarWorkspaceDragTarget.reorder(
            WorkspaceSidebarWorkspaceReorderTarget(
                projectId: WorkspaceProjectId("destination-folder"),
                targetWorkspaceName: "middle",
                placement: .before("middle")
            )
        )

        XCTAssertEqual(
            workspaceSidebarStableWorkspaceDragTarget(
                currentTarget: stableTarget,
                candidateTarget: nil,
                isPointerInsideSidebar: true
            ),
            stableTarget
        )
        XCTAssertNil(workspaceSidebarStableWorkspaceDragTarget(
            currentTarget: stableTarget,
            candidateTarget: nil,
            isPointerInsideSidebar: false
        ))
    }

    func testWorkspaceDragFinishUsesFinalFrozenFrameTargetForFastRelease() {
        let initialTarget = WorkspaceSidebarWorkspaceDragTarget.reorder(
            WorkspaceSidebarWorkspaceReorderTarget(
                projectId: workspaceProjectDefaultId,
                targetWorkspaceName: "middle",
                placement: .before("middle")
            )
        )
        let finalTarget = WorkspaceSidebarWorkspaceDragTarget.reorder(
            WorkspaceSidebarWorkspaceReorderTarget(
                projectId: workspaceProjectDefaultId,
                targetWorkspaceName: "last",
                placement: .after("last")
            )
        )

        XCTAssertEqual(
            workspaceSidebarWorkspaceDragFinishTarget(
                finalCandidate: finalTarget,
                lastValidTarget: initialTarget,
                currentTarget: initialTarget,
                hasCanvasDropIntent: false
            ),
            finalTarget
        )
        XCTAssertNil(workspaceSidebarWorkspaceDragFinishTarget(
            finalCandidate: finalTarget,
            lastValidTarget: initialTarget,
            currentTarget: initialTarget,
            hasCanvasDropIntent: true
        ))
    }

    func testWorkspaceDragFolderExpansionFollowsLatestExactHoverTarget() {
        let middleFolderId = WorkspaceProjectId("folder-2")
        let destinationFolderId = WorkspaceProjectId("folder-3")
        let pacedMiddleTarget = WorkspaceSidebarWorkspaceDragTarget.moveToFolder(
            WorkspaceSidebarWorkspaceFolderTarget(
                projectId: middleFolderId,
                sourceWorkspaceName: "source"
            )
        )
        let exactDestinationTarget = WorkspaceSidebarWorkspaceDragTarget.moveToFolder(
            WorkspaceSidebarWorkspaceFolderTarget(
                projectId: destinationFolderId,
                sourceWorkspaceName: "source"
            )
        )
        let drag = WorkspaceSidebarWorkspaceReorderDragState(
            sourceWorkspaceName: "source",
            projectId: WorkspaceProjectId("folder-1"),
            target: pacedMiddleTarget,
            lastValidTarget: exactDestinationTarget
        )

        XCTAssertEqual(workspaceSidebarWorkspaceInteractionProjectId(drag), destinationFolderId)
    }

    func testSidebarWindowMoveCollapsesSourceFolderAndExpandsDestinationFolder() {
        let sourceFolder = createWorkspaceFolderWithWindow(windowId: 501)
        let destinationFolder = createWorkspaceFolderWithWindow(windowId: 502)
        let sourceWorkspace = Workspace.all.first { $0.folderId == sourceFolder.id }.orDie()
        let destinationWorkspace = Workspace.all.first { $0.folderId == destinationFolder.id }.orDie()
        let sourceWindow = Window.get(byId: 501).orDie()
        setWorkspaceSidebarFolderExpanded(sourceFolder.id, isExpanded: true)

        applySidebarWorkspaceMove(
            sourceNode: sourceWindow,
            sourceWindow: sourceWindow,
            targetWorkspace: destinationWorkspace
        )

        XCTAssertEqual(sourceWindow.nodeWorkspace, destinationWorkspace)
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(sourceFolder.id))
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(destinationFolder.id))
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(workspaceFolderDefaultId))
        XCTAssertNotEqual(sourceWorkspace, destinationWorkspace)
    }

    func testReorderWorkspaceMovesItemBeforeTarget() {
        let (first, second, third) = makeOrderedDefaultWorkspaces()

        XCTAssertTrue(reorderWorkspaceForSidebar(
            sourceWorkspaceName: third.name,
            projectId: workspaceProjectDefaultId,
            placement: .before(first.name)
        ))

        XCTAssertEqual(folderWorkspaces(folderId: workspaceFolderDefaultId).map(\.name), [
            third.name,
            first.name,
            second.name,
        ])
    }

    func testReorderWorkspaceMovesItemAfterTarget() {
        let (first, second, third) = makeOrderedDefaultWorkspaces()

        XCTAssertTrue(reorderWorkspaceForSidebar(
            sourceWorkspaceName: first.name,
            projectId: workspaceProjectDefaultId,
            placement: .after(second.name)
        ))

        XCTAssertEqual(folderWorkspaces(folderId: workspaceFolderDefaultId).map(\.name), [
            second.name,
            first.name,
            third.name,
        ])
    }

    func testReorderWorkspaceCanMoveToLastPosition() {
        let (first, second, third) = makeOrderedDefaultWorkspaces()

        XCTAssertTrue(reorderWorkspaceForSidebar(
            sourceWorkspaceName: first.name,
            projectId: workspaceProjectDefaultId,
            placement: .after(third.name)
        ))

        XCTAssertEqual(folderWorkspaces(folderId: workspaceFolderDefaultId).map(\.name), [
            second.name,
            third.name,
            first.name,
        ])
    }

    func testReorderWorkspaceSameTargetIsNoop() {
        let (first, second, third) = makeOrderedDefaultWorkspaces()

        XCTAssertFalse(reorderWorkspaceForSidebar(
            sourceWorkspaceName: second.name,
            projectId: workspaceProjectDefaultId,
            placement: .before(second.name)
        ))

        XCTAssertEqual(folderWorkspaces(folderId: workspaceFolderDefaultId).map(\.name), [
            first.name,
            second.name,
            third.name,
        ])
    }

    func testReorderWorkspaceMissingTargetIsNoop() {
        let (first, second, third) = makeOrderedDefaultWorkspaces()

        XCTAssertFalse(reorderWorkspaceForSidebar(
            sourceWorkspaceName: first.name,
            projectId: workspaceProjectDefaultId,
            placement: .after("missing")
        ))

        XCTAssertEqual(folderWorkspaces(folderId: workspaceFolderDefaultId).map(\.name), [
            first.name,
            second.name,
            third.name,
        ])
    }

    func testReorderWorkspaceCanMoveUnfoldedTabBeforeFolderTab() {
        let (first, second, third) = makeOrderedDefaultWorkspaces()
        let folder = createWorkspaceFolder()
        let folderWorkspace = Workspace.get(byName: "folder-tab")
        folderWorkspace.assignFolder(folder.id)
        folderWorkspace.markAsAutomaticallyNamed()
        setFolderWorkspaceOrder(folder.id, [folderWorkspace])

        XCTAssertTrue(reorderWorkspaceForSidebar(
            sourceWorkspaceName: first.name,
            folderId: folder.id,
            placement: .before(folderWorkspace.name)
        ))

        XCTAssertEqual(first.folderId, folder.id)
        XCTAssertEqual(folderWorkspaces(folderId: workspaceFolderDefaultId).map(\.name), [
            second.name,
            third.name,
        ])
        XCTAssertEqual(folderWorkspaces(folderId: folder.id).map(\.name), [
            first.name,
            folderWorkspace.name,
        ])
    }

    func testReorderWorkspaceChangesPresentationOrder() {
        let (first, second, third) = makeOrderedDefaultWorkspaces()

        XCTAssertTrue(reorderWorkspaceForSidebar(
            sourceWorkspaceName: third.name,
            projectId: workspaceProjectDefaultId,
            placement: .before(second.name)
        ))

        XCTAssertEqual(orderedWorkspacesForPresentation().map(\.name), [
            first.name,
            third.name,
            second.name,
        ])
    }

    func testReorderWorkspaceChangesPresentationOrderWhenProjectsDisabled() {
        config.enableProjects = false
        let (first, second, third) = makeOrderedDefaultWorkspaces()

        XCTAssertTrue(reorderWorkspaceForSidebar(
            sourceWorkspaceName: third.name,
            projectId: workspaceProjectDefaultId,
            placement: .before(second.name)
        ))

        XCTAssertEqual(orderedWorkspacesForPresentation().map(\.name), [
            first.name,
            third.name,
            second.name,
        ])
    }

    func testReorderWorkspaceRejectsCrossProjectMove() {
        let first = focus.workspace
        first.assignProject(workspaceProjectDefaultId)
        let project = createWorkspaceProject()
        let second = Workspace.all.first { $0.projectId == project.id }.orDie()
        second.markAsAutomaticallyNamed()
        let third = Workspace.get(byName: "third")
        third.assignProject(workspaceProjectDefaultId)
        third.markAsAutomaticallyNamed()
        setProjectWorkspaceOrder(workspaceProjectDefaultId, [first, third])
        setProjectWorkspaceOrder(project.id, [second])

        XCTAssertFalse(reorderWorkspaceForSidebar(
            sourceWorkspaceName: second.name,
            folderId: workspaceFolderDefaultId,
            placement: .before(third.name)
        ))

        XCTAssertEqual(folderWorkspaces(folderId: workspaceFolderDefaultId).map(\.name), [
            first.name,
            third.name,
        ])
        XCTAssertEqual(projectWorkspaces(projectId: project.id).map(\.name), [second.name])
    }

    func testWorkspaceSidebarModelRefreshUsesReorderedWorkspaceOrder() async {
        config.workspaceSidebar.enabled = true
        let (first, second, third) = makeOrderedDefaultWorkspaces()
        _ = TestWindow.new(id: 301, parent: first.rootTilingContainer)
        _ = TestWindow.new(id: 302, parent: second.rootTilingContainer)
        _ = TestWindow.new(id: 303, parent: third.rootTilingContainer)
        await updateWorkspaceSidebarModel()
        XCTAssertEqual(TrayMenuModel.shared.workspaceSidebarWorkspaces.map(\.name), [
            first.name,
            second.name,
            third.name,
        ])

        XCTAssertTrue(reorderWorkspaceForSidebar(
            sourceWorkspaceName: third.name,
            projectId: workspaceProjectDefaultId,
            placement: .before(second.name)
        ))
        await updateWorkspaceSidebarModel()

        XCTAssertEqual(TrayMenuModel.shared.workspaceSidebarWorkspaces.map(\.name), [
            first.name,
            third.name,
            second.name,
        ])
    }

    func testReorderWorkspacePreservesHiddenWorkspaceRelativeOrder() {
        let first = focus.workspace
        let hidden = Workspace.get(byName: "hidden")
        let second = Workspace.get(byName: "second")
        let third = Workspace.get(byName: "third")
        setDefaultWorkspaceOrder([first, hidden, second, third])

        XCTAssertTrue(reorderWorkspaceForSidebar(
            sourceWorkspaceName: third.name,
            projectId: workspaceProjectDefaultId,
            placement: .before(second.name)
        ))

        XCTAssertEqual(folderWorkspaces(folderId: workspaceFolderDefaultId).map(\.name), [
            first.name,
            hidden.name,
            third.name,
            second.name,
        ])
    }

    func testWorkspaceReorderTargetUsesVisibleFrameMidpoints() {
        let frames = [
            reorderFrame("first", minY: 10, height: 30),
            reorderFrame("second", minY: 50, height: 30),
            reorderFrame("third", minY: 90, height: 30),
        ]

        let beforeSecond = workspaceSidebarWorkspaceReorderTarget(
            sourceWorkspaceName: "third",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 12, y: 55),
            frames: frames
        )
        let afterSecond = workspaceSidebarWorkspaceReorderTarget(
            sourceWorkspaceName: "first",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 12, y: 115),
            frames: frames
        )

        XCTAssertEqual(beforeSecond?.placement, .before("second"))
        XCTAssertEqual(afterSecond?.placement, .after("third"))
    }

    func testWorkspaceDragTargetUsesWholeRowsAsStableReplacementTargets() {
        let frames = [
            reorderFrame("first", minY: 10, height: 40),
            reorderFrame("second", minY: 60, height: 40),
        ]

        let leftMiddleTarget = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "first",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 2, y: 78),
            workspaceFrames: frames
        )
        let rightMiddleTarget = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "first",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 198, y: 78),
            workspaceFrames: frames
        )
        let slightlyLeftTarget = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "first",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: -10, y: 78),
            workspaceFrames: frames
        )
        let slightlyRightTarget = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "first",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 210, y: 78),
            workspaceFrames: frames
        )
        let topBandTarget = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "first",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 100, y: 62),
            workspaceFrames: frames
        )
        let bottomBandTarget = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "first",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 100, y: 98),
            workspaceFrames: frames
        )
        let centerTarget = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "first",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 100, y: 80),
            workspaceFrames: frames
        )

        let expectedReplacementTarget = WorkspaceSidebarWorkspaceDragTarget.reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: workspaceProjectDefaultId,
            targetWorkspaceName: "second",
            placement: .after("second")
        ))
        XCTAssertEqual(leftMiddleTarget, expectedReplacementTarget)
        XCTAssertEqual(rightMiddleTarget, expectedReplacementTarget)
        XCTAssertEqual(slightlyLeftTarget, expectedReplacementTarget)
        XCTAssertEqual(slightlyRightTarget, expectedReplacementTarget)
        XCTAssertEqual(topBandTarget, expectedReplacementTarget)
        XCTAssertEqual(bottomBandTarget, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: workspaceProjectDefaultId,
            targetWorkspaceName: "second",
            placement: .after("second")
        )))
        XCTAssertEqual(centerTarget, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: workspaceProjectDefaultId,
            targetWorkspaceName: "second",
            placement: .after("second")
        )))

        let upwardReplacementTarget = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "second",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 100, y: 28),
            workspaceFrames: frames
        )
        XCTAssertEqual(upwardReplacementTarget, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: workspaceProjectDefaultId,
            targetWorkspaceName: "first",
            placement: .before("first")
        )))
    }

    func testWorkspaceDragTargetLeavesSourceSlotUnprojected() {
        let frames = [
            reorderFrame("first", minY: 10, height: 40),
            reorderFrame("second", minY: 60, height: 40),
            reorderFrame("third", minY: 110, height: 40),
        ]

        let gapBeforeSource = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "second",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 100, y: 55),
            workspaceFrames: frames
        )
        let gapAfterSource = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "second",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 100, y: 105),
            workspaceFrames: frames
        )
        let realMoveUp = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "second",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 100, y: 12),
            workspaceFrames: frames
        )
        let realMoveDown = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "second",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 100, y: 148),
            workspaceFrames: frames
        )

        XCTAssertNil(gapBeforeSource)
        XCTAssertNil(gapAfterSource)
        XCTAssertEqual(realMoveUp, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: workspaceProjectDefaultId,
            targetWorkspaceName: "first",
            placement: .before("first")
        )))
        XCTAssertEqual(realMoveDown, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: workspaceProjectDefaultId,
            targetWorkspaceName: "third",
            placement: .after("third")
        )))
    }

    func testWorkspaceDragTargetDoesNotProjectLastTabWhilePointerIsStillOnIt() {
        let frames = [
            reorderFrame("first", minY: 10, height: 40),
            reorderFrame("second", minY: 60, height: 40),
            reorderFrame("third", minY: 110, height: 40),
            reorderFrame("fourth", minY: 160, height: 40),
        ]

        let sourceTop = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "fourth",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 100, y: 165),
            workspaceFrames: frames
        )
        let sourceBottom = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "fourth",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 100, y: 195),
            workspaceFrames: frames
        )
        let sourceGap = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "fourth",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 100, y: 155),
            workspaceFrames: frames
        )
        let thirdRow = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "fourth",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 100, y: 145),
            workspaceFrames: frames
        )

        XCTAssertNil(sourceTop)
        XCTAssertNil(sourceBottom)
        XCTAssertNil(sourceGap)
        XCTAssertEqual(thirdRow, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: workspaceProjectDefaultId,
            targetWorkspaceName: "third",
            placement: .before("third")
        )))
    }

    func testWorkspaceDragTargetDoesNotLeakIntoPreviousFolderFromInterFolderGap() {
        let firstFolderId = WorkspaceProjectId("project-first-folder")
        let secondFolderId = WorkspaceProjectId("project-second-folder")
        let frames = [
            reorderFrame("first-folder-tab", minY: 60, height: 40, projectId: firstFolderId),
            reorderFrame("second-folder-first-tab", minY: 150, height: 40, projectId: secondFolderId),
            reorderFrame("second-folder-tab", minY: 194, height: 40, projectId: secondFolderId),
        ]
        let folderFrames = [
            folderFrame(firstFolderId, minY: 52, height: 56),
            folderFrame(secondFolderId, minY: 144, height: 96),
        ]

        let target = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "second-folder-tab",
            sourceProjectId: secondFolderId,
            pointer: CGPoint(x: 100, y: 125),
            workspaceFrames: frames,
            folderFrames: folderFrames
        )

        XCTAssertNil(target)
    }

    func testWorkspaceDragTargetUsesSourceFolderTopGapAsFirstSlot() {
        let folderId = WorkspaceProjectId("project-folder")
        let frames = [
            reorderFrame("first-tab", minY: 302, height: 32, projectId: folderId),
            reorderFrame("dragged-tab", minY: 336, height: 32, projectId: folderId),
            reorderFrame("last-tab", minY: 370, height: 32, projectId: folderId),
        ]
        let folderFrames = [
            folderFrame(folderId, minY: 265, height: 170),
        ]

        let topGapTarget = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "dragged-tab",
            sourceProjectId: folderId,
            pointer: CGPoint(x: 100, y: 290),
            workspaceFrames: frames,
            folderFrames: folderFrames
        )
        let firstRowBandTarget = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "dragged-tab",
            sourceProjectId: folderId,
            pointer: CGPoint(x: 100, y: 304),
            workspaceFrames: frames,
            folderFrames: folderFrames
        )

        XCTAssertEqual(topGapTarget, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: folderId,
            targetWorkspaceName: "first-tab",
            placement: .before("first-tab")
        )))
        XCTAssertEqual(firstRowBandTarget, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: folderId,
            targetWorkspaceName: "first-tab",
            placement: .before("first-tab")
        )))
    }

    func testWorkspaceDragTargetUsesSourceFolderGapBetweenTabsAsInsertionSlot() {
        let folderId = WorkspaceProjectId("project-folder")
        let frames = [
            reorderFrame("first-tab", minY: 302, height: 32, projectId: folderId),
            reorderFrame("second-tab", minY: 348, height: 32, projectId: folderId),
            reorderFrame("dragged-tab", minY: 394, height: 32, projectId: folderId),
        ]
        let folderFrames = [
            folderFrame(folderId, minY: 265, height: 180),
        ]

        let gapTarget = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "dragged-tab",
            sourceProjectId: folderId,
            pointer: CGPoint(x: 100, y: 340),
            workspaceFrames: frames,
            folderFrames: folderFrames
        )
        let rowBandTarget = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "dragged-tab",
            sourceProjectId: folderId,
            pointer: CGPoint(x: 100, y: 350),
            workspaceFrames: frames,
            folderFrames: folderFrames
        )

        XCTAssertEqual(gapTarget, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: folderId,
            targetWorkspaceName: "second-tab",
            placement: .before("second-tab")
        )))
        XCTAssertEqual(rowBandTarget, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: folderId,
            targetWorkspaceName: "second-tab",
            placement: .before("second-tab")
        )))
    }

    func testWorkspaceDragTargetStillMovesAcrossFoldersWhenPointerIsOnTargetRow() {
        let firstFolderId = WorkspaceProjectId("project-first-folder")
        let secondFolderId = WorkspaceProjectId("project-second-folder")
        let frames = [
            reorderFrame("first-folder-tab", minY: 60, height: 40, projectId: firstFolderId),
            reorderFrame("second-folder-tab", minY: 150, height: 40, projectId: secondFolderId),
        ]
        let folderFrames = [
            folderFrame(firstFolderId, minY: 52, height: 56),
            folderFrame(secondFolderId, minY: 144, height: 56),
        ]

        let target = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "second-folder-tab",
            sourceProjectId: secondFolderId,
            pointer: CGPoint(x: 100, y: 62),
            workspaceFrames: frames,
            folderFrames: folderFrames
        )

        XCTAssertEqual(target, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: firstFolderId,
            targetWorkspaceName: "first-folder-tab",
            placement: .before("first-folder-tab")
        )))
    }

    func testWorkspaceDragPreviewAdvancesDownOneInsertionSlotPerRenderBeat() {
        let firstFolderId = WorkspaceProjectId("project-first-folder")
        let secondFolderId = WorkspaceProjectId("project-second-folder")
        let frames = [
            reorderFrame("1.1", minY: 10, height: 32, projectId: firstFolderId),
            reorderFrame("1.2", minY: 46, height: 32, projectId: firstFolderId),
            reorderFrame("1.3", minY: 82, height: 32, projectId: firstFolderId),
            reorderFrame("1.4", minY: 118, height: 32, projectId: firstFolderId),
            reorderFrame("2.1", minY: 180, height: 32, projectId: secondFolderId),
            reorderFrame("2.2", minY: 216, height: 32, projectId: secondFolderId),
        ]
        let crossFolderTarget = WorkspaceSidebarWorkspaceDragTarget.reorder(
            WorkspaceSidebarWorkspaceReorderTarget(
                projectId: secondFolderId,
                targetWorkspaceName: "2.2",
                placement: .after("2.2")
            )
        )
        let folderFrames = [
            folderFrame(firstFolderId, minY: 0, height: 160),
            folderFrame(secondFolderId, minY: 170, height: 90),
        ]
        var previewTarget: WorkspaceSidebarWorkspaceDragTarget?
        var renderedTargets: [WorkspaceSidebarWorkspaceDragTarget?] = []
        for _ in 0 ..< 6 {
            previewTarget = workspaceSidebarWorkspaceAdjacentPreviewTarget(
                currentTarget: previewTarget,
                desiredTarget: crossFolderTarget,
                sourceWorkspaceName: "1.1",
                sourceProjectId: firstFolderId,
                frames: frames,
                folderFrames: folderFrames
            )
            renderedTargets.append(previewTarget)
        }

        XCTAssertEqual(renderedTargets, [
            reorderTarget(firstFolderId, "1.2", .after("1.2")),
            reorderTarget(firstFolderId, "1.3", .after("1.3")),
            reorderTarget(firstFolderId, "1.4", .after("1.4")),
            reorderTarget(secondFolderId, "2.1", .before("2.1")),
            reorderTarget(secondFolderId, "2.1", .after("2.1")),
            reorderTarget(secondFolderId, "2.2", .after("2.2")),
        ])
    }

    func testWorkspaceDragPreviewAdvancesUpOneInsertionSlotPerRenderBeat() {
        let firstFolderId = WorkspaceProjectId("project-first-folder")
        let secondFolderId = WorkspaceProjectId("project-second-folder")
        let frames = [
            reorderFrame("1.1", minY: 10, height: 32, projectId: firstFolderId),
            reorderFrame("1.2", minY: 46, height: 32, projectId: firstFolderId),
            reorderFrame("1.3", minY: 82, height: 32, projectId: firstFolderId),
            reorderFrame("1.4", minY: 118, height: 32, projectId: firstFolderId),
            reorderFrame("2.1", minY: 180, height: 32, projectId: secondFolderId),
            reorderFrame("2.2", minY: 216, height: 32, projectId: secondFolderId),
        ]
        let folderFrames = [
            folderFrame(firstFolderId, minY: 0, height: 160),
            folderFrame(secondFolderId, minY: 170, height: 90),
        ]
        let finalTarget = reorderTarget(firstFolderId, "1.1", .before("1.1"))
        var previewTarget: WorkspaceSidebarWorkspaceDragTarget?
        var renderedTargets: [WorkspaceSidebarWorkspaceDragTarget?] = []
        for _ in 0 ..< 6 {
            previewTarget = workspaceSidebarWorkspaceAdjacentPreviewTarget(
                currentTarget: previewTarget,
                desiredTarget: finalTarget,
                sourceWorkspaceName: "2.2",
                sourceProjectId: secondFolderId,
                frames: frames,
                folderFrames: folderFrames
            )
            renderedTargets.append(previewTarget)
        }

        XCTAssertEqual(renderedTargets, [
            reorderTarget(secondFolderId, "2.1", .before("2.1")),
            reorderTarget(firstFolderId, "1.4", .after("1.4")),
            reorderTarget(firstFolderId, "1.3", .after("1.3")),
            reorderTarget(firstFolderId, "1.2", .after("1.2")),
            reorderTarget(firstFolderId, "1.1", .after("1.1")),
            reorderTarget(firstFolderId, "1.1", .before("1.1")),
        ])
    }

    func testWorkspaceDragPreviewHoldsEverySiblingSlotLongEnoughToRender() {
        let firstFolderId = WorkspaceProjectId("project-first-folder")
        let secondFolderId = WorkspaceProjectId("project-second-folder")
        let frames = [
            reorderFrame("1.1", minY: 10, height: 32, projectId: firstFolderId),
            reorderFrame("1.2", minY: 46, height: 32, projectId: firstFolderId),
            reorderFrame("1.3", minY: 82, height: 32, projectId: firstFolderId),
            reorderFrame("1.4", minY: 118, height: 32, projectId: firstFolderId),
            reorderFrame("2.1", minY: 180, height: 32, projectId: secondFolderId),
            reorderFrame("2.2", minY: 216, height: 32, projectId: secondFolderId),
        ]
        let folderFrames = [
            folderFrame(firstFolderId, minY: 0, height: 160),
            folderFrame(secondFolderId, minY: 170, height: 90),
        ]
        let finalTarget = reorderTarget(secondFolderId, "2.2", .after("2.2"))

        let firstStep = workspaceSidebarWorkspacePacedPreviewResolution(
            currentTarget: nil,
            desiredTarget: finalTarget,
            nextPreviewStepAt: nil,
            now: 10,
            stepInterval: 0.1,
            sourceWorkspaceName: "1.1",
            sourceProjectId: firstFolderId,
            frames: frames,
            folderFrames: folderFrames
        )
        XCTAssertEqual(firstStep.target, reorderTarget(firstFolderId, "1.2", .after("1.2")))
        XCTAssertEqual(firstStep.nextPreviewStepAt ?? .nan, 10.1, accuracy: 0.000_001)

        let heldStep = workspaceSidebarWorkspacePacedPreviewResolution(
            currentTarget: firstStep.target,
            desiredTarget: finalTarget,
            nextPreviewStepAt: firstStep.nextPreviewStepAt,
            now: 10.05,
            stepInterval: 0.1,
            sourceWorkspaceName: "1.1",
            sourceProjectId: firstFolderId,
            frames: frames,
            folderFrames: folderFrames
        )
        XCTAssertEqual(heldStep.target, firstStep.target)
        XCTAssertEqual(heldStep.nextPreviewStepAt, firstStep.nextPreviewStepAt)

        let secondStep = workspaceSidebarWorkspacePacedPreviewResolution(
            currentTarget: heldStep.target,
            desiredTarget: finalTarget,
            nextPreviewStepAt: heldStep.nextPreviewStepAt,
            now: 10.1,
            stepInterval: 0.1,
            sourceWorkspaceName: "1.1",
            sourceProjectId: firstFolderId,
            frames: frames,
            folderFrames: folderFrames
        )
        XCTAssertEqual(secondStep.target, reorderTarget(firstFolderId, "1.3", .after("1.3")))
        XCTAssertEqual(secondStep.nextPreviewStepAt ?? .nan, 10.2, accuracy: 0.000_001)
    }

    func testWorkspaceDragPreviewReversesOneSiblingAtATimeWithoutFlashingHome() {
        let folderId = WorkspaceProjectId("project-folder")
        let frames = [
            reorderFrame("1.1", minY: 10, height: 32, projectId: folderId),
            reorderFrame("1.2", minY: 46, height: 32, projectId: folderId),
            reorderFrame("1.3", minY: 82, height: 32, projectId: folderId),
            reorderFrame("1.4", minY: 118, height: 32, projectId: folderId),
        ]
        let farTarget = reorderTarget(folderId, "1.4", .after("1.4"))
        let outward = workspaceSidebarWorkspacePacedPreviewResolution(
            currentTarget: nil,
            desiredTarget: farTarget,
            nextPreviewStepAt: nil,
            now: 20,
            stepInterval: 0.1,
            sourceWorkspaceName: "1.1",
            sourceProjectId: folderId,
            frames: frames
        )
        XCTAssertEqual(outward.target, reorderTarget(folderId, "1.2", .after("1.2")))

        let heldOnReverse = workspaceSidebarWorkspacePacedPreviewResolution(
            currentTarget: outward.target,
            desiredTarget: nil,
            nextPreviewStepAt: outward.nextPreviewStepAt,
            now: 20.05,
            stepInterval: 0.1,
            sourceWorkspaceName: "1.1",
            sourceProjectId: folderId,
            frames: frames
        )
        XCTAssertEqual(heldOnReverse.target, outward.target)

        let returnedOneSlot = workspaceSidebarWorkspacePacedPreviewResolution(
            currentTarget: heldOnReverse.target,
            desiredTarget: nil,
            nextPreviewStepAt: heldOnReverse.nextPreviewStepAt,
            now: 20.1,
            stepInterval: 0.1,
            sourceWorkspaceName: "1.1",
            sourceProjectId: folderId,
            frames: frames
        )
        XCTAssertNil(returnedOneSlot.target)
        XCTAssertEqual(returnedOneSlot.nextPreviewStepAt ?? .nan, 20.2, accuracy: 0.000_001)
    }

    func testWorkspaceDragPreviewKeepsItsGateUntilTheVisibleTransitionCompletes() {
        let folderId = WorkspaceProjectId("project-folder")
        let frames = [
            reorderFrame("1.1", minY: 10, height: 32, projectId: folderId),
            reorderFrame("1.2", minY: 46, height: 32, projectId: folderId),
            reorderFrame("1.3", minY: 82, height: 32, projectId: folderId),
        ]
        let adjacentTarget = reorderTarget(folderId, "1.2", .after("1.2"))
        let firstStep = workspaceSidebarWorkspacePacedPreviewResolution(
            currentTarget: nil,
            desiredTarget: adjacentTarget,
            nextPreviewStepAt: nil,
            now: 30,
            stepInterval: 0.1,
            sourceWorkspaceName: "1.1",
            sourceProjectId: folderId,
            frames: frames
        )
        let caughtUp = workspaceSidebarWorkspacePacedPreviewResolution(
            currentTarget: firstStep.target,
            desiredTarget: adjacentTarget,
            nextPreviewStepAt: firstStep.nextPreviewStepAt,
            now: 30.05,
            stepInterval: 0.1,
            sourceWorkspaceName: "1.1",
            sourceProjectId: folderId,
            frames: frames
        )
        XCTAssertEqual(caughtUp.target, adjacentTarget)
        XCTAssertEqual(caughtUp.nextPreviewStepAt, firstStep.nextPreviewStepAt)

        let settled = workspaceSidebarWorkspacePacedPreviewResolution(
            currentTarget: caughtUp.target,
            desiredTarget: adjacentTarget,
            nextPreviewStepAt: caughtUp.nextPreviewStepAt,
            now: 30.1,
            stepInterval: 0.1,
            sourceWorkspaceName: "1.1",
            sourceProjectId: folderId,
            frames: frames
        )
        XCTAssertEqual(settled.target, adjacentTarget)
        XCTAssertNil(settled.nextPreviewStepAt)
    }

    func testWorkspaceDragPreviewDoesNotStartTheNextSiblingBeforeTheCurrentTransitionCompletes() {
        let folderId = WorkspaceProjectId("project-folder")
        let frames = [
            reorderFrame("1.1", minY: 10, height: 32, projectId: folderId),
            reorderFrame("1.2", minY: 46, height: 32, projectId: folderId),
            reorderFrame("1.3", minY: 82, height: 32, projectId: folderId),
        ]
        let firstTarget = reorderTarget(folderId, "1.2", .after("1.2"))
        let secondTarget = reorderTarget(folderId, "1.3", .after("1.3"))
        let firstStep = workspaceSidebarWorkspacePacedPreviewResolution(
            currentTarget: nil,
            desiredTarget: firstTarget,
            nextPreviewStepAt: nil,
            now: 40,
            stepInterval: 0.05,
            sourceWorkspaceName: "1.1",
            sourceProjectId: folderId,
            frames: frames
        )

        let heldForCurrentSibling = workspaceSidebarWorkspacePacedPreviewResolution(
            currentTarget: firstStep.target,
            desiredTarget: secondTarget,
            nextPreviewStepAt: firstStep.nextPreviewStepAt,
            now: 40.04,
            stepInterval: 0.05,
            sourceWorkspaceName: "1.1",
            sourceProjectId: folderId,
            frames: frames
        )
        XCTAssertEqual(heldForCurrentSibling.target, firstTarget)

        let nextSibling = workspaceSidebarWorkspacePacedPreviewResolution(
            currentTarget: heldForCurrentSibling.target,
            desiredTarget: secondTarget,
            nextPreviewStepAt: heldForCurrentSibling.nextPreviewStepAt,
            now: 40.05,
            stepInterval: 0.05,
            sourceWorkspaceName: "1.1",
            sourceProjectId: folderId,
            frames: frames
        )
        XCTAssertEqual(nextSibling.target, secondTarget)
        XCTAssertLessThan(
            workspaceSidebarWorkspacePreviewTransitionDuration,
            workspaceSidebarWorkspacePreviewStepInterval
        )
    }

    func testWorkspaceDragPreviewReplaysEveryCrossFolderSlotInBothDirections() {
        let firstFolderId = WorkspaceProjectId("project-first-folder")
        let secondFolderId = WorkspaceProjectId("project-second-folder")
        let frames = [
            reorderFrame("1.1", minY: 10, height: 32, projectId: firstFolderId),
            reorderFrame("1.2", minY: 46, height: 32, projectId: firstFolderId),
            reorderFrame("1.3", minY: 82, height: 32, projectId: firstFolderId),
            reorderFrame("1.4", minY: 118, height: 32, projectId: firstFolderId),
            reorderFrame("2.1", minY: 180, height: 32, projectId: secondFolderId),
            reorderFrame("2.2", minY: 216, height: 32, projectId: secondFolderId),
        ]
        let folderFrames = [
            folderFrame(firstFolderId, minY: 0, height: 160),
            folderFrame(secondFolderId, minY: 170, height: 90),
        ]

        func pacedTargets(
            sourceWorkspaceName: String,
            sourceProjectId: WorkspaceProjectId,
            desiredTarget: WorkspaceSidebarWorkspaceDragTarget,
            stepCount: Int
        ) -> [WorkspaceSidebarWorkspaceDragTarget?] {
            var target: WorkspaceSidebarWorkspaceDragTarget?
            var nextStepAt: TimeInterval?
            var now: TimeInterval = 100
            return (0 ..< stepCount).map { _ in
                let resolution = workspaceSidebarWorkspacePacedPreviewResolution(
                    currentTarget: target,
                    desiredTarget: desiredTarget,
                    nextPreviewStepAt: nextStepAt,
                    now: now,
                    stepInterval: 0.1,
                    sourceWorkspaceName: sourceWorkspaceName,
                    sourceProjectId: sourceProjectId,
                    frames: frames,
                    folderFrames: folderFrames
                )
                target = resolution.target
                nextStepAt = resolution.nextPreviewStepAt
                now += 0.1
                return target
            }
        }

        XCTAssertEqual(pacedTargets(
            sourceWorkspaceName: "1.1",
            sourceProjectId: firstFolderId,
            desiredTarget: reorderTarget(secondFolderId, "2.2", .after("2.2")),
            stepCount: 6
        ), [
            reorderTarget(firstFolderId, "1.2", .after("1.2")),
            reorderTarget(firstFolderId, "1.3", .after("1.3")),
            reorderTarget(firstFolderId, "1.4", .after("1.4")),
            reorderTarget(secondFolderId, "2.1", .before("2.1")),
            reorderTarget(secondFolderId, "2.1", .after("2.1")),
            reorderTarget(secondFolderId, "2.2", .after("2.2")),
        ])

        XCTAssertEqual(pacedTargets(
            sourceWorkspaceName: "2.2",
            sourceProjectId: secondFolderId,
            desiredTarget: reorderTarget(firstFolderId, "1.1", .before("1.1")),
            stepCount: 6
        ), [
            reorderTarget(secondFolderId, "2.1", .before("2.1")),
            reorderTarget(firstFolderId, "1.4", .after("1.4")),
            reorderTarget(firstFolderId, "1.3", .after("1.3")),
            reorderTarget(firstFolderId, "1.2", .after("1.2")),
            reorderTarget(firstFolderId, "1.1", .after("1.1")),
            reorderTarget(firstFolderId, "1.1", .before("1.1")),
        ])
    }

    func testWorkspaceDragTargetKeepsConcreteCrossFolderDestinationInBothDirections() {
        let firstFolderId = WorkspaceProjectId("project-first-folder")
        let secondFolderId = WorkspaceProjectId("project-second-folder")
        let frames = [
            reorderFrame("1.1", minY: 10, height: 32, projectId: firstFolderId),
            reorderFrame("1.2", minY: 46, height: 32, projectId: firstFolderId),
            reorderFrame("1.3", minY: 82, height: 32, projectId: firstFolderId),
            reorderFrame("1.4", minY: 118, height: 32, projectId: firstFolderId),
            reorderFrame("2.1", minY: 180, height: 32, projectId: secondFolderId),
            reorderFrame("2.2", minY: 216, height: 32, projectId: secondFolderId),
        ]
        let folderFrames = [
            folderFrame(firstFolderId, minY: 0, height: 160),
            folderFrame(secondFolderId, minY: 170, height: 90),
        ]

        let intoSecondFolder = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "1.1",
            sourceProjectId: firstFolderId,
            pointer: CGPoint(x: 100, y: 240),
            workspaceFrames: frames,
            folderFrames: folderFrames
        )
        let intoFirstFolder = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "2.2",
            sourceProjectId: secondFolderId,
            pointer: CGPoint(x: 100, y: 16),
            workspaceFrames: frames,
            folderFrames: folderFrames
        )

        XCTAssertEqual(intoSecondFolder, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: secondFolderId,
            targetWorkspaceName: "2.2",
            placement: .after("2.2")
        )))
        XCTAssertEqual(intoFirstFolder, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: firstFolderId,
            targetWorkspaceName: "1.1",
            placement: .before("1.1")
        )))
    }

    func testWorkspaceDragTargetMapsEveryCrossedDestinationRowWithoutSkipping() {
        let firstFolderId = WorkspaceProjectId("project-first-folder")
        let secondFolderId = WorkspaceProjectId("project-second-folder")
        let frames = [
            reorderFrame("1.1", minY: 10, height: 32, projectId: firstFolderId),
            reorderFrame("1.2", minY: 46, height: 32, projectId: firstFolderId),
            reorderFrame("1.3", minY: 82, height: 32, projectId: firstFolderId),
            reorderFrame("1.4", minY: 118, height: 32, projectId: firstFolderId),
            reorderFrame("2.1", minY: 180, height: 32, projectId: secondFolderId),
            reorderFrame("2.2", minY: 216, height: 32, projectId: secondFolderId),
        ]
        let folderFrames = [
            folderFrame(firstFolderId, minY: 0, height: 160),
            folderFrame(secondFolderId, minY: 170, height: 90),
        ]

        let targets = ["1.4", "1.3", "1.2", "1.1"].enumerated().map { index, name in
            workspaceSidebarWorkspaceDragTarget(
                sourceWorkspaceName: "2.2",
                sourceProjectId: secondFolderId,
                pointer: CGPoint(x: 100, y: CGFloat(128 - (index * 36))),
                workspaceFrames: frames,
                folderFrames: folderFrames
            ).map { target in
                switch target {
                    case .reorder(let reorderTarget): reorderTarget.targetWorkspaceName
                    case .moveToFolder: "folder"
                }
            }
        }

        XCTAssertEqual(targets, ["1.4", "1.3", "1.2", "1.1"])
    }

    func testWorkspaceDragTargetDoesNotCreateFolderFromHorizontalEdge() {
        let frames = [
            reorderFrame("first", minY: 10, height: 40),
            reorderFrame("second", minY: 60, height: 40),
        ]

        let target = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "first",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 0.5, y: 80),
            workspaceFrames: frames
        )

        XCTAssertEqual(target, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: workspaceProjectDefaultId,
            targetWorkspaceName: "second",
            placement: .after("second")
        )))
    }

    func testWorkspaceDragTargetUsesFolderHeaderForTopInsertionIntoFolder() {
        let folderId = WorkspaceProjectId("project-folder")
        let workspaceFrames = [
            reorderFrame("flat", minY: 10, height: 40),
            reorderFrame("folder-child", minY: 90, height: 40, projectId: folderId),
        ]
        let folderFrames = [
            folderFrame(folderId, minY: 54, height: 32),
        ]

        let target = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "flat",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 20, y: 70),
            workspaceFrames: workspaceFrames,
            folderFrames: folderFrames
        )

        XCTAssertEqual(target, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: folderId,
            targetWorkspaceName: "folder-child",
            placement: .before("folder-child")
        )))
    }

    func testWorkspaceDragTargetUsesFolderBodyForMovingTabIntoFolder() {
        let folderId = WorkspaceProjectId("project-folder")
        let workspaceFrames = [
            reorderFrame("flat", minY: 10, height: 40),
            reorderFrame("folder-child", minY: 90, height: 40, projectId: folderId),
        ]
        let folderFrames = [
            folderFrame(folderId, minY: 54, height: 140),
        ]

        let target = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "flat",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 20, y: 172),
            workspaceFrames: workspaceFrames,
            folderFrames: folderFrames
        )

        XCTAssertEqual(target, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: folderId,
            targetWorkspaceName: "folder-child",
            placement: .after("folder-child")
        )))
    }

    func testWorkspaceDragTargetPrefersFolderChildRowInsertionOverFolderHeader() {
        let folderId = WorkspaceProjectId("project-folder")
        let workspaceFrames = [
            reorderFrame("flat", minY: 10, height: 40),
            reorderFrame("folder-child", minY: 90, height: 40, projectId: folderId),
        ]
        let folderFrames = [
            folderFrame(folderId, minY: 54, height: 100),
        ]

        let target = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "flat",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 20, y: 94),
            workspaceFrames: workspaceFrames,
            folderFrames: folderFrames
        )

        XCTAssertEqual(target, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: folderId,
            targetWorkspaceName: "folder-child",
            placement: .before("folder-child")
        )))
    }

    func testWorkspaceDragTargetPrefersFolderHeaderOverFlatRowWhenHeaderOverlaps() {
        let folderId = WorkspaceProjectId("project-folder")
        let workspaceFrames = [
            reorderFrame("flat", minY: 54, height: 40),
        ]
        let folderFrames = [
            folderFrame(folderId, minY: 54, height: 32),
        ]

        let target = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "flat",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 20, y: 70),
            workspaceFrames: workspaceFrames,
            folderFrames: folderFrames
        )

        XCTAssertEqual(target, .moveToFolder(WorkspaceSidebarWorkspaceFolderTarget(
            projectId: folderId,
            sourceWorkspaceName: "flat"
        )))
    }

    func testWorkspaceDragTargetRejectsFolderChildOutToFlatRootRowBand() {
        let folderId = WorkspaceProjectId("project-folder")
        let frames = [
            reorderFrame("flat", minY: 10, height: 40),
            reorderFrame("folder-child", minY: 60, height: 40, projectId: folderId),
        ]

        let target = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "folder-child",
            sourceProjectId: folderId,
            pointer: CGPoint(x: 100, y: 12),
            workspaceFrames: frames
        )

        XCTAssertNil(target)
    }

    func testWorkspaceDragTargetDoesNotUseEmptyDefaultRootDropAreaWhenRootListIsEmpty() {
        let folderId = WorkspaceProjectId("project-folder")
        let frames = [
            reorderFrame("folder-child", minY: 60, height: 40, projectId: folderId),
        ]
        let defaultIsDropTarget = workspaceSidebarProjectFrameIsVisibleDropTarget(
            projectId: workspaceProjectDefaultId,
            sourceProjectId: folderId
        )
        let folderFrames = [
            folderFrame(workspaceProjectDefaultId, minY: 10, height: 32, isDropTarget: defaultIsDropTarget),
            folderFrame(folderId, minY: 54, height: 120),
        ]

        let target = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "folder-child",
            sourceProjectId: folderId,
            pointer: CGPoint(x: 100, y: 20),
            workspaceFrames: frames,
            folderFrames: folderFrames
        )

        XCTAssertFalse(defaultIsDropTarget)
        XCTAssertNil(target)
    }

    func testWorkspaceDragFinishActionMapsReorderTargetToSidebarAction() {
        let folderId = WorkspaceProjectId("project-folder")
        let target = WorkspaceSidebarWorkspaceDragTarget.reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: workspaceProjectDefaultId,
            targetWorkspaceName: "flat",
            placement: .before("flat")
        ))

        let action = workspaceSidebarWorkspaceDragFinishAction(
            sourceWorkspaceName: "folder-child",
            target: target
        )

        XCTAssertEqual(action, .reorderWorkspace(
            "folder-child",
            folderId: WorkspaceFolderId(workspaceProjectDefaultId),
            placement: .before("flat")
        ))
        XCTAssertNotEqual(folderId, workspaceProjectDefaultId)
    }

    func testWorkspaceDragTargetRejectsFolderChildOutToFlatRootRowCenterDrop() {
        let folderId = WorkspaceProjectId("project-folder")
        let frames = [
            reorderFrame("flat", minY: 10, height: 40),
            reorderFrame("folder-child", minY: 60, height: 40, projectId: folderId),
        ]

        let target = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "folder-child",
            sourceProjectId: folderId,
            pointer: CGPoint(x: 100, y: 30),
            workspaceFrames: frames
        )

        XCTAssertNil(target)
    }

    func testWorkspaceDragTargetCanMoveFolderChildIntoVisibleUnfoldedFolderRow() {
        let folderId = WorkspaceProjectId("project-folder")
        let frames = [
            reorderFrame("unfolded-tab", minY: 10, height: 40),
            reorderFrame("folder-child", minY: 80, height: 40, projectId: folderId),
        ]
        let folderFrames = [
            folderFrame(workspaceProjectDefaultId, minY: 2, height: 56),
            folderFrame(folderId, minY: 72, height: 56),
        ]

        let target = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "folder-child",
            sourceProjectId: folderId,
            pointer: CGPoint(x: 100, y: 12),
            workspaceFrames: frames,
            folderFrames: folderFrames
        )

        XCTAssertEqual(target, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: workspaceProjectDefaultId,
            targetWorkspaceName: "unfolded-tab",
            placement: .before("unfolded-tab")
        )))
    }

    func testWorkspaceDragTargetDoesNotCreateNestedFolderFromFolderChildCenterDrop() {
        let folderId = WorkspaceProjectId("project-folder")
        let frames = [
            reorderFrame("folder-child", minY: 10, height: 40, projectId: folderId),
            reorderFrame("folder-sibling", minY: 60, height: 40, projectId: folderId),
        ]

        let target = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "folder-child",
            sourceProjectId: folderId,
            pointer: CGPoint(x: 100, y: 80),
            workspaceFrames: frames
        )

        XCTAssertEqual(target, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: folderId,
            targetWorkspaceName: "folder-sibling",
            placement: .after("folder-sibling")
        )))
    }

    func testFolderReorderTargetUsesFolderFrames() {
        let sourceId = WorkspaceProjectId("project-source")
        let firstId = WorkspaceProjectId("project-first")
        let secondId = WorkspaceProjectId("project-second")
        let frames = [
            folderFrame(workspaceProjectDefaultId, minY: 0, height: 40),
            folderFrame(firstId, minY: 50, height: 50),
            folderFrame(sourceId, minY: 110, height: 50),
            folderFrame(secondId, minY: 170, height: 50),
        ]

        let beforeFirst = workspaceSidebarFolderReorderTarget(
            sourceProjectId: sourceId,
            pointer: CGPoint(x: 100, y: 54),
            frames: frames
        )
        let afterSecond = workspaceSidebarFolderReorderTarget(
            sourceProjectId: sourceId,
            pointer: CGPoint(x: 100, y: 218),
            frames: frames
        )
        let ignoresDefault = workspaceSidebarFolderReorderTarget(
            sourceProjectId: sourceId,
            pointer: CGPoint(x: 100, y: 20),
            frames: frames
        )

        XCTAssertEqual(beforeFirst, WorkspaceSidebarFolderReorderTarget(
            targetProjectId: firstId,
            placement: .before(firstId)
        ))
        XCTAssertEqual(afterSecond, WorkspaceSidebarFolderReorderTarget(
            targetProjectId: secondId,
            placement: .after(secondId)
        ))
        XCTAssertEqual(ignoresDefault, WorkspaceSidebarFolderReorderTarget(
            targetProjectId: firstId,
            placement: .before(firstId)
        ))
    }

    func testFolderListEntriesPreviewReorderAsPlaceholder() {
        let first = sidebarFolder("project-first", displayName: "First")
        let source = sidebarFolder("project-source", displayName: "Source")
        let second = sidebarFolder("project-second", displayName: "Second")

        let entries = workspaceSidebarFolderListEntries(
            sections: [first, source, second],
            sourceProjectId: source.id.backingProjectId,
            target: WorkspaceSidebarFolderReorderTarget(
                targetProjectId: second.id.backingProjectId,
                placement: .after(second.id.backingProjectId)
            )
        )

        XCTAssertEqual(entries.map(\.testDescription), [
            "folder:project-first",
            "drag-anchor:project-source",
            "folder:project-second",
            "folder-placeholder:project-source",
        ])
    }

    func testFolderListEntriesKeepsSourceFolderWhenReorderHasNoTarget() {
        let first = sidebarFolder("project-first", displayName: "First")
        let source = sidebarFolder("project-source", displayName: "Source")
        let second = sidebarFolder("project-second", displayName: "Second")

        let entries = workspaceSidebarFolderListEntries(
            sections: [first, source, second],
            sourceProjectId: source.id.backingProjectId,
            target: nil
        )

        XCTAssertEqual(entries.map(\.testDescription), [
            "folder:project-first",
            "folder:project-source",
            "folder:project-second",
        ])
    }

    func testFolderReorderIsDisabledForDefaultAndEditingStates() {
        XCTAssertTrue(workspaceSidebarFolderReorderIsEnabled(
            projectId: WorkspaceProjectId("project-folder"),
            isCompact: false,
            isSearchFiltering: false,
            isRenamingWorkspace: false,
            isInteractive: true
        ))
        XCTAssertFalse(workspaceSidebarFolderReorderIsEnabled(
            projectId: workspaceProjectDefaultId,
            isCompact: false,
            isSearchFiltering: false,
            isRenamingWorkspace: false,
            isInteractive: true
        ))
        XCTAssertFalse(workspaceSidebarFolderReorderIsEnabled(
            projectId: WorkspaceProjectId("project-folder"),
            isCompact: true,
            isSearchFiltering: false,
            isRenamingWorkspace: false,
            isInteractive: true
        ))
        XCTAssertFalse(workspaceSidebarFolderReorderIsEnabled(
            projectId: WorkspaceProjectId("project-folder"),
            isCompact: false,
            isSearchFiltering: true,
            isRenamingWorkspace: false,
            isInteractive: true
        ))
        XCTAssertFalse(workspaceSidebarFolderReorderIsEnabled(
            projectId: WorkspaceProjectId("project-folder"),
            isCompact: false,
            isSearchFiltering: false,
            isRenamingWorkspace: true,
            isInteractive: true
        ))
    }

    func testDefaultProjectFrameIsNotVisibleWorkspaceDropTarget() {
        let sourceId = WorkspaceProjectId("project-source")
        let targetId = WorkspaceProjectId("project-target")

        XCTAssertFalse(workspaceSidebarProjectFrameIsVisibleDropTarget(
            projectId: workspaceProjectDefaultId,
            sourceProjectId: sourceId
        ))
        XCTAssertFalse(workspaceSidebarProjectFrameIsVisibleDropTarget(
            projectId: sourceId,
            sourceProjectId: sourceId
        ))
        XCTAssertTrue(workspaceSidebarProjectFrameIsVisibleDropTarget(
            projectId: targetId,
            sourceProjectId: sourceId
        ))
    }

    func testWorkspaceReorderPreviewPlacementReflectsConcreteLandingSlot() {
        let folderId = WorkspaceProjectId("project-folder")

        XCTAssertEqual(
            workspaceSidebarWorkspaceReorderPreviewPlacement(
                sourceWorkspaceName: "source",
                target: .reorder(WorkspaceSidebarWorkspaceReorderTarget(
                    projectId: workspaceProjectDefaultId,
                    targetWorkspaceName: "target",
                    placement: .before("target")
                ))
            ),
            .before("target")
        )
        XCTAssertEqual(
            workspaceSidebarWorkspaceReorderPreviewPlacement(
                sourceWorkspaceName: "source",
                target: .moveToFolder(WorkspaceSidebarWorkspaceFolderTarget(
                    projectId: folderId,
                    sourceWorkspaceName: "source"
                ))
            ),
            .intoFolder(folderId)
        )
    }

    func testWorkspaceListEntriesPreviewSameFolderReorderMovesInterveningTabsIntoSourceSpace() {
        let first = sidebarWorkspace("first")
        let second = sidebarWorkspace("second")
        let third = sidebarWorkspace("third")

        let entries = workspaceSidebarWorkspaceListEntries(
            workspaces: [first, second, third],
            projectId: workspaceProjectDefaultId,
            sourceWorkspaceName: "third",
            sourceWorkspace: third,
            target: .reorder(WorkspaceSidebarWorkspaceReorderTarget(
                projectId: workspaceProjectDefaultId,
                targetWorkspaceName: "first",
                placement: .before("first")
            ))
        )

        XCTAssertEqual(entries.map(\.testDescription), [
            "placeholder:default:third",
            "workspace:first",
            "workspace:second",
        ])
    }

    func testWorkspaceListEntriesPreviewMoveIntoFolderAsIndentedPlaceholder() {
        let folderId = WorkspaceProjectId("project-folder")
        let flat = sidebarWorkspace("flat")
        let firstFolderTab = sidebarWorkspace("folder-first", projectId: folderId)
        let secondFolderTab = sidebarWorkspace("folder-second", projectId: folderId)

        let flatEntries = workspaceSidebarWorkspaceListEntries(
            workspaces: [flat],
            projectId: workspaceProjectDefaultId,
            sourceWorkspaceName: "flat",
            sourceWorkspace: flat,
            target: .moveToFolder(WorkspaceSidebarWorkspaceFolderTarget(
                projectId: folderId,
                sourceWorkspaceName: "flat"
            ))
        )
        let folderEntries = workspaceSidebarWorkspaceListEntries(
            workspaces: [firstFolderTab, secondFolderTab],
            projectId: folderId,
            sourceWorkspaceName: "flat",
            sourceWorkspace: flat,
            target: .moveToFolder(WorkspaceSidebarWorkspaceFolderTarget(
                projectId: folderId,
                sourceWorkspaceName: "flat"
            ))
        )

        XCTAssertEqual(flatEntries.map(\.testDescription), [
        ])
        XCTAssertEqual(folderEntries.map(\.testDescription), [
            "workspace:folder-first",
            "workspace:folder-second",
            "placeholder:project-folder:flat",
        ])
    }

    func testWorkspaceListEntriesRemovesSourceWhileMovingAcrossFolders() {
        let folderId = WorkspaceProjectId("project-folder")
        let flat = sidebarWorkspace("flat")
        let folderTab = sidebarWorkspace("folder-tab", projectId: folderId)

        let flatEntries = workspaceSidebarWorkspaceListEntries(
            workspaces: [flat],
            projectId: workspaceProjectDefaultId,
            sourceWorkspaceName: "flat",
            sourceWorkspace: flat,
            target: .moveToFolder(WorkspaceSidebarWorkspaceFolderTarget(
                projectId: folderId,
                sourceWorkspaceName: "flat"
            ))
        )
        let folderEntries = workspaceSidebarWorkspaceListEntries(
            workspaces: [folderTab],
            projectId: folderId,
            sourceWorkspaceName: "flat",
            sourceWorkspace: flat,
            target: .moveToFolder(WorkspaceSidebarWorkspaceFolderTarget(
                projectId: folderId,
                sourceWorkspaceName: "flat"
            ))
        )

        XCTAssertEqual(flatEntries.map(\.testDescription), [
        ])
        XCTAssertEqual(folderEntries.map(\.testDescription), [
            "workspace:folder-tab",
            "placeholder:project-folder:flat",
        ])
    }

    func testWorkspaceListEntriesDoesNotPreviewInvalidMoveOutToRootList() {
        let folderId = WorkspaceProjectId("project-folder")
        let flat = sidebarWorkspace("flat")
        let folderChild = sidebarWorkspace("folder-child", projectId: folderId)
        let folderSibling = sidebarWorkspace("folder-sibling", projectId: folderId)
        let target = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "folder-child",
            sourceProjectId: folderId,
            pointer: CGPoint(x: 100, y: 12),
            workspaceFrames: [
                reorderFrame("flat", minY: 10, height: 40),
                reorderFrame("folder-child", minY: 60, height: 40, projectId: folderId),
            ]
        )

        let flatEntries = workspaceSidebarWorkspaceListEntries(
            workspaces: [flat],
            projectId: workspaceProjectDefaultId,
            sourceWorkspaceName: "folder-child",
            sourceWorkspace: folderChild,
            target: target
        )
        let folderEntries = workspaceSidebarWorkspaceListEntries(
            workspaces: [folderChild, folderSibling],
            projectId: folderId,
            sourceWorkspaceName: "folder-child",
            sourceWorkspace: folderChild,
            target: target
        )

        XCTAssertNil(target)
        XCTAssertEqual(flatEntries.map(\.testDescription), [
            "workspace:flat",
        ])
        XCTAssertEqual(folderEntries.map(\.testDescription), [
            "workspace:folder-child",
            "workspace:folder-sibling",
        ])
    }

    func testWorkspaceListEntriesDoesNotPreviewMoveOutToEmptyDefaultRootList() {
        let folderId = WorkspaceProjectId("project-folder")
        let folderChild = sidebarWorkspace("folder-child", projectId: folderId)
        let defaultIsDropTarget = workspaceSidebarProjectFrameIsVisibleDropTarget(
            projectId: workspaceProjectDefaultId,
            sourceProjectId: folderId
        )
        let target = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "folder-child",
            sourceProjectId: folderId,
            pointer: CGPoint(x: 100, y: 20),
            workspaceFrames: [
                reorderFrame("folder-child", minY: 60, height: 40, projectId: folderId),
            ],
            folderFrames: [
                folderFrame(workspaceProjectDefaultId, minY: 10, height: 32, isDropTarget: defaultIsDropTarget),
                folderFrame(folderId, minY: 54, height: 120),
            ]
        )

        let entries = workspaceSidebarWorkspaceListEntries(
            workspaces: [],
            projectId: workspaceProjectDefaultId,
            sourceWorkspaceName: "folder-child",
            sourceWorkspace: folderChild,
            target: target
        )

        XCTAssertFalse(defaultIsDropTarget)
        XCTAssertNil(target)
        XCTAssertEqual(entries.map(\.testDescription), [])
    }

    func testWorkspaceListEntriesMovesFollowingTabsIntoSourceSpaceAndCreatesFinalTargetSpace() {
        let first = sidebarWorkspace("first")
        let second = sidebarWorkspace("second")
        let third = sidebarWorkspace("third")

        let entries = workspaceSidebarWorkspaceListEntries(
            workspaces: [first, second, third],
            projectId: workspaceProjectDefaultId,
            sourceWorkspaceName: "first",
            sourceWorkspace: first,
            target: .reorder(WorkspaceSidebarWorkspaceReorderTarget(
                projectId: workspaceProjectDefaultId,
                targetWorkspaceName: "third",
                placement: .after("third")
            ))
        )

        XCTAssertEqual(entries.map(\.testDescription), [
            "workspace:second",
            "workspace:third",
            "placeholder:default:first",
        ])
    }

    func testWorkspaceReorderUsesFrozenFramesAfterPreviewMovesLiveRows() {
        let frozenFrames = [
            reorderFrame("first", minY: 10, height: 30),
            reorderFrame("second", minY: 50, height: 30),
            reorderFrame("third", minY: 90, height: 30),
        ]
        let projectedLiveFrames = [
            reorderFrame("first", minY: 10, height: 1),
            reorderFrame("second", minY: 12, height: 30),
            reorderFrame("third", minY: 52, height: 30),
        ]
        let hitTestFrames = workspaceSidebarWorkspaceReorderFramesForHitTesting(
            liveFrames: projectedLiveFrames,
            frozenFrames: frozenFrames
        )

        let target = workspaceSidebarWorkspaceReorderTarget(
            sourceWorkspaceName: "first",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 20, y: 105),
            frames: hitTestFrames
        )

        XCTAssertEqual(target, WorkspaceSidebarWorkspaceReorderTarget(
            projectId: workspaceProjectDefaultId,
            targetWorkspaceName: "third",
            placement: .after("third")
        ))
    }

    func testWorkspaceDragInteractionUsesLiveFramesForNewlyExpandedDestinationFolder() {
        let sourceFolderId = WorkspaceProjectId("folder-1")
        let middleFolderId = WorkspaceProjectId("folder-2")
        let destinationFolderId = WorkspaceProjectId("folder-3")
        let frozenFolderFrames = [
            folderFrame(sourceFolderId, minY: 0, height: 120),
            folderFrame(middleFolderId, minY: 130, height: 32),
            folderFrame(destinationFolderId, minY: 172, height: 32),
        ]
        let liveFolderFrames = [
            folderFrame(sourceFolderId, minY: 0, height: 120),
            folderFrame(middleFolderId, minY: 130, height: 130),
            folderFrame(destinationFolderId, minY: 270, height: 100),
        ]
        let liveWorkspaceFrames = [
            reorderFrame("source", minY: 44, height: 32, projectId: sourceFolderId),
            reorderFrame("destination", minY: 310, height: 32, projectId: destinationFolderId),
        ]
        let frozenWorkspaceFrames = [
            reorderFrame("source", minY: 44, height: 32, projectId: sourceFolderId),
        ]
        let pointer = CGPoint(x: 100, y: 330)
        let interactionFolderFrames = workspaceSidebarFolderReorderFramesForInteraction(
            liveFrames: liveFolderFrames,
            frozenFrames: frozenFolderFrames
        )
        let interactionProjectId = workspaceSidebarWorkspaceFolderTarget(
            sourceWorkspaceName: "source",
            sourceProjectId: sourceFolderId,
            pointer: pointer,
            frames: interactionFolderFrames
        )?.projectId
        let interactionWorkspaceFrames = workspaceSidebarWorkspaceReorderFramesForInteraction(
            liveFrames: liveWorkspaceFrames,
            frozenFrames: frozenWorkspaceFrames,
            destinationProjectId: interactionProjectId
        )

        let target = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: "source",
            sourceProjectId: sourceFolderId,
            pointer: pointer,
            workspaceFrames: interactionWorkspaceFrames,
            folderFrames: interactionFolderFrames
        )

        XCTAssertEqual(interactionProjectId, destinationFolderId)
        XCTAssertEqual(target, .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: destinationFolderId,
            targetWorkspaceName: "destination",
            placement: .after("destination")
        )))
    }

    func testWorkspaceListEntriesKeepsSameListSourceMountedWithoutTarget() {
        let first = sidebarWorkspace("first")
        let second = sidebarWorkspace("second")

        let entries = workspaceSidebarWorkspaceListEntries(
            workspaces: [first, second],
            projectId: workspaceProjectDefaultId,
            sourceWorkspaceName: "first",
            sourceWorkspace: first,
            target: nil
        )

        XCTAssertEqual(entries.map(\.testDescription), [
            "workspace:first",
            "workspace:second",
        ])
    }

    func testWorkspaceSourcePreviewUsesSingleWindowMetadata() {
        let window = WorkspaceSidebarWindowViewModel(
            windowId: 42,
            workspaceName: "research",
            appName: "Arc",
            appBundleId: "company.thebrowser.Browser",
            appBundlePath: "/Applications/Arc.app",
            title: "Design docs",
            isFocused: false
        )
        let workspace = WorkspaceSidebarWorkspaceViewModel(
            name: "research",
            projectId: workspaceProjectDefaultId,
            displayName: "Design docs",
            sidebarLabel: "",
            isGeneratedName: true,
            tabSummary: WorkspaceSidebarTabSummaryViewModel(
                title: "Design docs",
                subtitle: "Arc",
                appBundleId: "fallback.bundle",
                appBundlePath: "/Applications/Fallback.app",
                windowCount: 1,
                isEmpty: false
            ),
            monitorScopeId: workspaceSidebarDefaultScopeId,
            monitorName: nil,
            isFocused: false,
            isVisible: true,
            items: [WorkspaceSidebarItemViewModel(kind: .window(window))]
        )

        let preview = workspaceSidebarWorkspaceSourcePreview(workspace)

        XCTAssertEqual(preview.sourceWindowId, 42)
        XCTAssertEqual(preview.label, "Design docs")
        XCTAssertEqual(preview.appName, "Arc")
        XCTAssertEqual(preview.appBundleIdentifier, "company.thebrowser.Browser")
        XCTAssertEqual(preview.appBundlePath, "/Applications/Arc.app")
        XCTAssertFalse(preview.isTabGroup)
        XCTAssertEqual(preview.windowCount, 1)
        XCTAssertTrue(preview.tabItems.isEmpty)
    }

    func testWorkspaceSourcePreviewCarriesGroupedTabItemsForCursorStack() {
        let arc = WorkspaceSidebarWindowViewModel(
            windowId: 201,
            workspaceName: "research",
            appName: "Arc",
            appBundleId: "company.thebrowser.Browser",
            appBundlePath: "/Applications/Arc.app",
            title: "Browser notes",
            isFocused: false
        )
        let notes = WorkspaceSidebarWindowViewModel(
            windowId: 202,
            workspaceName: "research",
            appName: "Notes",
            appBundleId: "com.apple.Notes",
            appBundlePath: "/System/Applications/Notes.app",
            title: "Planning",
            isFocused: false
        )
        let group = WorkspaceSidebarTabGroupViewModel(
            representativeWindowId: arc.windowId,
            workspaceName: "research",
            title: "Research",
            windowCount: 2,
            isFocused: false,
            tabs: [arc, notes]
        )
        let workspace = WorkspaceSidebarWorkspaceViewModel(
            name: "research",
            projectId: workspaceProjectDefaultId,
            displayName: "Research",
            sidebarLabel: "Research",
            isGeneratedName: false,
            tabSummary: WorkspaceSidebarTabSummaryViewModel(
                title: "Research",
                subtitle: nil,
                appBundleId: "fallback.bundle",
                appBundlePath: "/Applications/Fallback.app",
                windowCount: 2,
                isEmpty: false
            ),
            monitorScopeId: workspaceSidebarDefaultScopeId,
            monitorName: nil,
            isFocused: false,
            isVisible: true,
            items: [WorkspaceSidebarItemViewModel(kind: .tabGroup(group))]
        )

        let preview = workspaceSidebarWorkspaceSourcePreview(workspace)

        XCTAssertEqual(preview.sourceWindowId, 201)
        XCTAssertEqual(preview.label, "Research")
        XCTAssertEqual(preview.appName, "Arc")
        XCTAssertTrue(preview.isTabGroup)
        XCTAssertEqual(preview.windowCount, 2)
        XCTAssertEqual(preview.tabItems.map(\.title), ["Browser notes", "Planning"])
        XCTAssertEqual(preview.tabItems.map(\.appBundleIdentifier), [
            "company.thebrowser.Browser",
            "com.apple.Notes",
        ])
    }

    func testCreateSidebarFolderFromWorkspacesCreatesAutoNamedEditableFolder() {
        let source = Workspace.get(byName: "source")
        source.markAsAutomaticallyNamed()
        source.assignProject(workspaceProjectDefaultId)
        source.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
        }
        let target = Workspace.get(byName: "target")
        target.markAsAutomaticallyNamed()
        target.assignProject(workspaceProjectDefaultId)
        target.rootTilingContainer.apply {
            TestWindow.new(id: 3, parent: $0)
        }
        XCTAssertTrue(target.focusWorkspace())
        setDefaultWorkspaceOrder([target, source])

        XCTAssertTrue(createSidebarFolderFromWorkspaces(
            sourceWorkspaceName: source.name,
            targetWorkspaceName: target.name
        ))

        XCTAssertNotNil(Workspace.existing(byName: source.name))
        XCTAssertNotNil(Workspace.existing(byName: target.name))
        XCTAssertEqual(source.rootTilingContainer.layoutDescription, .h_tiles([
            .window(1),
            .window(2),
        ]))
        XCTAssertEqual(target.rootTilingContainer.layoutDescription, .h_tiles([
            .window(3),
        ]))
        XCTAssertEqual(source.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(source.folderId, target.folderId)
        XCTAssertNotEqual(source.folderId, workspaceFolderDefaultId)
        XCTAssertEqual(workspaceFolderName(source.folderId), "Folder 1")
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(source.folderId))
        XCTAssertEqual(folderWorkspaces(folderId: source.folderId).map(\.name), [
            target.name,
            source.name,
        ])
        XCTAssertEqual(focus.workspace, target)
    }

    func testCreateSidebarFolderFromWorkspaceMovesActiveTabIntoVisibleFolder() {
        let workspace = Workspace.get(byName: "source")
        workspace.markAsAutomaticallyNamed()
        workspace.assignProject(workspaceProjectDefaultId)
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
        }
        XCTAssertTrue(workspace.focusWorkspace())

        let folderId = createWorkspaceFolderFromWorkspace(workspace.name)

        XCTAssertNotNil(folderId)
        XCTAssertEqual(workspace.folderId, folderId)
        XCTAssertNotEqual(workspace.folderId, workspaceFolderDefaultId)
        XCTAssertEqual(folderId.map(workspaceFolderName), "Folder 1")
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(workspace.folderId))
        XCTAssertEqual(folderWorkspaces(folderId: workspace.folderId).map(\.name), [workspace.name])
        XCTAssertEqual(focus.workspace, workspace)
    }

    func testCreateSidebarFolderFromWorkspaceIgnoresHiddenFolderIdsWhenChoosingDefaultName() throws {
        for ordinal in 1 ... 30 {
            config.workspaceSidebar.folderLabels["project-\(ordinal)"] = "Folder \(ordinal)"
        }
        let unfolded = (1 ... 5).map { ordinal in
            let workspace = Workspace.get(byName: "unfolded-\(ordinal)")
            workspace.markAsAutomaticallyNamed()
            workspace.assignProject(workspaceProjectDefaultId)
            _ = TestWindow.new(id: UInt32(100 + ordinal), parent: workspace.rootTilingContainer)
            return workspace
        }

        let firstFolderId = try XCTUnwrap(createWorkspaceFolderFromWorkspace(unfolded[0].name))
        XCTAssertEqual(firstFolderId.rawValue, "project-31")
        XCTAssertEqual(
            winMuxWorkspaceState.workspaceFoldersById[firstFolderId]?.name,
            "Folder 1"
        )

        let secondFolderId = try XCTUnwrap(createWorkspaceFolderFromWorkspace(unfolded[1].name))
        XCTAssertEqual(secondFolderId.rawValue, "project-32")
        XCTAssertEqual(
            winMuxWorkspaceState.workspaceFoldersById[secondFolderId]?.name,
            "Folder 2"
        )
    }

    func testCreateSidebarFolderFromWorkspaceAppendsBeforeUnfoldedFolder() {
        let first = createWorkspaceFolderWithWindow(windowId: 31)
        let second = createWorkspaceFolderWithWindow(windowId: 32)
        let workspace = Workspace.get(byName: "source")
        workspace.markAsAutomaticallyNamed()
        workspace.assignProject(workspaceProjectDefaultId)
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 33, parent: $0)
        }

        let folderId = createWorkspaceFolderFromWorkspace(workspace.name)

        guard let folderId else {
            XCTFail("Expected sidebar folder creation to succeed")
            return
        }
        XCTAssertEqual(workspaceFolders(in: workspaceProjectDefaultId).map(\.id), [
            first.id,
            second.id,
            folderId,
            workspaceFolderDefaultId,
        ])
    }

    func testCreateSidebarFolderFromWorkspaceRejectsEmptyTab() {
        let workspace = Workspace.get(byName: "empty")
        workspace.markAsAutomaticallyNamed()
        workspace.assignProject(workspaceProjectDefaultId)
        XCTAssertTrue(workspace.focusWorkspace())

        XCTAssertNil(createWorkspaceFolderFromWorkspace(workspace.name))
        XCTAssertEqual(workspace.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(workspaceProjects().map(\.id), [workspaceProjectDefaultId])
    }

    func testCreateSidebarFolderFromWorkspacesRejectsTabsFromDifferentProjects() {
        let project = createWorkspaceProject()
        let source = Workspace.get(byName: "source")
        source.markAsAutomaticallyNamed()
        source.assignProject(project.id)
        source.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
        }
        let target = Workspace.get(byName: "target")
        target.markAsAutomaticallyNamed()
        target.assignProject(workspaceProjectDefaultId)
        target.rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }

        XCTAssertFalse(createSidebarFolderFromWorkspaces(
            sourceWorkspaceName: source.name,
            targetWorkspaceName: target.name
        ))

        XCTAssertNotNil(Workspace.existing(byName: source.name))
        XCTAssertEqual(source.projectId, project.id)
        XCTAssertEqual(target.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(source.rootTilingContainer.layoutDescription, .h_tiles([
            .window(1),
        ]))
        XCTAssertEqual(target.rootTilingContainer.layoutDescription, .h_tiles([
            .window(2),
        ]))
    }

    func testMoveWorkspaceToSidebarFolderMovesTabWithoutComposingLayouts() {
        let folder = createWorkspaceFolder()
        let folderWorkspace = Workspace.get(byName: "folder-tab")
        folderWorkspace.assignFolder(folder.id)
        folderWorkspace.markAsAutomaticallyNamed()
        folderWorkspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
        }

        let source = Workspace.get(byName: "source")
        source.markAsAutomaticallyNamed()
        source.assignProject(workspaceProjectDefaultId)
        source.rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }
        setWorkspaceSidebarFolderExpanded(workspaceFolderDefaultId, isExpanded: true)

        XCTAssertTrue(moveWorkspaceToSidebarFolder(source.name, folderId: folder.id))

        XCTAssertEqual(source.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(source.folderId, folder.id)
        XCTAssertEqual(source.rootTilingContainer.layoutDescription, .h_tiles([
            .window(2),
            .window(3),
        ]))
        XCTAssertEqual(folderWorkspace.rootTilingContainer.layoutDescription, .h_tiles([
            .window(1),
        ]))
        XCTAssertEqual(folderWorkspaces(folderId: folder.id).map(\.name), [
            folderWorkspace.name,
            source.name,
        ])
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(folder.id))
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(workspaceFolderDefaultId))
    }

    func testMoveWorkspaceToSidebarUnfoldedFolderMovesFolderChild() {
        let folder = createWorkspaceFolder()
        let folderWorkspace = Workspace.get(byName: "folder-tab")
        folderWorkspace.assignFolder(folder.id)
        folderWorkspace.markAsAutomaticallyNamed()
        folderWorkspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
        }

        let folderChild = Workspace.get(byName: "folder-child")
        folderChild.markAsAutomaticallyNamed()
        folderChild.assignFolder(folder.id)
        folderChild.rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }

        let flat = Workspace.get(byName: "flat")
        flat.markAsAutomaticallyNamed()
        flat.assignProject(workspaceProjectDefaultId)
        flat.rootTilingContainer.apply {
            TestWindow.new(id: 3, parent: $0)
        }
        setProjectWorkspaceOrder(workspaceProjectDefaultId, [flat])
        setFolderWorkspaceOrder(folder.id, [folderWorkspace, folderChild])
        setWorkspaceSidebarFolderExpanded(folder.id, isExpanded: true)

        XCTAssertTrue(moveWorkspaceToSidebarFolder(folderChild.name, folderId: workspaceFolderDefaultId))

        XCTAssertEqual(folderChild.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(folderWorkspaces(folderId: workspaceFolderDefaultId).map(\.name), [
            flat.name,
            folderChild.name,
        ])
        XCTAssertEqual(folderWorkspaces(folderId: folder.id).map(\.name), [
            folderWorkspace.name,
        ])
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(workspaceFolderDefaultId))
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(folder.id))
    }

    func testMoveWorkspaceToSidebarUnfoldedFolderKeepsOtherDisplayUnfoldedTab() {
        let main = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        defer { setMonitorsForTests(nil) }

        let folder = createWorkspaceFolder()
        let folderWorkspace = Workspace.get(byName: "folder-tab")
        folderWorkspace.assignFolder(folder.id)
        folderWorkspace.markAsAutomaticallyNamed()

        let folderChild = Workspace.get(byName: "folder-child")
        folderChild.markAsAutomaticallyNamed()
        folderChild.assignFolder(folder.id)
        folderChild.rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }

        let otherDisplayFlatTab = Workspace.get(byName: "other-display-flat")
        otherDisplayFlatTab.markAsAutomaticallyNamed()
        otherDisplayFlatTab.assignProject(workspaceProjectDefaultId)
        otherDisplayFlatTab.rootTilingContainer.apply {
            TestWindow.new(id: 3, parent: $0)
        }

        setProjectWorkspaceOrder(workspaceProjectDefaultId, [otherDisplayFlatTab])
        setFolderWorkspaceOrder(folder.id, [folderWorkspace, folderChild])
        XCTAssertTrue(main.setActiveWorkspace(folderChild))
        XCTAssertTrue(secondary.setActiveWorkspace(otherDisplayFlatTab))
        XCTAssertEqual(folderWorkspaces(folderId: workspaceFolderDefaultId).compactMap(\.visibleMonitor).first?.rect.topLeftCorner, secondary.rect.topLeftCorner)

        XCTAssertTrue(moveWorkspaceToSidebarFolder(folderChild.name, folderId: workspaceFolderDefaultId))

        XCTAssertEqual(folderChild.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(folderWorkspaces(folderId: workspaceFolderDefaultId).map(\.name), [
            otherDisplayFlatTab.name,
            folderChild.name,
        ])
    }

    func testReorderWorkspaceCanMoveFolderChildIntoUnfoldedFolderAtSpecificPosition() {
        let folder = createWorkspaceFolder()
        let folderWorkspace = Workspace.get(byName: "folder-tab")
        folderWorkspace.assignFolder(folder.id)
        folderWorkspace.markAsAutomaticallyNamed()
        folderWorkspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
        }

        let folderChild = Workspace.get(byName: "folder-child")
        folderChild.markAsAutomaticallyNamed()
        folderChild.assignFolder(folder.id)
        folderChild.rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }

        let flat = Workspace.get(byName: "flat")
        flat.markAsAutomaticallyNamed()
        flat.assignProject(workspaceProjectDefaultId)
        flat.rootTilingContainer.apply {
            TestWindow.new(id: 3, parent: $0)
        }
        setProjectWorkspaceOrder(workspaceProjectDefaultId, [flat])
        setFolderWorkspaceOrder(folder.id, [folderWorkspace, folderChild])

        XCTAssertTrue(reorderWorkspaceForSidebar(
            sourceWorkspaceName: folderChild.name,
            folderId: workspaceFolderDefaultId,
            placement: .before(flat.name)
        ))

        XCTAssertEqual(folderChild.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(folderWorkspaces(folderId: workspaceFolderDefaultId).map(\.name), [
            folderChild.name,
            flat.name,
        ])
        XCTAssertEqual(folderWorkspaces(folderId: folder.id).map(\.name), [
            folderWorkspace.name,
        ])
    }

    func testReorderWorkspaceCanMoveFlatTabIntoFolderAtSpecificPosition() {
        let folder = createWorkspaceFolder()
        let firstFolderTab = Workspace.get(byName: "first-folder")
        firstFolderTab.assignFolder(folder.id)
        firstFolderTab.markAsAutomaticallyNamed()
        firstFolderTab.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
        }

        let secondFolderTab = Workspace.get(byName: "second-folder")
        secondFolderTab.markAsAutomaticallyNamed()
        secondFolderTab.assignFolder(folder.id)
        secondFolderTab.rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }

        let flat = Workspace.get(byName: "flat")
        flat.markAsAutomaticallyNamed()
        flat.assignProject(workspaceProjectDefaultId)
        flat.rootTilingContainer.apply {
            TestWindow.new(id: 3, parent: $0)
        }
        setProjectWorkspaceOrder(workspaceProjectDefaultId, [flat])
        setFolderWorkspaceOrder(folder.id, [firstFolderTab, secondFolderTab])
        setWorkspaceSidebarFolderExpanded(folder.id, isExpanded: false)

        XCTAssertTrue(reorderWorkspaceForSidebar(
            sourceWorkspaceName: flat.name,
            folderId: folder.id,
            placement: .after(firstFolderTab.name)
        ))

        XCTAssertEqual(flat.folderId, folder.id)
        XCTAssertEqual(folderWorkspaces(folderId: folder.id).map(\.name), [
            firstFolderTab.name,
            flat.name,
            secondFolderTab.name,
        ])
        XCTAssertTrue(workspaceSidebarFolderIsExpanded(folder.id))
    }

    func testReorderWorkspaceProjectForSidebarMovesFolderBeforeTargetFolder() {
        let first = createWorkspaceFolderWithWindow(windowId: 401)
        let second = createWorkspaceFolderWithWindow(windowId: 402)
        let third = createWorkspaceFolderWithWindow(windowId: 403)

        XCTAssertTrue(reorderWorkspaceFolderForSidebar(
            sourceFolderId: third.id,
            placement: .before(first.id.backingProjectId)
        ))

        XCTAssertEqual(workspaceFolders(in: workspaceProjectDefaultId).map(\.id), [
            third.id,
            first.id,
            second.id,
            workspaceFolderDefaultId,
        ])
    }

    func testReorderWorkspaceProjectForSidebarRejectsDefaultFolder() {
        let folder = createWorkspaceFolderWithWindow(windowId: 411)

        XCTAssertFalse(reorderWorkspaceFolderForSidebar(
            sourceFolderId: folder.id,
            placement: .before(workspaceProjectDefaultId)
        ))
        XCTAssertFalse(reorderWorkspaceFolderForSidebar(
            sourceFolderId: workspaceFolderDefaultId,
            placement: .before(folder.id.backingProjectId)
        ))
    }

    func testMergeWorkspaceIntoActiveViewFromSidebarUsesPointerMonitorActiveTabAndPosition() {
        let source = Workspace.get(byName: "source")
        source.markAsAutomaticallyNamed()
        source.assignProject(workspaceProjectDefaultId)
        source.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
        }
        let target = Workspace.get(byName: "target")
        target.markAsAutomaticallyNamed()
        target.assignProject(workspaceProjectDefaultId)
        target.rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }
        XCTAssertTrue(mainMonitor.setActiveWorkspace(target))
        XCTAssertTrue(target.focusWorkspace())

        XCTAssertTrue(mergeWorkspaceIntoActiveViewFromSidebar(
            sourceWorkspaceName: source.name,
            pointer: CGPoint(
                x: mainMonitor.rect.topLeftX + (mainMonitor.rect.width / 2),
                y: mainMonitor.rect.topLeftY + (mainMonitor.rect.height / 2)
            ),
            position: .left
        ))

        XCTAssertNil(Workspace.existing(byName: source.name))
        XCTAssertEqual(target.rootTilingContainer.layoutDescription, .h_tiles([
            .window(1),
            .window(2),
        ]))
    }

    func testMergeWorkspaceIntoActiveViewCombinesTabsDirectionallyAndRemovesSource() {
        let source = Workspace.get(byName: "source")
        source.markAsAutomaticallyNamed()
        source.assignProject(workspaceProjectDefaultId)
        source.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
        }
        let target = Workspace.get(byName: "target")
        target.markAsAutomaticallyNamed()
        target.assignProject(workspaceProjectDefaultId)
        target.rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }

        XCTAssertTrue(mergeWorkspaceTab(
            sourceWorkspaceName: source.name,
            targetWorkspaceName: target.name,
            position: .right
        ))

        XCTAssertNil(Workspace.existing(byName: source.name))
        XCTAssertEqual(target.rootTilingContainer.layoutDescription, .h_tiles([
            .window(2),
            .window(1),
        ]))
    }

    func testMergeWorkspaceIntoActiveTabGroupFromSidebarStacksSourceWindowsAndRemovesSource() {
        let source = Workspace.get(byName: "source")
        source.markAsAutomaticallyNamed()
        source.assignProject(workspaceProjectDefaultId)
        source.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
        }
        let target = Workspace.get(byName: "target")
        target.markAsAutomaticallyNamed()
        target.assignProject(workspaceProjectDefaultId)
        let targetWindow = TestWindow.new(id: 2, parent: target.rootTilingContainer)
        _ = targetWindow.focusWindow()
        XCTAssertTrue(mainMonitor.setActiveWorkspace(target))

        XCTAssertTrue(mergeWorkspaceIntoActiveTabGroupFromSidebar(
            sourceWorkspaceName: source.name,
            pointer: mainMonitor.visibleRect.center
        ))

        XCTAssertNil(Workspace.existing(byName: source.name))
        XCTAssertEqual(target.rootTilingContainer.layoutDescription, .v_tab_group([
            .window(2),
            .window(1),
        ]))
    }

    func testMergeWorkspaceIntoActiveTabGroupFromSidebarUsesHoveredWindow() {
        let source = Workspace.get(byName: "source")
        source.markAsAutomaticallyNamed()
        source.assignProject(workspaceProjectDefaultId)
        source.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
        }
        let target = Workspace.get(byName: "target")
        target.markAsAutomaticallyNamed()
        target.assignProject(workspaceProjectDefaultId)
        let firstTargetWindow = TestWindow.new(id: 2, parent: target.rootTilingContainer)
        let hoveredTargetWindow = TestWindow.new(id: 3, parent: target.rootTilingContainer)
        _ = firstTargetWindow.focusWindow()
        XCTAssertTrue(mainMonitor.setActiveWorkspace(target))

        XCTAssertTrue(mergeWorkspaceIntoActiveTabGroupFromSidebar(
            sourceWorkspaceName: source.name,
            pointer: mainMonitor.visibleRect.center,
            targetWindowId: hoveredTargetWindow.windowId
        ))

        XCTAssertEqual(target.rootTilingContainer.layoutDescription, .h_tiles([
            .window(2),
            .v_tab_group([
                .window(3),
                .window(1),
            ]),
        ]))
    }

    func testCreateSidebarFolderFromWorkspacesRejectsVisibleTabsOnDifferentDisplays() {
        let main = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        defer { setMonitorsForTests(nil) }

        let source = Workspace.get(byName: "source")
        let target = Workspace.get(byName: "target")
        XCTAssertTrue(main.setActiveWorkspace(source))
        XCTAssertTrue(secondary.setActiveWorkspace(target))

        XCTAssertFalse(createSidebarFolderFromWorkspaces(
            sourceWorkspaceName: source.name,
            targetWorkspaceName: target.name
        ))
    }

    func testWorkspaceReorderTargetIgnoresSourceAndUnreorderableFrames() {
        let frames = [
            reorderFrame("first", minY: 10, height: 30),
            reorderFrame("second", minY: 50, height: 30, isReorderable: false),
        ]

        let target = workspaceSidebarWorkspaceReorderTarget(
            sourceWorkspaceName: "first",
            sourceProjectId: workspaceProjectDefaultId,
            pointer: CGPoint(x: 12, y: 70),
            frames: frames
        )

        XCTAssertNil(target)
    }

    func testWorkspaceReorderEnablementAllowsExpandedAndCompactIdleInteractiveRows() {
        XCTAssertTrue(workspaceSidebarWorkspaceReorderIsEnabled(
            isCompact: false,
            isSearchFiltering: false,
            isRenamingWorkspace: false,
            isPinnedActiveWorkspace: false,
            isInteractive: true
        ))
        XCTAssertTrue(workspaceSidebarWorkspaceReorderIsEnabled(
            isCompact: true,
            isSearchFiltering: false,
            isRenamingWorkspace: false,
            isPinnedActiveWorkspace: false,
            isInteractive: true
        ))
        XCTAssertFalse(workspaceSidebarWorkspaceReorderIsEnabled(
            isCompact: false,
            isSearchFiltering: true,
            isRenamingWorkspace: false,
            isPinnedActiveWorkspace: false,
            isInteractive: true
        ))
        XCTAssertFalse(workspaceSidebarWorkspaceReorderIsEnabled(
            isCompact: false,
            isSearchFiltering: false,
            isRenamingWorkspace: true,
            isPinnedActiveWorkspace: false,
            isInteractive: true
        ))
        XCTAssertFalse(workspaceSidebarWorkspaceReorderIsEnabled(
            isCompact: false,
            isSearchFiltering: false,
            isRenamingWorkspace: false,
            isPinnedActiveWorkspace: true,
            isInteractive: true
        ))
    }

    func testDraggingTabKeepsSelectedRowTreatment() {
        XCTAssertTrue(workspaceSidebarHeaderRowIsHighlighted(
            isSelected: false,
            isReorderSource: true
        ))
        XCTAssertTrue(workspaceSidebarHeaderRowIsHighlighted(
            isSelected: true,
            isReorderSource: false
        ))
        XCTAssertFalse(workspaceSidebarHeaderRowIsHighlighted(
            isSelected: false,
            isReorderSource: false
        ))
    }

    func testWorkspaceReorderSuppressesPointerHoverTreatmentOnOtherTabs() {
        XCTAssertTrue(workspaceSidebarPointerHoverIsVisible(
            isHovered: true,
            isWorkspaceReorderInProgress: false
        ))
        XCTAssertFalse(workspaceSidebarPointerHoverIsVisible(
            isHovered: true,
            isWorkspaceReorderInProgress: true
        ))
        XCTAssertFalse(workspaceSidebarPointerHoverIsVisible(
            isHovered: false,
            isWorkspaceReorderInProgress: true
        ))
    }

    func testWorkspaceSourceOnlyProjectsWhenSidebarTargetExists() {
        XCTAssertFalse(workspaceSidebarWorkspaceSourceIsProjectedDragAnchor(
            isSource: true,
            target: nil
        ))
        XCTAssertFalse(workspaceSidebarWorkspaceSourceIsProjectedDragAnchor(
            isSource: false,
            target: .reorder(WorkspaceSidebarWorkspaceReorderTarget(
                projectId: workspaceProjectDefaultId,
                targetWorkspaceName: "target",
                placement: .before("target")
            ))
        ))
        XCTAssertTrue(workspaceSidebarWorkspaceSourceIsProjectedDragAnchor(
            isSource: true,
            target: .reorder(WorkspaceSidebarWorkspaceReorderTarget(
                projectId: workspaceProjectDefaultId,
                targetWorkspaceName: "target",
                placement: .before("target")
            ))
        ))
    }

    private func makeOrderedDefaultWorkspaces() -> (Workspace, Workspace, Workspace) {
        let first = focus.workspace
        let second = Workspace.get(byName: "second")
        let third = Workspace.get(byName: "third")
        setDefaultWorkspaceOrder([first, second, third])
        return (first, second, third)
    }

    private func setDefaultWorkspaceOrder(_ workspaces: [Workspace]) {
        for workspace in workspaces {
            workspace.assignProject(workspaceProjectDefaultId)
        }
        setProjectWorkspaceOrder(workspaceProjectDefaultId, workspaces)
    }

    private func setProjectWorkspaceOrder(_ projectId: WorkspaceProjectId, _ workspaces: [Workspace]) {
        let folderId = winMuxWorkspaceState.unfoldedFolderId(for: projectId)
        setFolderWorkspaceOrder(folderId, workspaces)
    }

    private func setFolderWorkspaceOrder(_ folderId: WorkspaceFolderId, _ workspaces: [Workspace]) {
        var folder = winMuxWorkspaceState.workspaceFoldersById[folderId].orDie()
        folder.workspaceOrder = workspaces.map(\.id)
        winMuxWorkspaceState.workspaceFoldersById[folderId] = folder
    }

    private func reorderFrame(
        _ workspaceName: String,
        minY: CGFloat,
        height: CGFloat,
        projectId: WorkspaceProjectId = workspaceProjectDefaultId,
        isReorderable: Bool = true
    ) -> WorkspaceSidebarWorkspaceReorderFrame {
        WorkspaceSidebarWorkspaceReorderFrame(
            workspaceName: workspaceName,
            projectId: projectId,
            frame: CGRect(x: 0, y: minY, width: 200, height: height),
            isReorderable: isReorderable
        )
    }

    private func folderFrame(
        _ projectId: WorkspaceProjectId,
        minY: CGFloat,
        height: CGFloat,
        isDropTarget: Bool = true
    ) -> WorkspaceSidebarFolderReorderFrame {
        WorkspaceSidebarFolderReorderFrame(
            projectId: projectId,
            frame: CGRect(x: 0, y: minY, width: 200, height: height),
            isDropTarget: isDropTarget
        )
    }

    private func reorderTarget(
        _ projectId: WorkspaceProjectId,
        _ workspaceName: String,
        _ placement: WorkspaceReorderPlacement
    ) -> WorkspaceSidebarWorkspaceDragTarget {
        .reorder(WorkspaceSidebarWorkspaceReorderTarget(
            projectId: projectId,
            targetWorkspaceName: workspaceName,
            placement: placement
        ))
    }

    private func sidebarWorkspace(
        _ name: String,
        projectId: WorkspaceProjectId = workspaceProjectDefaultId
    ) -> WorkspaceSidebarWorkspaceViewModel {
        WorkspaceSidebarWorkspaceViewModel(
            name: name,
            projectId: projectId,
            displayName: name,
            sidebarLabel: name,
            isGeneratedName: false,
            tabSummary: WorkspaceSidebarTabSummaryViewModel(
                title: name,
                subtitle: nil,
                appBundleId: nil,
                appBundlePath: nil,
                windowCount: 1,
                isEmpty: false
            ),
            monitorScopeId: workspaceSidebarDefaultScopeId,
            monitorName: nil,
            isFocused: false,
            isVisible: false,
            items: []
        )
    }

    private func sidebarFolder(
        _ rawProjectId: String,
        displayName: String
    ) -> WorkspaceSidebarFolderSection {
        let projectId = WorkspaceProjectId(rawProjectId)
        return WorkspaceSidebarFolderSection(
            folder: WorkspaceSidebarFolderViewModel(
                id: WorkspaceFolderId(projectId),
                projectId: workspaceProjectDefaultId,
                displayName: displayName,
                colorHex: nil,
                isUnfolded: false
            ),
            workspaces: [sidebarWorkspace("\(rawProjectId)-workspace", projectId: projectId)]
        )
    }

    private func createWorkspaceFolderWithWindow(windowId: UInt32) -> WorkspaceFolder {
        let folder = createWorkspaceFolder()
        let workspace = Workspace.get(byName: "folder-tab-\(windowId)")
        workspace.assignFolder(folder.id)
        workspace.markAsAutomaticallyNamed()
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: windowId, parent: $0)
        }
        return folder
    }
}

private extension WorkspaceSidebarWorkspaceListEntry {
    var testDescription: String {
        switch self {
            case .workspace(let workspace, let isDragAnchor):
                return "\(isDragAnchor ? "drag-anchor" : "workspace"):\(workspace.name)"
            case .placeholder(let workspace, let projectId):
                return "placeholder:\(projectId.rawValue):\(workspace.name)"
        }
    }
}

private extension WorkspaceSidebarFolderListEntry {
    var testDescription: String {
        switch self {
            case .folder(let section, let isDragAnchor):
                return "\(isDragAnchor ? "drag-anchor" : "folder"):\(section.id.rawValue)"
            case .placeholder(let section):
                return "folder-placeholder:\(section.id.rawValue)"
        }
    }
}
