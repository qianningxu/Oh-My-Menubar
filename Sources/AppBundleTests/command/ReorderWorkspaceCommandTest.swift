@testable import AppBundle
import Common
import XCTest

@MainActor
final class ReorderWorkspaceCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParseReorderWorkspaceCommand() {
        testParseCommandSucc(
            "reorder-workspace 3 --before 2",
            ReorderWorkspaceCmdArgs(source: .parse("3").getOrDie(), beforeTarget: .parse("2").getOrDie())
        )
        testParseCommandSucc(
            "reorder-tab 3 --before 2",
            ReorderWorkspaceCmdArgs(source: .parse("3").getOrDie(), beforeTarget: .parse("2").getOrDie())
        )
        testParseCommandSucc(
            "reorder-workspace 1 --after 2",
            ReorderWorkspaceCmdArgs(source: .parse("1").getOrDie(), afterTarget: .parse("2").getOrDie())
        )
        assertEquals(parseCommand("reorder-workspace 1").errorOrNil, "Either --before or --after is required")
        assertEquals(parseCommand("reorder-workspace 1 --before 2 --after 3").errorOrNil, "ERROR: Conflicting options: --after, --before")
    }

    func testHelpIsTabFirstWhileKeepingWorkspaceCompatibility() {
        guard case .help(let help) = parseCommand("reorder-workspace --help") else {
            XCTFail("Expected help")
            return
        }

        XCTAssertTrue(help.contains("USAGE: reorder-tab"))
        XCTAssertFalse(help.contains("OR: reorder-workspace"))
    }

    func testReorderWorkspaceCommandMovesSourceBeforeTarget() async throws {
        let (first, second, third) = makeOrderedDefaultWorkspaces()

        let result = try await ReorderWorkspaceCommand(
            args: ReorderWorkspaceCmdArgs(
                source: .parse(third.name).getOrDie(),
                beforeTarget: .parse(second.name).getOrDie()
            )
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(projectWorkspaces(projectId: workspaceProjectDefaultId).map(\.name), [
            first.name,
            third.name,
            second.name,
        ])
    }

    func testReorderWorkspaceCommandRejectsMissingTarget() async throws {
        let (first, second, third) = makeOrderedDefaultWorkspaces()

        let result = try await ReorderWorkspaceCommand(
            args: ReorderWorkspaceCmdArgs(
                source: .parse(first.name).getOrDie(),
                afterTarget: .parse("missing").getOrDie()
            )
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertEqual(result.stderr, ["Tab 'missing' doesn't exist"])
        XCTAssertEqual(projectWorkspaces(projectId: workspaceProjectDefaultId).map(\.name), [
            first.name,
            second.name,
            third.name,
        ])
    }

    func testReorderWorkspaceCommandUsesExplicitFolderInNonMainProject() async throws {
        let project = createWorkspaceProject()
        let first = projectWorkspaces(projectId: project.id).first.orDie()
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 7, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "project-second")
        second.assignProject(project.id)
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 8, parent: second.rootTilingContainer)

        let result = try await ReorderWorkspaceCommand(
            args: ReorderWorkspaceCmdArgs(
                source: .parse(second.name).getOrDie(),
                beforeTarget: .parse(first.name).getOrDie()
            )
        ).run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(projectWorkspaces(projectId: project.id).map(\.name), [second.name, first.name])
    }

    func testReorderWorkspaceCommandRejectsTabsFromDifferentProjects() async throws {
        let first = focus.workspace
        let project = createWorkspaceProject()
        let second = projectWorkspaces(projectId: project.id).first.orDie()
        second.markAsAutomaticallyNamed()
        let third = Workspace.get(byName: "third")
        third.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 4, parent: first.rootTilingContainer)
        _ = TestWindow.new(id: 5, parent: second.rootTilingContainer)
        _ = TestWindow.new(id: 6, parent: third.rootTilingContainer)
        setProjectWorkspaceOrder(workspaceProjectDefaultId, [first, third])

        let result = try await ReorderWorkspaceCommand(
            args: ReorderWorkspaceCmdArgs(
                source: .parse(second.name).getOrDie(),
                beforeTarget: .parse(third.name).getOrDie()
            )
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertEqual(result.stderr, [
            "Tabs '\(workspaceDisplayName(second.name))' and '\(workspaceDisplayName(third.name))' cannot be reordered together"
        ])
    }

    private func makeOrderedDefaultWorkspaces() -> (Workspace, Workspace, Workspace) {
        let first = focus.workspace
        let second = Workspace.get(byName: "second")
        let third = Workspace.get(byName: "third")
        _ = TestWindow.new(id: 1, parent: first.rootTilingContainer)
        _ = TestWindow.new(id: 2, parent: second.rootTilingContainer)
        _ = TestWindow.new(id: 3, parent: third.rootTilingContainer)
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
        var folder = winMuxWorkspaceState.workspaceFoldersById[folderId].orDie()
        folder.workspaceOrder = workspaces.map(\.id)
        winMuxWorkspaceState.workspaceFoldersById[folderId] = folder
    }
}
