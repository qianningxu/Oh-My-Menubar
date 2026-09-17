import SwiftUI

extension WorkspaceSidebarProjectPager {
    @ViewBuilder
    func projectDot(
        _ project: WorkspaceSidebarProjectViewModel,
        index: Int,
    ) -> some View {
        let isCurrent = index == currentIndex
        let isDotHovered = hoveredProjectDotId == project.id
        let projectColor = workspaceSidebarProjectColor(projectId: project.id, configuredHex: project.colorHex)
        let projectMuted = workspaceSidebarProjectColor(projectId: project.id, configuredHex: project.colorHex, step: .color4)
        let projectHover = workspaceSidebarProjectColor(projectId: project.id, configuredHex: project.colorHex, step: .color5)
        let projectActive = workspaceSidebarProjectColor(projectId: project.id, configuredHex: project.colorHex, step: .color6)
        let projectStrong = workspaceSidebarProjectColor(projectId: project.id, configuredHex: project.colorHex, step: .color8)
        Button {
            debugWorkspaceSidebarProjectLog(
                "dotButton project=\(project.id.rawValue) selected=\(selectedProjectId.rawValue) currentIndex=\(currentIndex?.description ?? "nil") compact=\(isCompact) projects=\(projects.map(\.id.rawValue))"
            )
            projectTrackScrollTargetId = project.id
            onSelectProject(project.id)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isDotHovered ? workspaceSidebarProjectColor(projectId: project.id, configuredHex: project.colorHex, step: .color2) : WinMuxDesignTokens.transparent)
                    .frame(width: 34, height: 22)
                Capsule(style: .continuous)
                    .fill(isCurrent ? projectColor : (isDotHovered ? projectActive : (isHovered ? projectHover : projectMuted)))
                    .frame(width: isCurrent ? 28 : 13, height: isCompact ? 10 : 9)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isCurrent ? projectStrong : (isDotHovered ? projectActive : (isHovered ? projectHover : projectMuted)),
                                lineWidth: isDotHovered || isCurrent ? 0.8 : 0.5,
                            )
                    }
                }
                .frame(width: 36, height: workspaceSidebarProjectDotFrameHeight, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(project.displayName)
        .help(project.displayName)
        .onHover { hovering in
            hoveredProjectDotId = hovering ? project.id : (hoveredProjectDotId == project.id ? nil : hoveredProjectDotId)
        }
        .contextMenu {
            projectContextMenuItems(for: project)
        }
        .animation(.easeOut(duration: 0.18), value: isCurrent)
        .animation(.easeOut(duration: 0.14), value: isDotHovered)
    }
}
