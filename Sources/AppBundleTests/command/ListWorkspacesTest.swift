@testable import AppBundle
import Common
import XCTest

final class ListWorkspacesTest: XCTestCase {
    func testParse() {
        assertNotNil(parseCommand("list-workspaces --all").cmdOrNil)
        assertNotNil(parseCommand("list-tabs --all").cmdOrNil)
        assertNil(parseCommand("list-workspaces --all --visible").cmdOrNil)
        assertNil(parseCommand("list-workspaces --focused --visible").cmdOrNil)
        assertNil(parseCommand("list-workspaces --focused --all").cmdOrNil)
        assertNil(parseCommand("list-workspaces --visible").cmdOrNil)
        assertNotNil(parseCommand("list-workspaces --visible --monitor 2").cmdOrNil)
        assertNotNil(parseCommand("list-tabs --visible --monitor 2").cmdOrNil)
        assertNotNil(parseCommand("list-workspaces --monitor focused").cmdOrNil)
        assertNil(parseCommand("list-workspaces --focused --monitor 2").cmdOrNil)
        assertNotNil(parseCommand("list-workspaces --all --format %{workspace}").cmdOrNil)
        assertEquals(parseCommand("list-workspaces --all --format %{workspace} --count").errorOrNil, "ERROR: Conflicting options: --count, --format")
        assertEquals(parseCommand("list-workspaces --empty").errorOrNil, "Mandatory option is not specified (--all|--focused|--monitor)")
        assertEquals(parseCommand("list-workspaces --all --focused --monitor mouse").errorOrNil, "ERROR: Conflicting options: --all, --focused, --monitor")
    }

    func testHelpUsesTabLanguageWhileKeepingCommandNameCompatible() {
        guard case .help(let help) = parseCommand("list-workspaces --help") else {
            XCTFail("Expected help")
            return
        }

        XCTAssertTrue(help.contains("USAGE: list-tabs"))
        XCTAssertFalse(help.contains("list-workspaces"))
        XCTAssertFalse(help.contains("<workspace-name>"))
    }

    @MainActor
    func testListWorkspacesUsesProjectViewportOrderInsteadOfRawNameSort() async throws {
        setUpWorkspacesForTests()
        let first = Workspace.get(byName: "10")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 1, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "2")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 2, parent: second.rootTilingContainer)

        let io = CmdIo(stdin: .emptyStdin)
        let command = parseCommand("list-workspaces --all --format %{workspace}").cmdOrDie
        let succeeded = try await command.run(.defaultEnv, io)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(io.stdout.filter { $0 != "setUpWorkspacesForTests" }, ["10", "2"])
    }

    @MainActor
    func testListWorkspacesDefaultOutputUsesTabDisplayNames() async throws {
        setUpWorkspacesForTests()
        let first = Workspace.get(byName: "10")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 1, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "2")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 2, parent: second.rootTilingContainer)

        let io = CmdIo(stdin: .emptyStdin)
        let command = parseCommand("list-workspaces --all").cmdOrDie
        let succeeded = try await command.run(.defaultEnv, io)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(io.stdout.filter { $0 != "setUpWorkspacesForTests" }, ["Tab 1", "Tab 2"])
    }

    @MainActor
    func testListWorkspacesTabFormatUsesDisplayNameAndWorkspaceFormatStaysRaw() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "10")
        workspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        let tabIo = CmdIo(stdin: .emptyStdin)
        let tabCommand = parseCommand("list-workspaces --all --format %{tab}").cmdOrDie
        let tabSucceeded = try await tabCommand.run(.defaultEnv, tabIo)

        let workspaceIo = CmdIo(stdin: .emptyStdin)
        let workspaceCommand = parseCommand("list-workspaces --all --format %{workspace}").cmdOrDie
        let workspaceSucceeded = try await workspaceCommand.run(.defaultEnv, workspaceIo)

        XCTAssertTrue(tabSucceeded)
        XCTAssertTrue(workspaceSucceeded)
        XCTAssertEqual(tabIo.stdout.filter { $0 != "setUpWorkspacesForTests" }, ["Tab 1"])
        XCTAssertEqual(workspaceIo.stdout.filter { $0 != "setUpWorkspacesForTests" }, ["10"])
    }

    @MainActor
    func testListTabsDefaultJsonUsesTabOnly() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "10")
        workspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        let io = CmdIo(stdin: .emptyStdin)
        let command = parseCommand("list-tabs --all --json").cmdOrDie
        let succeeded = try await command.run(.defaultEnv, io)

        XCTAssertTrue(succeeded)
        let objects = try JSONSerialization.jsonObject(
            with: Data(io.stdout.joined(separator: "\n").utf8)
        ) as? [[String: Any]]
        let tab = try XCTUnwrap(objects?.first { ($0["tab"] as? String) == "Tab 1" })
        XCTAssertEqual(tab["tab"] as? String, "Tab 1")
        XCTAssertNil(tab["workspace"])
        XCTAssertEqual(Set(tab.keys), ["tab"])
    }

    @MainActor
    func testListTabsExplicitJsonFormatDoesNotAddLegacyWorkspaceKey() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "10")
        workspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        let io = CmdIo(stdin: .emptyStdin)
        let command = parseCommand("list-tabs --all --json --format %{tab}").cmdOrDie
        let succeeded = try await command.run(.defaultEnv, io)

        XCTAssertTrue(succeeded)
        let objects = try JSONSerialization.jsonObject(
            with: Data(io.stdout.joined(separator: "\n").utf8)
        ) as? [[String: Any]]
        let tab = try XCTUnwrap(objects?.first { ($0["tab"] as? String) == "Tab 1" })
        XCTAssertEqual(Set(tab.keys), ["tab"])
    }
}
