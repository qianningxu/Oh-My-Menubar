@testable import AppBundle
import Common
import XCTest

@MainActor
final class FlattenWorkspaceTreeCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParseTabAlias() {
        testParseCommandSucc("flatten-tab-tree --tab 1", FlattenWorkspaceTreeCmdArgs(rawArgs: ["--tab", "1"]).copy(\.workspaceName, .parse("1").getOrDie()))
        testParseCommandSucc("flatten-workspace-tree --workspace 1", FlattenWorkspaceTreeCmdArgs(rawArgs: ["--workspace", "1"]).copy(\.workspaceName, .parse("1").getOrDie()))
    }

    func testSimple() async throws {
        let workspace = Workspace.get(byName: name).apply {
            $0.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    TestWindow.new(id: 2, parent: $0)
                }
            }
            TestWindow.new(id: 3, parent: $0) // floating
        }
        assertEquals(workspace.focusWorkspace(), true)

        try await FlattenWorkspaceTreeCommand(args: FlattenWorkspaceTreeCmdArgs(rawArgs: [])).run(.defaultEnv, .emptyStdin)
        workspace.normalizeContainers()
        assertEquals(workspace.layoutDescription, .workspace([.h_tiles([.window(1), .window(2)]), .window(3)]))
    }
}
