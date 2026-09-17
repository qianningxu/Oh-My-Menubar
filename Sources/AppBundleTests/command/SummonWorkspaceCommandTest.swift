@testable import AppBundle
import Common
import XCTest

@MainActor
final class SummonWorkspaceCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        assertEquals(parseCommand("summon-workspace").errorOrNil, "ERROR: Argument '<tab>' is mandatory")
        assertEquals(parseCommand("summon-tab").errorOrNil, "ERROR: Argument '<tab>' is mandatory")
        assertNotNil(parseCommand("summon-tab 2").cmdOrNil)
    }

    func testHelpIsTabFirstWhileKeepingWorkspaceCompatibility() {
        guard case .help(let help) = parseCommand("summon-workspace --help") else {
            XCTFail("Expected help")
            return
        }

        XCTAssertTrue(help.contains("USAGE: summon-tab"))
        XCTAssertFalse(help.contains("OR: summon-workspace"))
    }

    func testSummonDoesNotCreateMissingWorkspace() async throws {
        let args = SummonWorkspaceCmdArgs(rawArgs: [])
            .copy(\.target, .initialized(.parse("2").getOrDie()))
        let result = try await SummonWorkspaceCommand(args: args).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertNil(Workspace.existing(byName: "2"))
    }

    func testSummonIgnoresWorkspaceWithOnlyMacosHiddenWindows() async throws {
        let initialWorkspace = focus.workspace
        let hiddenWorkspace = Workspace.get(byName: "2")
        _ = TestWindow.new(id: 11, parent: hiddenWorkspace.macOsNativeHiddenAppsWindowsContainer)

        let args = SummonWorkspaceCmdArgs(rawArgs: [])
            .copy(\.target, .initialized(.parse("2").getOrDie()))
        let result = try await SummonWorkspaceCommand(args: args).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertEqual(focus.workspace, initialWorkspace)
    }
}
