@testable import AppBundle
import XCTest

@MainActor
final class WorkspaceSidebarHierarchyPreparationTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testPreparationMaterializesNormalizesAndIsIdempotent() {
        let focusedWorkspace = focus.workspace
        config.workspaceSidebar.projectLabels["client"] = "Client"

        var defaultProject = winMuxWorkspaceState.projectsById[workspaceProjectDefaultId]!
        defaultProject.folderOrder = [workspaceFolderDefaultId, workspaceFolderDefaultId]
        winMuxWorkspaceState.projectsById[workspaceProjectDefaultId] = defaultProject

        var defaultFolder = winMuxWorkspaceState.workspaceFoldersById[workspaceFolderDefaultId]!
        defaultFolder.workspaceOrder = []
        winMuxWorkspaceState.workspaceFoldersById[workspaceFolderDefaultId] = defaultFolder

        let first = prepareWorkspaceSidebarHierarchyInputs()
        let workspaceIdsAfterFirstPreparation = Set(Workspace.all.map(\.id))
        let second = prepareWorkspaceSidebarHierarchyInputs()

        XCTAssertEqual(first.projects.map(\.id), [workspaceProjectDefaultId, WorkspaceProjectId("client")])
        XCTAssertEqual(
            first.folders.map(\.id),
            [workspaceFolderDefaultId, WorkspaceFolderId("unfolded-client")]
        )
        XCTAssertEqual(
            winMuxWorkspaceState.projectsById[workspaceProjectDefaultId]?.folderOrder,
            [workspaceFolderDefaultId]
        )
        XCTAssertEqual(
            winMuxWorkspaceState.workspaceFoldersById[workspaceFolderDefaultId]?.workspaceOrder,
            [focusedWorkspace.id]
        )
        XCTAssertEqual(Set(first.orderedWorkspaces.map(\.id)), workspaceIdsAfterFirstPreparation)
        XCTAssertEqual(Set(second.orderedWorkspaces.map(\.id)), workspaceIdsAfterFirstPreparation)
        XCTAssertEqual(Set(Workspace.all.map(\.id)), workspaceIdsAfterFirstPreparation)
    }
}
