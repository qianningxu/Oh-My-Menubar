@testable import AppBundle
import Common
import XCTest

@MainActor
final class GlobalFloatingWindowsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testFloatingWindowHasNoWorkspaceAndFollowsDisplayFocus() {
        let original = Workspace.get(byName: name)
        let window = TestWindow.new(id: 91001, parent: original.rootTilingContainer)
        window.bindAsFloatingWindow(to: original)
        XCTAssertNil(window.nodeWorkspace)
        XCTAssertTrue(window.isFloating)
        XCTAssertFalse(original.allLeafWindowsRecursive.contains(window))
        let next = Workspace.get(byName: "global-float-next")
        XCTAssertTrue(mainMonitor.setActiveWorkspace(next))
        XCTAssertTrue(window.focusWindow())
        XCTAssertEqual(mainMonitor.activeWorkspace, next)
        XCTAssertNil(window.nodeWorkspace)
    }

    func testGlobalFloatRestoresOutsideWorkspaceTree() async throws {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 91002, parent: workspace.rootTilingContainer)
        window.bindAsFloatingWindow(to: workspace)
        let snapshot = snapshotCurrentFrozenWorld()
        XCTAssertEqual(snapshot.globalFloatingWindows?.map(\.id), [window.windowId])
        window.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        let restored = try await restoreFrozenWorldIfNeeded(snapshot, newlyDetectedWindow: window)
        XCTAssertTrue(restored)
        XCTAssertNil(window.nodeWorkspace)
        XCTAssertTrue(window.isFloating)
    }
}
