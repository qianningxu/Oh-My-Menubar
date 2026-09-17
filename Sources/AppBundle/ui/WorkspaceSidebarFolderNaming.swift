func workspaceSidebarFolderDisplayName(_ name: String) -> String {
    if name.hasPrefix("Project ") {
        return "Folder \(name.dropFirst("Project ".count))"
    }
    if name.hasPrefix("Group ") {
        return "Folder \(name.dropFirst("Group ".count))"
    }
    return name
}
