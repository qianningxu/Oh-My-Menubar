@testable import AppBundle
import XCTest

@MainActor
final class WorkspaceSidebarProjectHierarchyTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testSidebarModelExposesRealProjectsAndProjectOwnedFolders() async {
        config.enableProjects = true
        let project = createWorkspaceProject()
        let folder = createWorkspaceFolder(in: project.id)
        let tab = Workspace.get(byName: "project-tab")
        tab.markAsAutomaticallyNamed()
        tab.assignFolder(folder.id)
        _ = TestWindow.new(id: 101, parent: tab.rootTilingContainer)

        let state = await buildWorkspaceSidebarModelState()

        XCTAssertEqual(state.projects.map(\.id), [workspaceProjectDefaultId, project.id])
        XCTAssertEqual(
            state.folders.filter { $0.projectId == project.id }.map(\.id),
            [folder.id, project.unfoldedFolderId]
        )
        XCTAssertEqual(state.workspaces.first { $0.name == tab.name }?.projectId, project.id)
        XCTAssertEqual(state.workspaces.first { $0.name == tab.name }?.folderId, folder.id)
    }

    func testPanelSnapshotIncludesProjectOwnedFoldersFromTrayModel() {
        let model = TrayMenuModel()
        let projectId = WorkspaceProjectId("client")
        let folder = WorkspaceSidebarFolderViewModel(
            id: "client-folder",
            projectId: projectId,
            displayName: "Client Folder",
            colorHex: "#7BA3C9",
            isUnfolded: false
        )
        model.workspaceSidebarFolders = [folder]

        let snapshot = workspaceSidebarSnapshot(from: model)

        XCTAssertEqual(snapshot.folders, [folder])
    }

    func testFolderSectionsContainOnlyTheRequestedProjectsFolders() {
        let mainFolder = WorkspaceSidebarFolderViewModel(
            id: "main-folder",
            projectId: workspaceProjectDefaultId,
            displayName: "Main Folder",
            colorHex: nil,
            isUnfolded: false
        )
        let mainUnfolded = WorkspaceSidebarFolderViewModel(
            id: workspaceFolderDefaultId,
            projectId: workspaceProjectDefaultId,
            displayName: workspaceDefaultFolderDisplayName,
            colorHex: nil,
            isUnfolded: true
        )
        let otherProjectId = WorkspaceProjectId("other")
        let otherFolder = WorkspaceSidebarFolderViewModel(
            id: "other-folder",
            projectId: otherProjectId,
            displayName: "Other Folder",
            colorHex: nil,
            isUnfolded: false
        )
        let workspaces = [
            sidebarWorkspace("main-tab", projectId: workspaceProjectDefaultId, folderId: mainFolder.id),
            sidebarWorkspace("other-tab", projectId: otherProjectId, folderId: otherFolder.id),
        ]

        let sections = workspaceSidebarFolderSections(
            projectId: workspaceProjectDefaultId,
            workspaces: workspaces,
            folders: [mainFolder, otherFolder, mainUnfolded]
        )

        XCTAssertEqual(sections.map(\.id), [mainFolder.id, mainUnfolded.id])
        XCTAssertEqual(sections[0].workspaces.map(\.name), ["main-tab"])
        XCTAssertTrue(sections[1].workspaces.isEmpty)
    }

    func testFilteringPreservesExplicitFolderIdentity() {
        let folderId = WorkspaceFolderId("client-folder")
        let workspace = sidebarWorkspace(
            "client-tab",
            projectId: workspaceProjectDefaultId,
            folderId: folderId
        )

        let filtered = workspaceSidebarFilteredWorkspacesByProject(
            [workspaceProjectDefaultId: [workspace]],
            projects: [],
            query: "client"
        )[workspaceProjectDefaultId]

        XCTAssertEqual(filtered?.first?.folderId, folderId)
    }

    func testProjectFolderOrderKeepsUnfoldedLast() {
        let project = createWorkspaceProject()
        let first = createWorkspaceFolder(in: project.id)
        let second = createWorkspaceFolder(in: project.id)

        XCTAssertEqual(
            workspaceFolders(in: project.id).map(\.id),
            [first.id, second.id, project.unfoldedFolderId]
        )
    }

    func testMoveToProjectDestinationsExcludeCurrentProject() {
        let main = WorkspaceSidebarProjectViewModel(
            id: workspaceProjectDefaultId,
            displayName: "Main",
            colorHex: nil
        )
        let client = WorkspaceSidebarProjectViewModel(
            id: "client",
            displayName: "Client",
            colorHex: nil
        )
        let personal = WorkspaceSidebarProjectViewModel(
            id: "personal",
            displayName: "Personal",
            colorHex: nil
        )

        XCTAssertEqual(
            workspaceSidebarProjectDestinations(
                projects: [main, client, personal],
                currentProjectId: client.id
            ).map(\.id),
            [main.id, personal.id]
        )
    }

    func testNewProjectNameTrimsWhitespaceAndRejectsBlankInput() {
        XCTAssertEqual(workspaceSidebarNewProjectName("  Client Work  "), "Client Work")
        XCTAssertNil(workspaceSidebarNewProjectName(" \n\t "))
    }

    func testTopLeftProjectPopupExcludesCurrentProjectAndUsesCompactMetrics() {
        let main = WorkspaceSidebarProjectViewModel(
            id: workspaceProjectDefaultId,
            displayName: "Main",
            colorHex: nil
        )
        let client = WorkspaceSidebarProjectViewModel(
            id: "client",
            displayName: "Client",
            colorHex: "#006BFF"
        )
        let personal = WorkspaceSidebarProjectViewModel(
            id: "personal",
            displayName: "Personal",
            colorHex: nil
        )

        let popupProjects = workspaceSidebarProjectPopupProjects(
            [main, client, personal],
            excluding: client.id
        )

        XCTAssertEqual(popupProjects.map(\.id), [main.id, personal.id])
        XCTAssertEqual(workspaceSidebarProjectPopupRowHeight, 26)
        XCTAssertEqual(workspaceSidebarProjectPopupCornerRadius, 8)
        XCTAssertLessThanOrEqual(
            workspaceSidebarProjectPopupWidth(projects: popupProjects),
            workspaceSidebarProjectPopupMaximumWidth
        )
        XCTAssertLessThan(
            workspaceSidebarProjectPopupWidth(projects: popupProjects),
            200
        )
    }

    func testConfiguredProjectColorFlowsIntoSidebarSnapshot() async {
        config.enableProjects = true
        let project = createWorkspaceProject()
        config.workspaceSidebar.projectColors[project.id.rawValue] = "#006BFF"

        let state = await buildWorkspaceSidebarModelState()

        XCTAssertEqual(
            state.projects.first { $0.id == project.id }?.colorHex,
            "#006BFF"
        )
    }

    func testProjectColorPresetsUseGeistHighContrastAccentRoles() {
        XCTAssertEqual(
            workspaceSidebarProjectColorPresets.map(\.hex),
            ["#8F8F8F", "#006BFF", "#E5484D", "#FFAE00", "#28A948", "#00AC96", "#A000F8", "#F22782"]
        )
        XCTAssertEqual(
            workspaceSidebarProjectColorPresets.map(\.name),
            ["Gray", "Blue", "Red", "Amber", "Green", "Teal", "Purple", "Pink"]
        )
    }

    func testProjectSwitchingDoesNotChangeSharedWidgetConfiguration() {
        var widget = WorkspaceSidebarWidgetConfig()
        widget.id = "shared-tasks"
        widget.type = .builtInTasks
        config.workspaceSidebar.widgets = [widget]
        let project = createWorkspaceProject()
        let before = workspaceSidebarConfiguration().widgets

        XCTAssertNotNil(switchWorkspaceProject(project.id, on: mainMonitor))

        XCTAssertEqual(workspaceSidebarConfiguration().widgets, before)
        XCTAssertEqual(config.workspaceSidebar.widgets, [widget])
    }

    func testSelectorOnlySurfaceDisablesPagerAndSwipeCapture() {
        XCTAssertFalse(workspaceSidebarShouldShowProjectPager(projectsEnabled: true, isCompact: false))
        XCTAssertFalse(workspaceSidebarShouldShowProjectPager(projectsEnabled: true, isCompact: true))
        XCTAssertFalse(workspaceSidebarProjectSwipeCaptureIsEnabled(
            projectsEnabled: true,
            projectCount: 3,
            isCompact: false
        ))
    }

    private func sidebarWorkspace(
        _ name: String,
        projectId: WorkspaceProjectId,
        folderId: WorkspaceFolderId
    ) -> WorkspaceSidebarWorkspaceViewModel {
        WorkspaceSidebarWorkspaceViewModel(
            name: name,
            projectId: projectId,
            folderId: folderId,
            displayName: name,
            sidebarLabel: "",
            isGeneratedName: true,
            tabSummary: WorkspaceSidebarTabSummaryViewModel(
                title: name,
                subtitle: nil,
                appBundleId: nil,
                appBundlePath: nil,
                windowCount: 1,
                isEmpty: false
            ),
            monitorScopeId: workspaceSidebarDefaultScopeId,
            monitorName: nil,
            isFocused: false,
            isVisible: false,
            items: []
        )
    }
}
