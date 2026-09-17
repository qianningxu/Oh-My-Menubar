@testable import AppBundle
import Common
import XCTest

@MainActor
final class ListWindowsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        assertEquals(
            parseCommand("list-windows --pid 1").errorOrNil,
            "Choose a window scope: --focused, --all, --monitor, or --tab (legacy --workspace is still accepted)"
        )
        assertNil(parseCommand("list-windows --tab M --pid 1").errorOrNil)
        assertNil(parseCommand("list-windows --workspace M --pid 1").errorOrNil)
        assertEquals(parseCommand("list-windows --pid 1 --focused").errorOrNil, "--focused conflicts with other \"filtering\" flags")
        assertEquals(parseCommand("list-windows --pid 1 --all").errorOrNil, "--all conflicts with \"filtering\" flags. Please use '--monitor all' instead of '--all' alias")
        assertNil(parseCommand("list-windows --all").errorOrNil)
        assertEquals(parseCommand("list-windows --all --tab M").errorOrNil, "ERROR: Conflicting options: --all, --tab")
        assertEquals(parseCommand("list-windows --all --workspace M").errorOrNil, "ERROR: Conflicting options: --all, --workspace")
        assertEquals(parseCommand("list-windows --all --focused").errorOrNil, "ERROR: Conflicting options: --all, --focused")
        assertEquals(parseCommand("list-windows --all --count --format %{window-title}").errorOrNil, "ERROR: Conflicting options: --count, --format")
        assertEquals(
            parseCommand("list-windows --all --focused --monitor mouse").errorOrNil,
            "ERROR: Conflicting options: --all, --focused")
        assertEquals(
            parseCommand("list-windows --all --focused --monitor mouse --workspace focused").errorOrNil,
            "ERROR: Conflicting options: --all, --focused, --workspace")
        assertEquals(
            parseCommand("list-windows --all --workspace focused").errorOrNil,
            "ERROR: Conflicting options: --all, --workspace")
        assertNil(parseCommand("list-windows --monitor mouse").errorOrNil)

        // --json
        assertEquals(parseCommand("list-windows --all --count --json").errorOrNil, "ERROR: Conflicting options: --count, --json")
        assertEquals(parseCommand("list-windows --all --format '%{right-padding}' --json").errorOrNil, "%{right-padding} interpolation variable is not allowed when --json is used")
        assertEquals(parseCommand("list-windows --all --format '%{window-title} |' --json").errorOrNil, "Only interpolation variables and spaces are allowed in \'--format\' when \'--json\' is used")
        assertNil(parseCommand("list-windows --all --format '%{window-title}' --json").errorOrNil)
    }

    func testHelpIsTabFirstWhileKeepingWorkspaceCompatibility() {
        guard case .help(let help) = parseCommand("list-windows --help") else {
            XCTFail("Expected help")
            return
        }

        XCTAssertTrue(help.contains("USAGE: list-windows [-h|--help] (--tab <tab>...|--monitor <monitor>...)"))
        XCTAssertFalse(help.contains("[--workspace <tab>...]"))
    }

    func testInterpolationVariablesConsistency() {
        for kind in FormatObjectKind.allCases {
            switch kind {
                case .window:
                    assertTrue(FormatVar.WindowFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "window-") })
                case .app:
                    assertTrue(FormatVar.AppFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "app-") })
                case .workspace:
                    assertTrue(FormatVar.WorkspaceFormatVar.allCases.allSatisfy {
                        $0.rawValue.starts(with: "workspace") || $0.rawValue.starts(with: "tab")
                    })
                case .monitor:
                    assertTrue(FormatVar.MonitorFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "monitor-") })
            }
        }
    }

    func testFormat() {
        Workspace.get(byName: name).rootTilingContainer.apply {
            let windows = [
                FormatObject.window(window: TestWindow.new(id: 2, parent: $0), title: "non-empty"),
                FormatObject.window(window: TestWindow.new(id: 1, parent: $0), title: ""),
            ]
            assertEquals(windows.format([.interVar("window-title")]), .success(["non-empty", ""]))
        }

        Workspace.get(byName: name).rootTilingContainer.apply {
            let windows = [
                FormatObject.window(window: TestWindow.new(id: 2, parent: $0), title: "non-empty"),
                FormatObject.window(window: TestWindow.new(id: 10, parent: $0), title: ""),
            ]
            assertEquals(windows.format([.interVar("window-id"), .interVar("right-padding"), .interVar("window-title")]), .success(["2 non-empty", "10"]))
        }

        Workspace.get(byName: name).rootTilingContainer.apply {
            let windows = [
                FormatObject.window(window: TestWindow.new(id: 2, parent: $0), title: "title1"),
                FormatObject.window(window: TestWindow.new(id: 10, parent: $0), title: "title2"),
            ]
            assertEquals(windows.format([.interVar("window-id"), .interVar("right-padding"), .literal(" | "), .interVar("window-title")]), .success(["2  | title1", "10 | title2"]))
        }

        Workspace.get(byName: name).rootTilingContainer.apply {
            let window = TestWindow.new(id: 42, parent: $0)
            window.unbindFromParent()

            let windows = [FormatObject.window(window: window, title: "detached")]

            assertEquals(windows.format([.interVar("workspace")]), .success(["NULL-WORKSPACE"]))
            assertEquals(windows.format([.interVar("tab")]), .success(["NULL-TAB"]))
        }
    }

    func testListWindowsAllIgnoresNonUserFacingWorkspace() async throws {
        let visibleWorkspace = Workspace.get(byName: "visible")
        visibleWorkspace.rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }
        let fullscreenOnlyWorkspace = Workspace.get(byName: "fullscreen-only")
        _ = TestWindow.new(id: 2, parent: fullscreenOnlyWorkspace.macOsNativeFullscreenWindowsContainer)

        guard let command = parseCommand("list-windows --all --count").cmdOrNil as? ListWindowsCommand else {
            XCTFail("Expected list-windows command")
            return
        }

        let result = try await command.run(.defaultEnv, .emptyStdin)

        assertEquals(result.stdout, ["1"])
    }

    func testListWindowsDefaultJsonIncludesTabDisplayNameOnly() async throws {
        let workspace = Workspace.get(byName: "10")
        workspace.markAsAutomaticallyNamed()
        workspace.rootTilingContainer.apply {
            _ = TestWindow.new(id: 42, parent: $0)
        }

        guard let command = parseCommand("list-windows --all --json").cmdOrNil as? ListWindowsCommand else {
            XCTFail("Expected list-windows command")
            return
        }

        let result = try await command.run(.defaultEnv, .emptyStdin)

        XCTAssertTrue(result.stderr.isEmpty)
        let objects = try JSONSerialization.jsonObject(
            with: Data(result.stdout.joined(separator: "\n").utf8)
        ) as? [[String: Any]]
        let window = try XCTUnwrap(objects?.first { ($0["window-id"] as? UInt32) == 42 || ($0["window-id"] as? Int) == 42 })
        XCTAssertEqual(window["tab"] as? String, "Tab 1")
        XCTAssertNil(window["workspace"])
        XCTAssertEqual(window["window-title"] as? String, "TestWindow(42)")
        XCTAssertEqual(window["app-name"] as? String, "bobko.WinMux.test-app")
    }
}
