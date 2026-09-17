@testable import AppBundle
import Common
import XCTest

// todo write tests
//
// test 1
//     horizontal
//         window1
//         vertical
//             vertical
//                 window2 <-- focused
//             vertical
//                 window5
//                 horizontal
//                     window3
//                     window4
// pre-condition: focus_wrapping force_workspace
// action: focus up
// expected: mru(window3, window4) is focused

@MainActor
final class FocusCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        XCTAssertTrue(parseCommand("focus --boundaries left").errorOrNil?.contains("Possible values") == true)
        var expected = FocusCmdArgs(rawArgs: [], targetArg: .direction(.left))
        expected.rawBoundaries = .workspace
        testParseCommandSucc("focus --boundaries workspace left", expected)
        expected.rawBoundaries = .tab
        testParseCommandSucc("focus --boundaries tab left", expected)

        expected = FocusCmdArgs(rawArgs: [], targetArg: .tabRelative(.tabNext))
        testParseCommandSucc("focus tab-next", expected)
        expected.rawBoundaries = .tab
        testParseCommandSucc("focus --boundaries tab tab-next", expected)
        expected.rawBoundaries = .workspace
        testParseCommandSucc("focus --boundaries workspace tab-next", expected)
        testParseCommandSucc("focus --tab-index 2", FocusCmdArgs(rawArgs: [], tabIndex: 2))

        assertEquals(
            parseCommand("focus --boundaries workspace --boundaries workspace left").errorOrNil,
            "ERROR: Duplicated option '--boundaries'",
        )
        assertEquals(
            parseCommand("focus --window-id 42 --ignore-floating").errorOrNil,
            "--window-id is incompatible with other options",
        )
        assertEquals(
            parseCommand("focus --boundaries all-monitors-outer-frame dfs-next").errorOrNil,
            "Relative window, pane, and stack focus only supports the current tab boundary (--boundaries tab)",
        )
        assertEquals(
            parseCommand("focus --boundaries all-monitors-outer-frame tab-next").errorOrNil,
            "Relative window, pane, and stack focus only supports the current tab boundary (--boundaries tab)",
        )

        assertEquals(
            parseCommand("focus --window-id 42 --wrap-around").errorOrNil,
            "--window-id is incompatible with other options",
        )
        assertEquals(
            parseCommand("focus --tab-index 2 --wrap-around").errorOrNil,
            "--tab-index is incompatible with other options",
        )
        assertEquals(
            parseCommand("focus left --boundaries-action wrap-around-the-workspace --wrap-around").errorOrNil,
            "ERROR: Conflicting options: --boundaries-action, --wrap-around",
        )
    }

    func testFocus() {
        assertEquals(focus.windowOrNil, nil)
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0)
        }
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusOverFloatingWindows() async throws {
        assertEquals(focus.windowOrNil, nil)
        Workspace.get(byName: name).apply {
            TestWindow.new(id: 1, parent: $0, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
            assertEquals(TestWindow.new(id: 2, parent: $0, rect: Rect(topLeftX: 10, topLeftY: 10, width: 100, height: 100)).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0, rect: Rect(topLeftX: 20, topLeftY: 20, width: 100, height: 100))
        }

        assertEquals(focus.windowOrNil?.windowId, 2)
        try await FocusCommand.new(direction: .right).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
    }

    func testFocusAlongTheContainerOrientation() async throws {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)
        try await FocusCommand.new(direction: .right).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusAcrossTheContainerOrientation() async throws {
        Workspace.get(byName: name).apply {
            TestWindow.new(id: 1, parent: $0.rootTilingContainer)
            TestWindow.new(id: 2, parent: $0.rootTilingContainer)
            assertEquals($0.focusWorkspace(), true)
        }

        assertEquals(focus.windowOrNil?.windowId, 2)
        try await FocusCommand.new(direction: .up).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
        try await FocusCommand.new(direction: .down).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusNoWrapping() async throws {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)
        try await FocusCommand.new(direction: .left).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusWrapping() async throws {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)
        var args = FocusCmdArgs(rawArgs: [], targetArg: .direction(.left))
        args.rawBoundaries = .workspace
        args.rawBoundariesAction = .wrapAroundTheWorkspace
        try await FocusCommand(args: args).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusFindMruLeaf() async throws {
        let workspace = Workspace.get(byName: name)
        var startWindow: Window!
        var window2: Window!
        var window3: Window!
        var unrelatedWindow: Window!
        workspace.rootTilingContainer.apply {
            startWindow = TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    window2 = TestWindow.new(id: 2, parent: $0)
                    unrelatedWindow = TestWindow.new(id: 5, parent: $0)
                }
                window3 = TestWindow.new(id: 3, parent: $0)
            }
        }

        assertEquals(workspace.mostRecentWindowRecursive?.windowId, 3) // The latest bound
        _ = startWindow.focusWindow()
        try await FocusCommand.new(direction: .right).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)

        window2.markAsMostRecentChild()
        _ = startWindow.focusWindow()
        try await FocusCommand.new(direction: .right).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)

        window3.markAsMostRecentChild()
        unrelatedWindow.markAsMostRecentChild()
        _ = startWindow.focusWindow()
        try await FocusCommand.new(direction: .right).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusOutsideOfTheContainer() async throws {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            }
        }

        try await FocusCommand.new(direction: .left).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusOutsideOfTheContainer2() async throws {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            }
        }

        try await FocusCommand.new(direction: .left).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusDfsRelative() async throws {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    TestWindow.new(id: 2, parent: $0)
                    TestWindow.new(id: 3, parent: $0)
                }
            }
            TestWindow.new(id: 4, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)

        try await FocusCommand.new(dfsRelative: .dfsNext).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
        try await FocusCommand.new(dfsRelative: .dfsNext).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
        try await FocusCommand.new(dfsRelative: .dfsNext).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 4)

        try await FocusCommand.new(dfsRelative: .dfsPrev).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
        try await FocusCommand.new(dfsRelative: .dfsPrev).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
        try await FocusCommand.new(dfsRelative: .dfsPrev).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusDfsRelativeWrapping() async throws {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)

        var args = FocusCmdArgs(rawArgs: [], targetArg: .dfsRelative(.dfsPrev))

        args.rawBoundariesAction = .stop
        assertEquals(try await FocusCommand(args: args).run(.defaultEnv, .emptyStdin).exitCode, 0)
        assertEquals(focus.windowOrNil?.windowId, 1)

        args.rawBoundariesAction = .fail
        assertEquals(try await FocusCommand(args: args).run(.defaultEnv, .emptyStdin).exitCode, 1)
        assertEquals(focus.windowOrNil?.windowId, 1)

        args.rawBoundariesAction = .wrapAroundTheWorkspace
        assertEquals(try await FocusCommand(args: args).run(.defaultEnv, .emptyStdin).exitCode, 0)
        assertEquals(focus.windowOrNil?.windowId, 2)

        args.targetArg = .dfsRelative(.dfsNext)

        args.rawBoundariesAction = .stop
        assertEquals(try await FocusCommand(args: args).run(.defaultEnv, .emptyStdin).exitCode, 0)
        assertEquals(focus.windowOrNil?.windowId, 2)

        args.rawBoundariesAction = .fail
        assertEquals(try await FocusCommand(args: args).run(.defaultEnv, .emptyStdin).exitCode, 1)
        assertEquals(focus.windowOrNil?.windowId, 2)

        args.rawBoundariesAction = .wrapAroundTheWorkspace
        assertEquals(try await FocusCommand(args: args).run(.defaultEnv, .emptyStdin).exitCode, 0)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusTabRelativeStaysInsideActiveTabComposedLayout() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        var middleWindow: Window!
        var lastWindow: Window!
        root.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1, index: INDEX_BIND_LAST).apply {
                TestWindow.new(id: 2, parent: $0)
                middleWindow = TestWindow.new(id: 3, parent: $0)
                lastWindow = TestWindow.new(id: 4, parent: $0)
            }
            TestWindow.new(id: 5, parent: $0)
        }

        XCTAssertTrue(middleWindow.focusWindow())

        try await FocusCommand.new(tabRelative: .tabNext).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(focus.windowOrNil?.windowId, lastWindow.windowId)
    }

    func testFocusTabRelativeWrapsInsideActiveTabComposedLayout() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        var firstWindow: Window!
        var lastWindow: Window!
        root.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1, index: INDEX_BIND_LAST).apply {
                firstWindow = TestWindow.new(id: 1, parent: $0)
                TestWindow.new(id: 2, parent: $0)
                lastWindow = TestWindow.new(id: 3, parent: $0)
            }
        }

        XCTAssertTrue(lastWindow.focusWindow())

        var args = FocusCmdArgs(rawArgs: [], targetArg: .tabRelative(.tabNext))
        args.rawBoundariesAction = .wrapAroundTheWorkspace
        let exitCode = try await FocusCommand(args: args).run(.defaultEnv, .emptyStdin).exitCode
        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(focus.windowOrNil?.windowId, firstWindow.windowId)
    }

    func testFocusTabRelativeFailsAtActiveTabBoundaryWhenRequested() async throws {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
        }
        XCTAssertTrue(Window.get(byId: 2).orDie().focusWindow())

        var args = FocusCmdArgs(rawArgs: [], targetArg: .tabRelative(.tabNext))
        args.rawBoundariesAction = .fail

        let exitCode = try await FocusCommand(args: args).run(.defaultEnv, .emptyStdin).exitCode
        XCTAssertEqual(exitCode, 1)
        XCTAssertEqual(focus.windowOrNil?.windowId, 2)
    }

    func testFocusTabIndexTargetsSpecificComposedWindowInsideActiveTab() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        var firstWindow: Window!
        var secondWindow: Window!
        root.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1, index: INDEX_BIND_LAST).apply {
                firstWindow = TestWindow.new(id: 1, parent: $0)
                secondWindow = TestWindow.new(id: 2, parent: $0)
                _ = TestWindow.new(id: 3, parent: $0)
            }
        }

        XCTAssertTrue(firstWindow.focusWindow())

        let exitCode = try await FocusCommand(args: FocusCmdArgs(rawArgs: [], tabIndex: 2)).run(.defaultEnv, .emptyStdin).exitCode
        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(focus.windowOrNil?.windowId, secondWindow.windowId)
    }

    func testFocusTabRelativeIgnoresLegacyTabGroupScope() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        var legacySecondWindow: Window!
        var nextComposedWindow: Window!
        root.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer(parent: $0, adaptiveWeight: 1, .v, .tabGroup, index: INDEX_BIND_LAST).apply {
                TestWindow.new(id: 2, parent: $0)
                legacySecondWindow = TestWindow.new(id: 3, parent: $0)
            }
            nextComposedWindow = TestWindow.new(id: 4, parent: $0)
        }

        XCTAssertTrue(legacySecondWindow.focusWindow())

        try await FocusCommand.new(tabRelative: .tabNext).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(focus.windowOrNil?.windowId, nextComposedWindow.windowId)
    }
}

extension FocusCommand {
    static func new(direction: CardinalDirection) -> FocusCommand {
        FocusCommand(args: FocusCmdArgs(rawArgs: [], targetArg: .direction(direction)))
    }
    static func new(dfsRelative: DfsNextPrev) -> FocusCommand {
        FocusCommand(args: FocusCmdArgs(rawArgs: [], targetArg: .dfsRelative(dfsRelative)))
    }
    static func new(tabRelative: TabNextPrev) -> FocusCommand {
        FocusCommand(args: FocusCmdArgs(rawArgs: [], targetArg: .tabRelative(tabRelative)))
    }
}
