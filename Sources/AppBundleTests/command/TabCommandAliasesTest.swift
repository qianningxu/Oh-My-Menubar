@testable import AppBundle
import XCTest

final class TabCommandAliasesTest: XCTestCase {
    func testPrimaryTabCommandsParseAndDescribeAsTabFirst() {
        assertParses("flatten-tab-tree --tab 1", as: FlattenWorkspaceTreeCommand.self, describedWithPrefix: "flatten-tab-tree")
        assertParses("list-tabs --all", as: ListWorkspacesCommand.self, describedWithPrefix: "list-tabs")
        assertParses("move-node-to-tab next", as: MoveNodeToWorkspaceCommand.self, describedWithPrefix: "move-node-to-tab")
        assertParses("move-tab-to-monitor next", as: MoveWorkspaceToMonitorCommand.self, describedWithPrefix: "move-tab-to-monitor")
        assertParses("new-tab", as: NewTabCommand.self, describedWithPrefix: "new-tab")
        assertParses("reorder-tab 3 --before 2", as: ReorderWorkspaceCommand.self, describedWithPrefix: "reorder-tab")
        assertParses("summon-tab 2", as: SummonWorkspaceCommand.self, describedWithPrefix: "summon-tab")
        assertParses("tab next", as: WorkspaceCommand.self, describedWithPrefix: "tab")
        assertParses("tab-back-and-forth", as: WorkspaceBackAndForthCommand.self, describedWithPrefix: "tab-back-and-forth")
    }

    func testLegacyWorkspaceCommandsParseButDescribeAsTabFirst() {
        assertParses("flatten-workspace-tree --workspace 1", as: FlattenWorkspaceTreeCommand.self, describedWithPrefix: "flatten-tab-tree")
        assertParses("list-workspaces --all", as: ListWorkspacesCommand.self, describedWithPrefix: "list-tabs")
        assertParses("move-node-to-workspace next", as: MoveNodeToWorkspaceCommand.self, describedWithPrefix: "move-node-to-tab")
        assertParses("move-workspace-to-monitor next", as: MoveWorkspaceToMonitorCommand.self, describedWithPrefix: "move-tab-to-monitor")
        assertParses("reorder-workspace 3 --before 2", as: ReorderWorkspaceCommand.self, describedWithPrefix: "reorder-tab")
        assertParses("summon-workspace 2", as: SummonWorkspaceCommand.self, describedWithPrefix: "summon-tab")
        assertParses("workspace next", as: WorkspaceCommand.self, describedWithPrefix: "tab")
        assertParses("workspace-back-and-forth", as: WorkspaceBackAndForthCommand.self, describedWithPrefix: "tab-back-and-forth")
    }

    private func assertParses<T>(
        _ raw: String,
        as _: T.Type,
        describedWithPrefix expectedPrefix: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let command = parseCommand(raw).cmdOrNil else {
            XCTFail("Expected '\(raw)' to parse", file: file, line: line)
            return
        }
        XCTAssertTrue(command is T, "Expected \(T.self), got \(type(of: command))", file: file, line: line)
        XCTAssertTrue(
            command.args.description.hasPrefix(expectedPrefix),
            "Expected description for '\(raw)' to start with '\(expectedPrefix)', got '\(command.args.description)'",
            file: file,
            line: line
        )
    }
}
