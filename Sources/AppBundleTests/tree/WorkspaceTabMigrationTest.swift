@testable import AppBundle
import XCTest

@MainActor
final class WorkspaceTabMigrationTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testRootTabGroupChildrenBecomeSeparateWorkspaceTabs() {
        let workspace = Workspace.get(byName: "1")
        workspace.markAsAutomaticallyNamed()
        let root = workspace.rootTilingContainer
        root.layout = .tabGroup
        let first = TestWindow.new(id: 1, parent: root)
        let second = TestWindow.new(id: 2, parent: root)
        second.markAsMostRecentChild()
        XCTAssertTrue(workspace.focusWorkspace())

        Workspace.reconcileWorkspaceState()

        let workspaces = orderedWorkspacesForPresentation()
            .filter { !$0.isArchived && workspaceHasSidebarVisibleWindows($0) }
        XCTAssertEqual(workspaces.count, 2)
        XCTAssertTrue(workspace.rootTilingContainer.children.contains(second))
        XCTAssertEqual(workspace.rootTilingContainer.layout, .tiles)
        XCTAssertTrue(second.nodeWorkspace === workspace)
        XCTAssertTrue(first.nodeWorkspace !== workspace)
        XCTAssertEqual(first.nodeWorkspace?.rootTilingContainer.children, [first])
        XCTAssertFalse(Workspace.all.contains { $0.rootTilingContainer.layout == .tabGroup && $0.rootTilingContainer.children.count > 1 })
    }

    func testWindowTabsKeepTabGroupsDuringWorkspaceReconciliation() {
        config.windowTabs.enabled = true
        let workspace = Workspace.get(byName: "1")
        let root = workspace.rootTilingContainer
        root.layout = .tabGroup
        let first = TestWindow.new(id: 1, parent: root)
        let second = TestWindow.new(id: 2, parent: root)
        second.markAsMostRecentChild()

        Workspace.reconcileWorkspaceState()

        XCTAssertEqual(root.layout, .tabGroup)
        XCTAssertEqual(root.children, [first, second])
        XCTAssertTrue(first.nodeWorkspace === workspace)
        XCTAssertTrue(second.nodeWorkspace === workspace)
    }

    func testRootTabGroupMigrationPreservesOldTabOrderButKeepsActiveChildInOriginalTab() {
        let workspace = Workspace.get(byName: "1")
        workspace.markAsAutomaticallyNamed()
        let root = workspace.rootTilingContainer
        root.layout = .tabGroup
        let first = TestWindow.new(id: 1, parent: root)
        let active = TestWindow.new(id: 2, parent: root)
        let third = TestWindow.new(id: 3, parent: root)
        active.markAsMostRecentChild()
        XCTAssertTrue(workspace.focusWorkspace())

        Workspace.reconcileWorkspaceState()

        let migratedTabs = orderedWorkspacesForPresentation()
            .filter { !$0.isArchived && workspaceHasSidebarVisibleWindows($0) }
        XCTAssertEqual(migratedTabs.compactMap(\.rootTilingContainer.anyLeafWindowRecursive?.windowId), [
            first.windowId,
            active.windowId,
            third.windowId,
        ])
        XCTAssertTrue(active.nodeWorkspace === workspace)
        XCTAssertTrue(workspace.workspaceMonitor.activeWorkspace === workspace)
    }

    func testNestedTabGroupChildComposedLayoutIsPreservedAsWorkspaceTab() {
        let workspace = Workspace.get(byName: "1")
        workspace.markAsAutomaticallyNamed()
        let root = workspace.rootTilingContainer
        let leading = TestWindow.new(id: 1, parent: root)
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let composed = TilingContainer(parent: tabGroup, adaptiveWeight: WEIGHT_AUTO, .h, .tiles, index: INDEX_BIND_LAST)
        let splitA = TestWindow.new(id: 2, parent: composed)
        let splitB = TestWindow.new(id: 3, parent: composed)
        let active = TestWindow.new(id: 4, parent: tabGroup)
        active.markAsMostRecentChild()
        XCTAssertTrue(workspace.focusWorkspace())

        Workspace.reconcileWorkspaceState()

        XCTAssertEqual(workspace.rootTilingContainer.layoutDescription, .h_tiles([
            .window(1),
            .window(4),
        ]))
        XCTAssertTrue(leading.nodeWorkspace === workspace)
        XCTAssertTrue(active.nodeWorkspace === workspace)
        XCTAssertTrue(splitA.nodeWorkspace === splitB.nodeWorkspace)
        XCTAssertTrue(splitA.nodeWorkspace !== workspace)
        XCTAssertEqual(splitA.nodeWorkspace?.rootTilingContainer.layoutDescription, .h_tiles([
            .h_tiles([
                .window(2),
                .window(3),
            ]),
        ]))
    }

    func testRootSingleChildTabGroupShellIsRemovedDuringMigration() {
        let workspace = Workspace.get(byName: "1")
        workspace.markAsAutomaticallyNamed()
        let root = workspace.rootTilingContainer
        root.layout = .tabGroup
        let window = TestWindow.new(id: 1, parent: root)

        Workspace.reconcileWorkspaceState()

        XCTAssertEqual(root.layout, .tiles)
        XCTAssertEqual(root.children, [window])
        XCTAssertFalse(Workspace.all.contains { workspace in
            workspace.rootTilingContainer.allTabbedContainersRecursive.contains { $0.layout == .tabGroup }
        })
    }

    func testNestedSingleChildTabGroupShellIsUnwrappedDuringMigration() {
        let workspace = Workspace.get(byName: "1")
        workspace.markAsAutomaticallyNamed()
        let root = workspace.rootTilingContainer
        let leading = TestWindow.new(id: 1, parent: root)
        let shell = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let nested = TestWindow.new(id: 2, parent: shell)

        Workspace.reconcileWorkspaceState()

        XCTAssertEqual(root.layoutDescription, .h_tiles([
            .window(1),
            .window(2),
        ]))
        XCTAssertTrue(leading.nodeWorkspace === workspace)
        XCTAssertTrue(nested.nodeWorkspace === workspace)
        XCTAssertFalse(root.allTabbedContainersRecursive.contains { $0.layout == .tabGroup })
    }

    func testProjectsCanBeEnabledForWorkspaceTabs() {
        config.enableProjects = true

        XCTAssertTrue(projectsAreEnabled())
        XCTAssertEqual(buildWorkspaceSidebarProjectViewModels().map(\.id), [workspaceProjectDefaultId])
    }
}
