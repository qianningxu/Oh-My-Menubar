@testable import AppBundle
import XCTest

@MainActor
final class LayoutDetachedTreeTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testLayoutStopsWhenRootIsDetachedDuringWindowFrameUpdate() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let first = TestWindow.new(id: 1, parent: root)
        _ = TestWindow.new(id: 2, parent: root)
        first.onSetAxFrame = {
            first.onSetAxFrame = nil
            root.unbindFromParent()
        }

        try await workspace.layoutWorkspace()

        XCTAssertNil(root.parent)
    }
}
