@testable import AppBundle
import Common
import XCTest

@MainActor
final class ProjectCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testProjectCommandsRemainAvailableToCLI() {
        XCTAssertTrue(parseCommand("project").cmdOrNil is ProjectCommand)
        XCTAssertTrue(parseCommand("project next").cmdOrNil is ProjectCommand)
        XCTAssertTrue(parseCommand("folder 2").cmdOrNil is ProjectCommand)
        XCTAssertTrue(parseCommand("move-node-to-project 2").cmdOrNil is MoveNodeToProjectCommand)
        XCTAssertTrue(parseCommand("move-node-to-folder default").cmdOrNil is MoveNodeToProjectCommand)
    }

    func testProjectCreationOwnsUnfoldedFolderAndBlankTab() throws {
        let project = createWorkspaceProject()
        let stored = try XCTUnwrap(winMuxWorkspaceState.projectsById[project.id])
        let unfolded = try XCTUnwrap(winMuxWorkspaceState.workspaceFoldersById[stored.unfoldedFolderId])

        XCTAssertEqual(project.name, "Project 1")
        XCTAssertEqual(unfolded.projectId, project.id)
        XCTAssertEqual(unfolded.name, "Unfolded")
        XCTAssertEqual(stored.folderOrder, [unfolded.id])
        XCTAssertEqual(projectWorkspaces(projectId: project.id).count, 1)
        XCTAssertEqual(projectWorkspaces(projectId: project.id).first?.folderId, unfolded.id)
        XCTAssertTrue(projectWorkspaces(projectId: project.id).first?.isOrdinaryEmptySlot == true)

        let folder = createWorkspaceFolder(in: project.id)
        XCTAssertEqual(folder.projectId, project.id)
        XCTAssertEqual(
            winMuxWorkspaceState.projectsById[project.id]?.folderOrder,
            [folder.id, unfolded.id]
        )
    }

    func testProjectCommandSwitchesRealProjectsByIndex() async throws {
        let mainWorkspace = focus.workspace
        _ = TestWindow.new(id: 1, parent: mainWorkspace.rootTilingContainer)
        let project = createWorkspaceProject()
        let projectWorkspace = projectWorkspaces(projectId: project.id).first.orDie()
        _ = TestWindow.new(id: 2, parent: projectWorkspace.rootTilingContainer)

        let result = try await ProjectCommand(
            args: ProjectCmdArgs(target: .index(2))
        ).run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(focus.workspace === projectWorkspace)
        XCTAssertEqual(activeWorkspaceProjectId(for: mainMonitor), project.id)
    }

    func testProjectSelectionIsIndependentPerDisplay() throws {
        let main = TestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true
        )
        let secondary = TestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false
        )
        setMonitorsForTests([main, secondary])
        defer { setMonitorsForTests(nil) }

        let mainWorkspace = Workspace.get(byName: "main")
        mainWorkspace.markAsAutomaticallyNamed()
        mainWorkspace.seedMonitorIfNeeded(main)
        _ = TestWindow.new(id: 11, parent: mainWorkspace.rootTilingContainer)
        let secondaryWorkspace = Workspace.get(byName: "secondary")
        secondaryWorkspace.markAsAutomaticallyNamed()
        secondaryWorkspace.seedMonitorIfNeeded(secondary)
        _ = TestWindow.new(id: 12, parent: secondaryWorkspace.rootTilingContainer)
        XCTAssertTrue(main.setActiveWorkspace(mainWorkspace))
        XCTAssertTrue(secondary.setActiveWorkspace(secondaryWorkspace))

        let project = createWorkspaceProject()
        let secondaryProjectWorkspace = Workspace.get(byName: "secondary-project")
        secondaryProjectWorkspace.markAsAutomaticallyNamed()
        secondaryProjectWorkspace.assignProject(project.id)
        secondaryProjectWorkspace.seedMonitorIfNeeded(secondary)
        _ = TestWindow.new(id: 13, parent: secondaryProjectWorkspace.rootTilingContainer)

        XCTAssertTrue(switchWorkspaceProject(project.id, on: secondary) === secondaryProjectWorkspace)
        XCTAssertEqual(activeWorkspaceProjectId(for: main), workspaceProjectDefaultId)
        XCTAssertEqual(activeWorkspaceProjectId(for: secondary), project.id)

        XCTAssertNotNil(switchWorkspaceProject(project.id, on: main))
        XCTAssertEqual(activeWorkspaceProjectId(for: main), project.id)
        XCTAssertTrue(secondary.activeWorkspace === secondaryProjectWorkspace)

        XCTAssertTrue(switchWorkspaceProject(workspaceProjectDefaultId, on: main) === mainWorkspace)
        XCTAssertEqual(activeWorkspaceProjectId(for: main), workspaceProjectDefaultId)
        XCTAssertEqual(activeWorkspaceProjectId(for: secondary), project.id)
    }

    func testMainCanBeRenamedAndDeleted() throws {
        try renameWorkspaceProject(workspaceProjectDefaultId, displayName: "Personal")
        XCTAssertEqual(workspaceProjectName(workspaceProjectDefaultId), "Personal")
        XCTAssertTrue(canDeleteWorkspaceProject(workspaceProjectDefaultId))

        let project = createWorkspaceProject()
        try renameWorkspaceProject(project.id, displayName: "Client")
        XCTAssertEqual(workspaceProjectName(project.id), "Client")
        XCTAssertThrowsError(try renameWorkspaceProject(project.id, displayName: "Personal"))

        try deleteWorkspaceProject(workspaceProjectDefaultId)
        XCTAssertNil(winMuxWorkspaceState.projectsById[workspaceProjectDefaultId])
        XCTAssertNotNil(winMuxWorkspaceState.projectsById[project.id])

        try deleteWorkspaceProject(project.id)
        XCTAssertNil(winMuxWorkspaceState.projectsById[project.id])
        XCTAssertNil(config.workspaceSidebar.projectLabels[project.id.rawValue])
        XCTAssertEqual(workspaceProjects().map(\.name), ["Default"])
    }

    func testProjectIsDeletedWhenItsLastTabCloses() {
        let project = createWorkspaceProject()
        let tab = projectWorkspaces(projectId: project.id).singleOrNil().orDie()
        let window = TestWindow.new(id: 20, parent: tab.rootTilingContainer)

        window.closeAxWindow()

        XCTAssertNil(winMuxWorkspaceState.projectsById[project.id])
    }

    func testClosingTheLastProjectTabCreatesDefaultProject() {
        let window = TestWindow.new(id: 21, parent: focus.workspace.rootTilingContainer)

        window.closeAxWindow()

        XCTAssertNil(winMuxWorkspaceState.projectsById[workspaceProjectDefaultId])
        XCTAssertEqual(workspaceProjects().map(\.name), ["Default"])
    }

    func testClosingLastWindowDeletesProjectWithBlankPlaceholders() {
        let project = createWorkspaceProject()
        let tab = projectWorkspaces(projectId: project.id).singleOrNil().orDie()
        let window = TestWindow.new(id: 23, parent: tab.rootTilingContainer)
        _ = createBlankWorkspace(projectId: project.id, monitor: mainMonitor)

        window.closeAxWindow()

        XCTAssertNil(winMuxWorkspaceState.projectsById[project.id])
        XCTAssertTrue(projectWorkspaces(projectId: project.id).isEmpty)
    }

    func testEmptyProjectIsRemovedAfterLeavingItsBlankWorkspace() {
        let occupied = focus.workspace
        _ = TestWindow.new(id: 24, parent: occupied.rootTilingContainer)
        let project = createWorkspaceProject()
        _ = switchWorkspaceProject(project.id, on: mainMonitor)
        pruneEmptyWorkspaceProjects()
        XCTAssertNotNil(winMuxWorkspaceState.projectsById[project.id])

        _ = occupied.focusWorkspace()
        pruneEmptyWorkspaceProjects()

        XCTAssertNil(winMuxWorkspaceState.projectsById[project.id])
        XCTAssertTrue(projectWorkspaces(projectId: project.id).isEmpty)
        XCTAssertEqual(mainMonitor.activeWorkspace, occupied)
    }

    func testMovingActiveTabToProjectFallsBackWithinSourceAndAppendsToUnfolded() throws {
        let source = Workspace.get(byName: "source")
        source.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 21, parent: source.rootTilingContainer)
        let adjacent = Workspace.get(byName: "adjacent")
        adjacent.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 22, parent: adjacent.rootTilingContainer)
        XCTAssertTrue(source.focusWorkspace())

        let destination = createWorkspaceProject()
        let destinationUnfolded = try XCTUnwrap(
            winMuxWorkspaceState.projectsById[destination.id]?.unfoldedFolderId
        )
        let originalDestinationIds = folderWorkspaces(folderId: destinationUnfolded).map(\.id)

        XCTAssertTrue(moveWorkspaceToProject(
            workspaceName: source.name,
            destinationProjectId: destination.id
        ))

        XCTAssertTrue(mainMonitor.activeWorkspace === adjacent)
        XCTAssertTrue(focus.workspace === adjacent)
        XCTAssertEqual(source.projectId, destination.id)
        XCTAssertEqual(source.folderId, destinationUnfolded)
        XCTAssertEqual(
            folderWorkspaces(folderId: destinationUnfolded).map(\.id),
            originalDestinationIds + [source.id]
        )
        XCTAssertEqual(activeWorkspaceProjectId(for: mainMonitor), workspaceProjectDefaultId)
    }

    func testMovingInactiveTabLeavesSourceProjectAndActiveTabSelected() {
        let active = Workspace.get(byName: "active")
        active.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 31, parent: active.rootTilingContainer)
        let inactive = Workspace.get(byName: "inactive")
        inactive.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 32, parent: inactive.rootTilingContainer)
        XCTAssertTrue(active.focusWorkspace())
        let destination = createWorkspaceProject()

        XCTAssertTrue(moveWorkspaceToProject(
            workspaceName: inactive.name,
            destinationProjectId: destination.id
        ))

        XCTAssertTrue(mainMonitor.activeWorkspace === active)
        XCTAssertTrue(focus.workspace === active)
        XCTAssertEqual(active.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(inactive.projectId, destination.id)
    }

    func testMovingActiveFolderPreservesFolderAndFallsBackWithinSourceProject() throws {
        let folder = createWorkspaceFolder()
        try renameWorkspaceFolder(folder.id, displayName: "Research")
        let first = Workspace.get(byName: "folder-first")
        first.markAsAutomaticallyNamed()
        first.assignFolder(folder.id)
        _ = TestWindow.new(id: 41, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "folder-second")
        second.markAsAutomaticallyNamed()
        second.assignFolder(folder.id)
        _ = TestWindow.new(id: 42, parent: second.rootTilingContainer)
        let sourceFallback = Workspace.get(byName: "source-fallback")
        sourceFallback.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 43, parent: sourceFallback.rootTilingContainer)
        XCTAssertTrue(first.focusWorkspace())

        let destination = createWorkspaceProject()
        let destinationFolder = createWorkspaceFolder(in: destination.id)
        let destinationUnfolded = destination.unfoldedFolderId

        XCTAssertTrue(moveWorkspaceFolderToProject(
            folderId: folder.id,
            destinationProjectId: destination.id
        ))

        XCTAssertEqual(activeWorkspaceProjectId(for: mainMonitor), workspaceProjectDefaultId)
        XCTAssertFalse([first, second].contains { mainMonitor.activeWorkspace === $0 })
        XCTAssertFalse([first, second].contains { focus.workspace === $0 })
        XCTAssertEqual(winMuxWorkspaceState.workspaceFoldersById[folder.id]?.projectId, destination.id)
        XCTAssertEqual(workspaceFolderName(folder.id), "Research")
        XCTAssertEqual(folderWorkspaces(folderId: folder.id).map(\.id), [first.id, second.id])
        XCTAssertEqual(first.folderId, folder.id)
        XCTAssertEqual(second.folderId, folder.id)
        XCTAssertFalse(
            winMuxWorkspaceState.projectsById[workspaceProjectDefaultId]?.folderOrder.contains(folder.id) == true
        )
        XCTAssertEqual(
            winMuxWorkspaceState.projectsById[destination.id]?.folderOrder,
            [destinationFolder.id, folder.id, destinationUnfolded]
        )
    }

    func testMovingInactiveFolderLeavesCurrentTabSelectedAndRejectsUnfolded() {
        let active = Workspace.get(byName: "active-source")
        active.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 51, parent: active.rootTilingContainer)
        XCTAssertTrue(active.focusWorkspace())
        let folder = createWorkspaceFolder()
        let inactive = Workspace.get(byName: "inactive-folder-tab")
        inactive.markAsAutomaticallyNamed()
        inactive.assignFolder(folder.id)
        _ = TestWindow.new(id: 52, parent: inactive.rootTilingContainer)
        let destination = createWorkspaceProject()

        XCTAssertTrue(moveWorkspaceFolderToProject(
            folderId: folder.id,
            destinationProjectId: destination.id
        ))
        XCTAssertTrue(mainMonitor.activeWorkspace === active)
        XCTAssertTrue(focus.workspace === active)
        XCTAssertEqual(inactive.projectId, destination.id)
        XCTAssertFalse(moveWorkspaceFolderToProject(
            folderId: workspaceFolderDefaultId,
            destinationProjectId: destination.id
        ))
    }
}
