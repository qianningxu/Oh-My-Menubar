@testable import AppBundle
import Common
import XCTest

@MainActor
final class CloseCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testSimple() async throws {
        Workspace.get(byName: name).rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(focus.workspace.rootTilingContainer.children.count, 2)

        try await CloseCommand(args: CloseCmdArgs(rawArgs: [])).run(.defaultEnv, .emptyStdin)

        assertEquals(focus.windowOrNil?.windowId, 2)
        assertEquals(focus.workspace.rootTilingContainer.children.count, 1)
    }

    func testCloseViaWindowIdFlag() async throws {
        Workspace.get(byName: name).rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(focus.workspace.rootTilingContainer.children.count, 2)

        try await CloseCommand(args: CloseCmdArgs(rawArgs: []).copy(\.windowId, 2)).run(.defaultEnv, .emptyStdin)

        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(focus.workspace.rootTilingContainer.children.count, 1)
    }

    func testClosingOnlyWindowDeletesTab() async throws {
        let survivingWorkspace = focus.workspace
        survivingWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 3, parent: survivingWorkspace.rootTilingContainer)
        let closingWorkspace = Workspace.get(byName: "2")
        closingWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 4, parent: closingWorkspace.rootTilingContainer).focusWindow()

        try await CloseCommand(args: CloseCmdArgs(rawArgs: [])).run(.defaultEnv, .emptyStdin)

        XCTAssertNil(Workspace.existing(byName: closingWorkspace.name))
        XCTAssertTrue(focus.workspace === survivingWorkspace)
        XCTAssertEqual(focus.windowOrNil?.windowId, 3)
    }

    func testClosingOnlyWindowKeepsPersistentTab() async throws {
        let workspace = focus.workspace
        config.persistentWorkspaces = [workspace.name]
        _ = TestWindow.new(id: 5, parent: workspace.rootTilingContainer).focusWindow()

        try await CloseCommand(args: CloseCmdArgs(rawArgs: [])).run(.defaultEnv, .emptyStdin)

        XCTAssertTrue(Workspace.existing(byName: workspace.name) === workspace)
        XCTAssertTrue(workspace.isEffectivelyEmpty)
        XCTAssertTrue(focus.workspace === workspace)
    }
}
