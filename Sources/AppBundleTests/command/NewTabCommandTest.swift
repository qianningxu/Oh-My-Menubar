@testable import AppBundle
import Common
import XCTest

@MainActor
final class NewTabCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParseNewTabCommand() {
        testParseCommandSucc("new-tab", NewTabCmdArgs(rawArgs: []))
    }

    func testNewTabAlwaysCreatesFreshBlankTabAfterCurrentTab() async throws {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 1, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "2")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 2, parent: second.rootTilingContainer)
        _ = first.focusWorkspace()

        let result = try await NewTabCommand(args: NewTabCmdArgs(rawArgs: [])).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertNotEqual(focus.workspace, first)
        XCTAssertNotEqual(focus.workspace, second)
        XCTAssertTrue(focus.workspace.isEffectivelyEmpty)
        XCTAssertEqual(focus.workspace.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(focus.workspace.workspaceMonitor.rect.topLeftCorner, first.workspaceMonitor.rect.topLeftCorner)
        XCTAssertEqual(workspaceDisplayName(focus.workspace.name), "Tab 2")
        XCTAssertEqual(
            orderedWorkspacesForPresentation().filter { !$0.isArchived }.map(\.name),
            [first.name, focus.workspace.name, second.name]
        )
    }

    func testNewTabRootTabsPresentAfterSidebarFolders() async throws {
        let root = Workspace.get(byName: "root")
        root.assignProject(workspaceProjectDefaultId)
        root.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 3, parent: root.rootTilingContainer)
        let folder = createWorkspaceFolder()
        let folderTab = Workspace.get(byName: "folder-tab")
        folderTab.assignFolder(folder.id)
        folderTab.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 4, parent: folderTab.rootTilingContainer)
        winMuxWorkspaceState.workspaceFoldersById[workspaceFolderDefaultId]?.workspaceOrder = [root.id]
        winMuxWorkspaceState.workspaceFoldersById[folder.id]?.workspaceOrder = [folderTab.id]
        XCTAssertTrue(root.focusWorkspace())

        let result = try await NewTabCommand(args: NewTabCmdArgs(rawArgs: [])).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(
            orderedWorkspacesForPresentation().filter { !$0.isArchived }.map(\.name),
            [folderTab.name, root.name, focus.workspace.name]
        )
    }

    func testNewTabCreatesFreshBlankTabInCurrentFolder() async throws {
        let folder = createWorkspaceFolder()
        let folderTab = Workspace.get(byName: "folder-tab")
        folderTab.assignFolder(folder.id)
        folderTab.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 5, parent: folderTab.rootTilingContainer)
        XCTAssertTrue(folderTab.focusWorkspace())

        let result = try await NewTabCommand(args: NewTabCmdArgs(rawArgs: [])).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(focus.workspace.folderId, folder.id)
        XCTAssertEqual(
            folderWorkspaces(folderId: folder.id).map(\.name),
            [folderTab.name, focus.workspace.name]
        )
    }
}
