import SwiftUI

extension WorkspaceSidebarProjectPopup {
    @ViewBuilder
    func projectContextMenuItems(for project: WorkspaceSidebarProjectViewModel) -> some View {
        WorkspaceSidebarProjectContextMenu(
            project: project,
            onRename: onRename,
            onSetColor: onSetColor,
            onDelete: onDelete
        )
    }
}

struct WorkspaceSidebarProjectContextMenu: View {
    let project: WorkspaceSidebarProjectViewModel
    let onRename: (WorkspaceSidebarProjectViewModel) -> Void
    let onSetColor: (WorkspaceSidebarProjectViewModel, String?) -> Void
    let onDelete: (WorkspaceSidebarProjectViewModel) -> Void

    var body: some View {
        Button("Rename project") {
            onRename(project)
        }
        if projectsAreEnabled() {
            Menu("Color") {
                let selectedColorHex = project.colorHex.flatMap(normalizedWorkspaceSidebarColorHex)
                    ?? workspaceSidebarDefaultProjectColorHex
                ForEach(workspaceSidebarProjectColorPresets) { preset in
                    Button {
                        onSetColor(project, preset.hex)
                    } label: {
                        Label {
                            Text(preset.name)
                        } icon: {
                            Image(nsImage: workspaceSidebarProjectColorSwatchImage(
                                hex: preset.hex,
                                isSelected: selectedColorHex == preset.hex
                            ))
                        }
                    }
                }
            }
        }
        Button(role: .destructive) {
            onDelete(project)
        } label: {
            Text("Delete project")
        }
        .disabled(!canDeleteWorkspaceProject(project.id))
    }
}
