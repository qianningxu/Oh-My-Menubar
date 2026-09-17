enum WorkspaceSidebarSearchSelection: Hashable {
    case workspace(String)
}

func workspaceSidebarSearchSelections(
    workspaces: [WorkspaceSidebarWorkspaceViewModel],
) -> [WorkspaceSidebarSearchSelection] {
    workspaces.map { .workspace($0.name) }
}
