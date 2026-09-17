struct WorkspaceSidebarFolderViewModel: Hashable, Identifiable {
    let id: WorkspaceFolderId
    let projectId: WorkspaceProjectId
    let displayName: String
    let colorHex: String?
    let isUnfolded: Bool
}
