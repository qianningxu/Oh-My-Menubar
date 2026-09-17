@testable import AppBundle
import XCTest

@MainActor
final class DebugWindowsCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testDebugWindowTabNameUsesTabDisplayNameBesideLegacyWorkspaceName() {
        let workspace = Workspace.get(byName: "10")
        workspace.markAsAutomaticallyNamed()
        let window = TestWindow.new(id: 42, parent: workspace.rootTilingContainer)

        XCTAssertEqual(winMuxDebugTabName(for: window), "Tab 1")
        XCTAssertEqual(window.nodeWorkspace?.name, "10")
    }
}
