@MainActor
func buildWorkspaceSidebarProjectViewModels() -> [WorkspaceSidebarProjectViewModel] {
    buildWorkspaceSidebarProjectViewModels(from: workspaceProjects())
}

@MainActor
func buildWorkspaceSidebarProjectViewModels(
    from projects: [WorkspaceProject]
) -> [WorkspaceSidebarProjectViewModel] {
    projects.map {
        WorkspaceSidebarProjectViewModel(
            id: $0.id,
            displayName: $0.name,
            colorHex: config.workspaceSidebar.projectColors[$0.id.rawValue].flatMap(normalizedWorkspaceSidebarColorHex),
        )
    }
}

@MainActor
func buildWorkspaceSidebarFolderViewModels() -> [WorkspaceSidebarFolderViewModel] {
    buildWorkspaceSidebarFolderViewModels(from: workspaceFolders())
}

@MainActor
func buildWorkspaceSidebarFolderViewModels(
    from folders: [WorkspaceFolder]
) -> [WorkspaceSidebarFolderViewModel] {
    folders.map { folder in
        WorkspaceSidebarFolderViewModel(
            id: folder.id,
            projectId: folder.projectId,
            displayName: folder.name,
            colorHex: config.workspaceSidebar.folderColors[folder.id.rawValue]
                .flatMap(normalizedWorkspaceSidebarColorHex),
            isUnfolded: folder.id == winMuxWorkspaceState.projectsById[folder.projectId]?.unfoldedFolderId
        )
    }
}
