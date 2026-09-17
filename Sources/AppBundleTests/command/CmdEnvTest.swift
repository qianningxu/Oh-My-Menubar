@testable import AppBundle
import Common
import XCTest

@MainActor
final class CmdEnvTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testWindowFocusEnvIncludesTabAliasBesideWindowId() {
        let workspace = focus.workspace
        let window = TestWindow.new(id: 27, parent: workspace.rootTilingContainer)
        let env = CmdEnv.defaultEnv
            .withFocus(LiveFocus(windowOrNil: window, workspace: workspace))
            .asMap

        XCTAssertEqual(env[WINMUX_WINDOW_ID], "27")
        XCTAssertEqual(env[WINMUX_TAB], workspace.name)
        XCTAssertEqual(env[WINMUX_WORKSPACE], workspace.name)
    }

    func testFocusedTabEnvAliasIsSetBesideLegacyWorkspaceEnv() {
        let env = CmdEnv.defaultEnv
            .copy(\.windowId, 12)
            .copy(\.workspaceName, "2")
            .asMap

        XCTAssertEqual(env[WINMUX_WINDOW_ID], "12")
        XCTAssertEqual(env[WINMUX_TAB], "2")
        XCTAssertEqual(env[WINMUX_WORKSPACE], "2")
    }
}
