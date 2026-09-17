@testable import AppBundle
import XCTest

@MainActor
final class WorkspaceSidebarProjectCreationTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testNewProjectSurvivesCleanupWithoutChangingFocus() async throws {
        let previousWorkspace = focus.workspace
        _ = TestWindow.new(id: 1, parent: previousWorkspace.rootTilingContainer)
        let previousProjects = Set(workspaceProjects().map(\.id))

        await createWorkspaceSidebarProject()?.value

        pruneEmptyWorkspaceProjects()
        let project = try XCTUnwrap(workspaceProjects().first { !previousProjects.contains($0.id) })
        XCTAssertEqual(activeWorkspaceProjectId(for: mainMonitor), previousWorkspace.projectId)
        XCTAssertTrue(focus.workspace === previousWorkspace)
        XCTAssertEqual(projectWorkspaces(projectId: project.id).count, 1)
    }

    func testNamedProjectIsCreatedWithoutChangingFocus() async throws {
        let previousWorkspace = focus.workspace
        _ = TestWindow.new(id: 2, parent: previousWorkspace.rootTilingContainer)
        await createWorkspaceSidebarProject(displayName: "  Writing  ")?.value

        let project = try XCTUnwrap(workspaceProjects().first { $0.name == "Writing" })
        XCTAssertNotEqual(project.id, previousWorkspace.projectId)
        XCTAssertTrue(focus.workspace === previousWorkspace)
    }
}
