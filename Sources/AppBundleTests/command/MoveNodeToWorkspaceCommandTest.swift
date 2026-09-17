@testable import AppBundle
import Common
import XCTest

@MainActor
final class MoveNodeToWorkspaceCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        testParseCommandSucc("move-node-to-workspace next", MoveNodeToWorkspaceCmdArgs(target: .relative(.next)))
        testParseCommandSucc("move-node-to-tab next", MoveNodeToWorkspaceCmdArgs(target: .relative(.next)))
        testParseCommandSucc("move-node-to-tab new", MoveNodeToWorkspaceCmdArgs(target: .fresh))
        assertEquals(parseCommand("move-node-to-workspace --fail-if-noop next").errorOrNil, "--fail-if-noop is incompatible with (next|prev)")
        assertEquals(parseCommand("move-node-to-workspace --stdin foo").errorOrNil, "--stdin and --no-stdin require using (next|prev) argument")
        testParseCommandSucc("move-node-to-workspace --stdin next", MoveNodeToWorkspaceCmdArgs(target: .relative(.next)).copy(\.explicitStdinFlag, true))
        testParseCommandSucc("move-node-to-workspace --no-stdin next", MoveNodeToWorkspaceCmdArgs(target: .relative(.next)).copy(\.explicitStdinFlag, false))
    }

    func testHelpIsTabFirstWhileKeepingWorkspaceCompatibility() {
        guard case .help(let help) = parseCommand("move-node-to-workspace --help") else {
            XCTFail("Expected help")
            return
        }

        XCTAssertTrue(help.contains("USAGE: move-node-to-tab"))
        XCTAssertFalse(help.contains("OR: move-node-to-workspace"))
    }

    func testSimple() async throws {
        let workspaceA = Workspace.get(byName: "a")
        workspaceA.rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }

        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)
        XCTAssertTrue(workspaceA.isEffectivelyEmpty)
        assertEquals((Workspace.get(byName: "b").rootTilingContainer.children.singleOrNil() as? Window)?.windowId, 1)
    }

    func testMovingLastWindowLeavesOneAdjacentEmptyWorkspace() async throws {
        let workspaceA = Workspace.get(byName: "a")
        workspaceA.rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }

        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)

        Workspace.reconcileWorkspaceState()

        XCTAssertTrue(Workspace.existing(byName: "a") === workspaceA)
        XCTAssertTrue(workspaceA.isEffectivelyEmpty)
        XCTAssertEqual(
            userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace).filter(\.isOrdinaryEmptySlot),
            [workspaceA],
        )
    }

    func testAnotherWindowSubject() async throws {
        Workspace.get(byName: "a").rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            _ = TestWindow.new(id: 2, parent: $0).focusWindow()
        }

        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testPreserveFloatingLayout() async throws {
        let workspaceA = Workspace.get(byName: "a").apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }

        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)
        XCTAssertTrue(workspaceA.isEffectivelyEmpty)
        assertEquals(Workspace.get(byName: "b").children.filterIsInstance(of: Window.self).singleOrNil()?.windowId, 1)
    }

    func testNewWorkspaceKeepsSourceMonitorPreferenceBeforeItBecomesVisible() async throws {
        let workspaceA = Workspace.get(byName: "a")
        workspaceA.rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }

        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(Workspace.get(byName: "b").preferredMonitorPointForTesting, workspaceA.workspaceMonitor.rect.topLeftCorner)
    }

    func testNewForceAssignedWorkspaceUsesForcedMonitorViewport() async throws {
        let main = TestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = TestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        config.workspaceToMonitorForceAssignment["forced"] = [.sequenceNumber(2)]
        let workspaceA = Workspace.get(byName: "a")
        workspaceA.rootTilingContainer.apply {
            _ = TestWindow.new(id: 31, parent: $0).focusWindow()
        }

        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "forced")).run(.defaultEnv, .emptyStdin)

        let forced = Workspace.get(byName: "forced")
        XCTAssertEqual(forced.preferredMonitorPointForTesting, secondary.rect.topLeftCorner)
        XCTAssertEqual(forced.workspaceMonitor.rect.topLeftCorner, secondary.rect.topLeftCorner)
    }

    func testNewWorkspaceUsesCurrentFolderWhenProjectsAreHardDisabled() async throws {
        let project = createWorkspaceProject()
        let sourceWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: mainMonitor))
        _ = TestWindow.new(id: 1, parent: sourceWorkspace.rootTilingContainer).focusWindow()

        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(Workspace.get(byName: "b").projectId, project.id)
    }

    func testNewWorkspaceUsesCurrentFolderWhenProjectsDisabled() async throws {
        let project = createWorkspaceProject()
        let sourceWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: mainMonitor))
        _ = TestWindow.new(id: 2, parent: sourceWorkspace.rootTilingContainer).focusWindow()
        config.enableProjects = false

        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(Workspace.get(byName: "b").projectId, project.id)
    }

    func testDirectNumericMoveCreatesOnlyAdjacentWorkspace() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        let window = TestWindow.new(id: 11, parent: workspace1.rootTilingContainer)
        _ = window.focusWindow()

        let result = try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "2"))
            .run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(window.nodeWorkspace?.name, "2")
        XCTAssertEqual(workspaceDisplayName("2"), "Tab 2")
    }

    func testDirectNumericMoveFromFolderedTabCreatesTabInSameFolder() async throws {
        let defaultWorkspace = Workspace.get(byName: "1")
        defaultWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 21, parent: defaultWorkspace.rootTilingContainer)

        let groupProject = createWorkspaceProject()
        let groupedWorkspace = Workspace.get(byName: "grouped")
        groupedWorkspace.markAsAutomaticallyNamed()
        groupedWorkspace.assignProject(groupProject.id)
        groupedWorkspace.seedMonitorIfNeeded(defaultWorkspace.workspaceMonitor)
        let window = TestWindow.new(id: 22, parent: groupedWorkspace.rootTilingContainer)
        _ = window.focusWindow()

        let result = try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "2"))
            .run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(window.nodeWorkspace?.projectId, groupProject.id)
        XCTAssertEqual(workspaceDisplayName(window.nodeWorkspace?.name ?? ""), "Tab 2")
    }

    func testDirectNumericMoveUsesSourceMonitorLocalTabDisplayIndexWhenProjectsAreHardDisabled() async throws {
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
        defer { setMonitorsForTests(nil) }

        let mainFirst = Workspace.get(byName: "main-first")
        mainFirst.markAsAutomaticallyNamed()
        mainFirst.seedMonitorIfNeeded(main)
        let movedWindow = TestWindow.new(id: 23, parent: mainFirst.rootTilingContainer)
        let mainSecond = Workspace.get(byName: "main-second")
        mainSecond.markAsAutomaticallyNamed()
        mainSecond.seedMonitorIfNeeded(main)
        _ = TestWindow.new(id: 24, parent: mainSecond.rootTilingContainer)
        let secondaryFirst = Workspace.get(byName: "secondary-first")
        secondaryFirst.markAsAutomaticallyNamed()
        secondaryFirst.seedMonitorIfNeeded(secondary)
        _ = TestWindow.new(id: 25, parent: secondaryFirst.rootTilingContainer)
        let secondarySecond = Workspace.get(byName: "secondary-second")
        secondarySecond.markAsAutomaticallyNamed()
        secondarySecond.seedMonitorIfNeeded(secondary)
        let secondaryWindow = TestWindow.new(id: 26, parent: secondarySecond.rootTilingContainer)
        XCTAssertTrue(main.setActiveWorkspace(mainFirst))
        XCTAssertTrue(secondary.setActiveWorkspace(secondaryFirst))
        XCTAssertTrue(movedWindow.focusWindow())

        let result = try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "2"))
            .run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertTrue(movedWindow.nodeWorkspace === mainSecond)
        XCTAssertTrue(secondaryWindow.nodeWorkspace === secondarySecond)
        XCTAssertEqual(movedWindow.nodeWorkspace?.workspaceMonitor.rect.topLeftCorner, main.rect.topLeftCorner)
        XCTAssertEqual(scopedAutomaticDisplayWorkspaces(current: mainFirst), [mainFirst, mainSecond])
        XCTAssertEqual(scopedAutomaticDisplayWorkspaces(current: secondaryFirst), [secondaryFirst, secondarySecond])
    }

    func testDirectNumericMoveDoesNotCreateWorkspaceMultipleHopsAway() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        let window = TestWindow.new(id: 12, parent: workspace1.rootTilingContainer)
        _ = window.focusWindow()

        let result = try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "3"))
            .run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertNil(Workspace.existing(byName: "3"))
        XCTAssertEqual(window.nodeWorkspace, workspace1)
    }

    func testDirectNumericMoveFillsDisplayIndexGapBeforeAppending() async throws {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        let window = TestWindow.new(id: 17, parent: first.rootTilingContainer)
        let thirdRaw = Workspace.get(byName: "3")
        thirdRaw.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 18, parent: thirdRaw.rootTilingContainer)
        _ = window.focusWindow()

        let result = try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "3"))
            .run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(window.nodeWorkspace?.name, "2")
        XCTAssertNil(Workspace.existing(byName: "4"))
        XCTAssertEqual(workspaceDisplayName(first.name), "Tab 1")
        XCTAssertEqual(workspaceDisplayName(thirdRaw.name), "Tab 2")
        XCTAssertEqual(workspaceDisplayName("2"), "Tab 3")
    }

    func testDirectNumericMoveDoesNotCreateMultipleHopsAfterBlankIsCollected() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        let window = TestWindow.new(id: 13, parent: workspace1.rootTilingContainer)
        _ = window.focusWindow()
        assertEquals(
            try await WorkspaceCommand(args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())))
                .run(.defaultEnv, .emptyStdin)
                .exitCode,
            0,
        )
        _ = window.focusWindow()
        Workspace.reconcileWorkspaceState()
        XCTAssertNil(Workspace.existing(byName: "2"))

        let result = try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "3"))
            .run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertNil(Workspace.existing(byName: "3"))
        XCTAssertEqual(window.nodeWorkspace, workspace1)
    }

    func testRelativeNextMoveCreatesAdjacentWorkspace() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        let window = TestWindow.new(id: 14, parent: workspace1.rootTilingContainer)
        _ = window.focusWindow()

        let result = try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(target: .relative(.next)))
            .run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(window.nodeWorkspace?.name, "2")
    }

    func testFreshMoveAlwaysCreatesNewAdjacentWorkspaceInCurrentFolder() async throws {
        let folder = createWorkspaceProject()
        let first = projectWorkspaces(projectId: folder.id).first.orDie()
        first.markAsAutomaticallyNamed()
        let window = TestWindow.new(id: 15, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "already-there")
        second.markAsAutomaticallyNamed()
        second.assignProject(folder.id)
        second.seedMonitorIfNeeded(mainMonitor)
        _ = TestWindow.new(id: 16, parent: second.rootTilingContainer)
        _ = window.focusWindow()

        let result = try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(target: .fresh))
            .run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        let freshWorkspace = try XCTUnwrap(window.nodeWorkspace)
        XCTAssertEqual(freshWorkspace.projectId, folder.id)
        XCTAssertNotEqual(freshWorkspace, first)
        XCTAssertNotEqual(freshWorkspace, second)
        XCTAssertEqual(
            projectWorkspaces(projectId: folder.id).map(\.name),
            [first.name, freshWorkspace.name, second.name],
        )
    }

    func testMoveWindowToWorkspaceWrapsRootTabGroupInsteadOfTabbingIntoIt() async throws {
        let sourceWorkspace = Workspace.get(byName: "a")
        let window = TestWindow.new(id: 1, parent: sourceWorkspace.rootTilingContainer)
        let targetWorkspace = Workspace.get(byName: "b")
        let rootTabGroup = targetWorkspace.rootTilingContainer
        rootTabGroup.layout = .tabGroup
        _ = TestWindow.new(id: 2, parent: rootTabGroup)
        _ = TestWindow.new(id: 3, parent: rootTabGroup)

        XCTAssertTrue(moveWindowToWorkspace(window, targetWorkspace, CmdIo(stdin: .emptyStdin), focusFollowsWindow: false, failIfNoop: false))

        XCTAssertEqual(targetWorkspace.rootTilingContainer.layout, .tiles)
        XCTAssertTrue(targetWorkspace.rootTilingContainer.children.first === rootTabGroup)
        XCTAssertTrue(targetWorkspace.rootTilingContainer.children.last === window)
        XCTAssertEqual(rootTabGroup.children.count, 2)
    }

    func testSummonWindow() async throws {
        let workspaceA = Workspace.get(byName: "a").apply {
            $0.rootTilingContainer.apply {
                _ = TestWindow.new(id: 1, parent: $0).focusWindow()
            }
        }
        Workspace.get(byName: "b").rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.workspace, workspaceA)

        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "a").copy(\.windowId, 2))
            .run(.defaultEnv, .emptyStdin)

        assertEquals(focus.workspace, workspaceA)
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(Workspace.get(byName: "b").rootTilingContainer.children.count, 0)
        assertEquals(workspaceA.rootTilingContainer.children.count, 2)
    }
}
