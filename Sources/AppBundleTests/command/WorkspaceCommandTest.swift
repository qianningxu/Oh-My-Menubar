@testable import AppBundle
import Common
import XCTest

@MainActor
final class WorkspaceCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParseWorkspaceCommand() {
        testParseCommandFail("workspace my mail", msg: "ERROR: Unknown argument 'mail'")
        testParseCommandFail("workspace 'my mail'", msg: "ERROR: Whitespace characters are forbidden in Tab names")
        assertEquals(parseCommand("workspace").errorOrNil, "ERROR: Argument '(<tab-name>|new|next|prev)' is mandatory")
        testParseCommandSucc("tab new", WorkspaceCmdArgs(target: .fresh))
        testParseCommandSucc("workspace next", WorkspaceCmdArgs(target: .relative(.next)))
        testParseCommandSucc("tab next", WorkspaceCmdArgs(target: .relative(.next)))
        testParseCommandSucc("workspace --auto-back-and-forth W", WorkspaceCmdArgs(target: .direct(.parse("W").getOrDie()), autoBackAndForth: true))
        assertEquals(parseCommand("workspace --wrap-around W").errorOrNil, "--wrapAround requires using (next|prev) argument")
        assertEquals(parseCommand("workspace --auto-back-and-forth next").errorOrNil, "--auto-back-and-forth is incompatible with (next|prev)")
        testParseCommandSucc("workspace next --wrap-around", WorkspaceCmdArgs(target: .relative(.next), wrapAround: true))
        testParseCommandSucc("tab next --wrap-around", WorkspaceCmdArgs(target: .relative(.next), wrapAround: true))
        assertEquals(parseCommand("workspace --stdin foo").errorOrNil, "--stdin and --no-stdin require using (next|prev) argument")
        testParseCommandSucc("workspace --stdin next", WorkspaceCmdArgs(target: .relative(.next)).copy(\.explicitStdinFlag, true))
        testParseCommandSucc("workspace --no-stdin next", WorkspaceCmdArgs(target: .relative(.next)).copy(\.explicitStdinFlag, false))
    }

    func testHelpIsTabFirstWhileKeepingWorkspaceCompatibility() {
        guard case .help(let help) = parseCommand("workspace --help") else {
            XCTFail("Expected help")
            return
        }

        XCTAssertTrue(help.contains("USAGE: tab"))
        XCTAssertFalse(help.contains("OR: workspace"))
    }

    func testDirectWorkspaceFocusDoesNotCreateMissingWorkspace() async throws {
        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertNil(Workspace.existing(byName: "2"))
    }

    func testDirectWorkspaceFocusCreatesNextBlankNumericWorkspace() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 1, parent: workspace1.rootTilingContainer)
        _ = workspace1.focusWorkspace()

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace.name, "2")
        XCTAssertEqual(workspaceDisplayName("2"), "Tab 2")
    }

    func testDirectWorkspaceFocusDoesNotSkipBlankNumericWorkspace() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 2, parent: workspace1.rootTilingContainer)
        _ = workspace1.focusWorkspace()

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("3").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertNil(Workspace.existing(byName: "3"))
    }

    func testDirectWorkspaceFocusDoesNotCreateMultipleHopsAfterBlankIsCollected() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 20, parent: workspace1.rootTilingContainer)
        _ = workspace1.focusWorkspace()
        assertEquals(
            try await WorkspaceCommand(
                args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
            ).run(.defaultEnv, .emptyStdin).exitCode,
            0,
        )
        _ = workspace1.focusWorkspace()
        Workspace.reconcileWorkspaceState()
        XCTAssertNil(Workspace.existing(byName: "2"))

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("3").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertNil(Workspace.existing(byName: "3"))
    }

    func testDirectWorkspaceShortcutUsesProjectViewportOrderInsteadOfRawNameSort() async throws {
        let first = Workspace.get(byName: "10")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 21, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "2")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 22, parent: second.rootTilingContainer)
        _ = second.focusWorkspace()

        let focusFirst = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("1").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)
        assertEquals(focusFirst.exitCode, 0)
        XCTAssertTrue(focus.workspace === first)

        let focusSecond = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)
        assertEquals(focusSecond.exitCode, 0)
        XCTAssertTrue(focus.workspace === second)
    }

    func testDirectWorkspaceFocusFillsDisplayIndexGapBeforeAppending() async throws {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 23, parent: first.rootTilingContainer)
        let thirdRaw = Workspace.get(byName: "3")
        thirdRaw.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 24, parent: thirdRaw.rootTilingContainer)
        _ = first.focusWorkspace()

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("3").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace.name, "2")
        XCTAssertNil(Workspace.existing(byName: "4"))
        XCTAssertEqual(workspaceDisplayName(first.name), "Tab 1")
        XCTAssertEqual(workspaceDisplayName(thirdRaw.name), "Tab 2")
        XCTAssertEqual(workspaceDisplayName("2"), "Tab 3")
    }

    func testNextWorkspaceAfterRawNameGapCreatesRawTwoNotRawFour() async throws {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 25, parent: first.rootTilingContainer)
        let thirdRaw = Workspace.get(byName: "3")
        thirdRaw.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 26, parent: thirdRaw.rootTilingContainer)
        _ = thirdRaw.focusWorkspace()

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .relative(.next)),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace.name, "2")
        XCTAssertNil(Workspace.existing(byName: "4"))
        XCTAssertEqual(workspaceDisplayName(first.name), "Tab 1")
        XCTAssertEqual(workspaceDisplayName(thirdRaw.name), "Tab 2")
        XCTAssertEqual(workspaceDisplayName("2"), "Tab 3")
    }

    func testWorkspaceNextPrevFollowDisplayOrderWhenRawNamesSortDifferently() async throws {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 27, parent: first.rootTilingContainer)
        let secondDisplay = Workspace.get(byName: "__internal_auto_workspace_1")
        secondDisplay.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 28, parent: secondDisplay.rootTilingContainer)
        let third = Workspace.get(byName: "3")
        third.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 29, parent: third.rootTilingContainer)
        _ = first.focusWorkspace()

        XCTAssertEqual(workspaceDisplayName(first.name), "Tab 1")
        XCTAssertEqual(workspaceDisplayName(secondDisplay.name), "Tab 2")
        XCTAssertEqual(workspaceDisplayName(third.name), "Tab 3")

        assertEquals(
            try await WorkspaceCommand(args: WorkspaceCmdArgs(target: .relative(.next)))
                .run(.defaultEnv, .emptyStdin)
                .exitCode,
            0,
        )
        XCTAssertTrue(focus.workspace === secondDisplay)

        assertEquals(
            try await WorkspaceCommand(args: WorkspaceCmdArgs(target: .relative(.next)))
                .run(.defaultEnv, .emptyStdin)
                .exitCode,
            0,
        )
        XCTAssertTrue(focus.workspace === third)

        assertEquals(
            try await WorkspaceCommand(args: WorkspaceCmdArgs(target: .relative(.prev)))
                .run(.defaultEnv, .emptyStdin)
                .exitCode,
            0,
        )
        XCTAssertTrue(focus.workspace === secondDisplay)

        assertEquals(
            try await WorkspaceCommand(args: WorkspaceCmdArgs(target: .relative(.prev)))
                .run(.defaultEnv, .emptyStdin)
                .exitCode,
            0,
        )
        XCTAssertTrue(focus.workspace === first)
    }

    func testBlankNumericWorkspaceIsDeletedAfterLeavingItEmpty() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 3, parent: workspace1.rootTilingContainer)
        _ = workspace1.focusWorkspace()

        assertEquals(
            try await WorkspaceCommand(
                args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
            ).run(.defaultEnv, .emptyStdin).exitCode,
            0,
        )

        _ = workspace1.focusWorkspace()
        Workspace.reconcileWorkspaceState()

        XCTAssertNil(Workspace.existing(byName: "2"))
        XCTAssertEqual(workspaceDisplayName("1"), "Tab 1")
    }

    func testWorkspaceNextCreatesBlankNumericWorkspaceAtRightEdge() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 4, parent: workspace1.rootTilingContainer)
        _ = workspace1.focusWorkspace()

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .relative(.next)),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace.name, "2")
        XCTAssertEqual(workspaceDisplayName("2"), "Tab 2")
    }

    func testWorkspaceNextBlankNumericWorkspaceIsDeletedAfterLeavingItEmpty() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 5, parent: workspace1.rootTilingContainer)
        _ = workspace1.focusWorkspace()

        assertEquals(
            try await WorkspaceCommand(
                args: WorkspaceCmdArgs(target: .relative(.next)),
            ).run(.defaultEnv, .emptyStdin).exitCode,
            0,
        )

        _ = workspace1.focusWorkspace()
        Workspace.reconcileWorkspaceState()

        XCTAssertNil(Workspace.existing(byName: "2"))
        XCTAssertEqual(workspaceDisplayName("1"), "Tab 1")
    }

    func testDirectWorkspaceShortcutUsesCurrentFolderDisplayIndexWhenProjectsAreHardDisabled() async throws {
        let defaultWorkspace = Workspace.get(byName: "1")
        defaultWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 51, parent: defaultWorkspace.rootTilingContainer)
        let project = createWorkspaceProject()
        let projectFirst = try XCTUnwrap(switchWorkspaceProject(project.id, on: mainMonitor))
        projectFirst.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 56, parent: projectFirst.rootTilingContainer)
        let projectSecond = Workspace.get(byName: "folder-second")
        projectSecond.markAsAutomaticallyNamed()
        projectSecond.assignProject(project.id)
        projectSecond.seedMonitorIfNeeded(mainMonitor)
        XCTAssertTrue(TestWindow.new(id: 57, parent: projectSecond.rootTilingContainer).focusWindow())
        XCTAssertTrue(projectFirst.focusWorkspace())

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertTrue(focus.workspace === projectSecond)
        XCTAssertEqual(focus.workspace.projectId, project.id)
        XCTAssertEqual(workspaceDisplayName(focus.workspace.name), "Tab 2")
    }

    func testDirectWorkspaceShortcutCreatesMonitorLocalAdjacentTabWhenProjectsAreHardDisabled() async throws {
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
        let mainFirst = Workspace.get(byName: "main-first")
        mainFirst.markAsAutomaticallyNamed()
        mainFirst.seedMonitorIfNeeded(main)
        _ = TestWindow.new(id: 52, parent: mainFirst.rootTilingContainer)
        let mainSecond = Workspace.get(byName: "main-second")
        mainSecond.markAsAutomaticallyNamed()
        mainSecond.seedMonitorIfNeeded(main)
        _ = TestWindow.new(id: 53, parent: mainSecond.rootTilingContainer)
        let secondaryFirst = Workspace.get(byName: "secondary-first")
        secondaryFirst.markAsAutomaticallyNamed()
        secondaryFirst.seedMonitorIfNeeded(secondary)
        _ = TestWindow.new(id: 57, parent: secondaryFirst.rootTilingContainer)
        XCTAssertTrue(main.setActiveWorkspace(mainFirst))
        XCTAssertTrue(secondary.setActiveWorkspace(secondaryFirst))
        XCTAssertTrue(secondaryFirst.focusWorkspace())

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertFalse(focus.workspace === mainSecond)
        XCTAssertEqual(focus.workspace.workspaceMonitor.rect.topLeftCorner, secondary.rect.topLeftCorner)
        XCTAssertEqual(workspaceDisplayName(focus.workspace.name), "Tab 2")
        XCTAssertEqual(scopedAutomaticDisplayWorkspaces(current: mainFirst), [mainFirst, mainSecond])
    }

    func testWorkspaceNextTraversesMonitorLocalTabsWhenProjectsAreHardDisabled() async throws {
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
        let mainFirst = Workspace.get(byName: "main-first")
        mainFirst.markAsAutomaticallyNamed()
        mainFirst.seedMonitorIfNeeded(main)
        _ = TestWindow.new(id: 54, parent: mainFirst.rootTilingContainer)
        let secondaryFirst = Workspace.get(byName: "secondary-first")
        secondaryFirst.markAsAutomaticallyNamed()
        secondaryFirst.seedMonitorIfNeeded(secondary)
        _ = TestWindow.new(id: 58, parent: secondaryFirst.rootTilingContainer)
        XCTAssertTrue(main.setActiveWorkspace(mainFirst))
        XCTAssertTrue(secondary.setActiveWorkspace(secondaryFirst))
        XCTAssertTrue(secondaryFirst.focusWorkspace())

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .relative(.next)),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(focus.workspace.workspaceMonitor.rect.topLeftCorner, secondary.rect.topLeftCorner)
        XCTAssertEqual(workspaceDisplayName(focus.workspace.name), "Tab 2")
    }

    func testWorkspaceNextCreatesDefaultFolderTabAfterBottomDefaultFolderWhenProjectsDisabled() async throws {
        let defaultWorkspace = Workspace.get(byName: "1")
        defaultWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 59, parent: defaultWorkspace.rootTilingContainer)
        let project = createWorkspaceProject()
        let projectWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: mainMonitor))
        projectWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 60, parent: projectWorkspace.rootTilingContainer)
        _ = defaultWorkspace.focusWorkspace()
        config.enableProjects = false

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .relative(.next)),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace.projectId, workspaceProjectDefaultId)
        XCTAssertFalse(focus.workspace === projectWorkspace)
        XCTAssertTrue(focus.workspace.usesAutomaticDisplayName)
    }

    func testWorkspaceNextIgnoresOtherMonitorTabsWhenProjectsDisabled() async throws {
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
        let mainFirst = Workspace.get(byName: "main-first")
        mainFirst.markAsAutomaticallyNamed()
        mainFirst.seedMonitorIfNeeded(main)
        _ = TestWindow.new(id: 64, parent: mainFirst.rootTilingContainer)
        let mainSecond = Workspace.get(byName: "main-second")
        mainSecond.markAsAutomaticallyNamed()
        mainSecond.seedMonitorIfNeeded(main)
        _ = TestWindow.new(id: 65, parent: mainSecond.rootTilingContainer)
        let secondaryTab = Workspace.get(byName: "secondary-tab")
        secondaryTab.markAsAutomaticallyNamed()
        secondaryTab.seedMonitorIfNeeded(secondary)
        _ = TestWindow.new(id: 66, parent: secondaryTab.rootTilingContainer)
        XCTAssertTrue(main.setActiveWorkspace(mainFirst))
        XCTAssertTrue(secondary.setActiveWorkspace(secondaryTab))
        XCTAssertTrue(mainFirst.focusWorkspace())

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .relative(.next)),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertTrue(focus.workspace === mainSecond)
        XCTAssertEqual(focus.workspace.workspaceMonitor.rect.topLeftCorner, main.rect.topLeftCorner)
    }

    func testDirectWorkspaceShortcutUsesRootTabDisplayIndexWhenProjectsDisabled() async throws {
        let defaultWorkspace = Workspace.get(byName: "1")
        defaultWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 61, parent: defaultWorkspace.rootTilingContainer)
        let project = createWorkspaceProject()
        let projectWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: mainMonitor))
        projectWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 62, parent: projectWorkspace.rootTilingContainer)
        _ = defaultWorkspace.focusWorkspace()
        config.enableProjects = false

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertFalse(focus.workspace === projectWorkspace)
        XCTAssertEqual(focus.workspace.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(workspaceDisplayName(focus.workspace.name), "Tab 2")
    }

    func testWorkspaceNextCreatesCurrentFolderWorkspaceWhenProjectsDisabled() async throws {
        let project = createWorkspaceProject()
        let projectWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: mainMonitor))
        projectWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 63, parent: projectWorkspace.rootTilingContainer)
        _ = projectWorkspace.focusWorkspace()
        config.enableProjects = false

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .relative(.next)),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace.projectId, project.id)
    }

    func testWorkspaceNextDoesNotCreateBlankWorkspaceWhenWrapping() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 6, parent: workspace1.rootTilingContainer)
        _ = workspace1.focusWorkspace()

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .relative(.next), wrapAround: true),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace, workspace1)
        XCTAssertNil(Workspace.existing(byName: "2"))
    }

    func testDirectWorkspaceFocusDoesNotCreateConfiguredPersistentWorkspace() async throws {
        config.persistentWorkspaces = ["2"]

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertNil(Workspace.existing(byName: "2"))
    }

    func testDirectWorkspaceFocusIgnoresWorkspaceWithOnlyMacosFullscreenWindows() async throws {
        let initialWorkspace = focus.workspace
        let hiddenWorkspace = Workspace.get(byName: "2")
        _ = TestWindow.new(id: 10, parent: hiddenWorkspace.macOsNativeFullscreenWindowsContainer)

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertEqual(focus.workspace, initialWorkspace)
    }

    func testWorkspaceSwitchRefreshesClosedWindowsCacheVisibleWorkspaceSnapshot() async throws {
        let workspace1 = Workspace.get(byName: "1")
        let window1 = TestWindow.new(id: 11, parent: workspace1.rootTilingContainer)
        let workspace2 = Workspace.get(byName: "2")
        _ = TestWindow.new(id: 12, parent: workspace2.rootTilingContainer)
        _ = workspace1.focusWorkspace()
        replaceClosedWindowsCache(snapshotCurrentFrozenWorld())

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(mainMonitor.activeWorkspace, workspace2)

        let didRestore = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window1)

        XCTAssertTrue(didRestore)
        XCTAssertEqual(mainMonitor.activeWorkspace, workspace2)
    }

    func testWorkspaceNextUsesCurrentWorkspacePositionWhenFilteredStdinOmitsIt() async throws {
        let workspace1 = Workspace.get(byName: "1")
        _ = TestWindow.new(id: 21, parent: workspace1.rootTilingContainer)
        let workspace2 = Workspace.get(byName: "2")
        _ = TestWindow.new(id: 22, parent: workspace2.rootTilingContainer)
        let workspace3 = Workspace.get(byName: "3")
        let workspace4 = Workspace.get(byName: "4")
        _ = TestWindow.new(id: 24, parent: workspace4.rootTilingContainer)
        let workspace5 = Workspace.get(byName: "5")
        _ = TestWindow.new(id: 25, parent: workspace5.rootTilingContainer)
        _ = workspace3.focusWorkspace()

        let result = try await parseCommand("workspace --stdin next").cmdOrDie.run(
            .defaultEnv,
            CmdStdin("1\n2\n4\n5"),
        )

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace, workspace4)
    }

    func testWorkspacePrevUsesCurrentWorkspacePositionWhenFilteredStdinOmitsIt() async throws {
        let workspace1 = Workspace.get(byName: "1")
        _ = TestWindow.new(id: 31, parent: workspace1.rootTilingContainer)
        let workspace2 = Workspace.get(byName: "2")
        _ = TestWindow.new(id: 32, parent: workspace2.rootTilingContainer)
        let workspace3 = Workspace.get(byName: "3")
        let workspace4 = Workspace.get(byName: "4")
        _ = TestWindow.new(id: 34, parent: workspace4.rootTilingContainer)
        let workspace5 = Workspace.get(byName: "5")
        _ = TestWindow.new(id: 35, parent: workspace5.rootTilingContainer)
        _ = workspace3.focusWorkspace()

        let result = try await parseCommand("workspace --stdin prev").cmdOrDie.run(
            .defaultEnv,
            CmdStdin("1\n2\n4\n5"),
        )

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace, workspace2)
    }

    func testWorkspaceNextDeduplicatesStdinWorkspaceList() async throws {
        let workspace1 = Workspace.get(byName: "1")
        _ = TestWindow.new(id: 41, parent: workspace1.rootTilingContainer)
        let workspace2 = Workspace.get(byName: "2")
        _ = TestWindow.new(id: 42, parent: workspace2.rootTilingContainer)
        let workspace3 = Workspace.get(byName: "3")
        _ = TestWindow.new(id: 43, parent: workspace3.rootTilingContainer)
        _ = workspace2.focusWorkspace()

        let result = try await parseCommand("workspace --stdin next").cmdOrDie.run(
            .defaultEnv,
            CmdStdin("1\n2\n2\n3"),
        )

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace, workspace3)
    }
}
