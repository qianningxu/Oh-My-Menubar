import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    func tabGroupHeaderButton(_ group: WorkspaceSidebarTabGroupViewModel) -> some View {
        Button {
            guard allowsWorkspaceActivation else { return }
            guard shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) else { return }
            if isInUseOnOtherDisplay {
                activeInUseOverrideWorkspaceName = workspace.name
                return
            }
            activeInUseOverrideWorkspaceName = nil
            onBeginWorkspaceActivation(workspace.name)
            actions.send(.selectWindow(group.representativeWindowId))
        } label: {
            WorkspaceSidebarWindowRow(
                title: group.title.isEmpty ? "Composed Windows" : group.title,
                badge: nil,
                isFocused: group.isFocused,
                suppressFocusedStyle: isSearchFiltering,
                rowHeight: workspaceSidebarNestedTabRowHeight,
                isHovered: hoveredTabGroupId == group.representativeWindowId,
                isActiveInteraction: activeSidebarDragSourceWindowId == group.representativeWindowId,
                style: .tabGroupHeader,
                appBundleIds: group.tabs.map(\.appBundleId),
                appBundlePaths: group.tabs.map(\.appBundlePath),
                reservesCloseButtonSpace: false,
                leadingContentInset: 0,
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(WorkspaceSidebarTabRowButtonStyle())
        .padding(.leading, workspaceSidebarTabGroupChildLeadingIndent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(WorkspaceSidebarOptionalDragModifier(
            isEnabled: true,
            onChanged: { actions.tabGroupDragChanged(group.representativeWindowId, $0) },
            onEnded: { actions.tabGroupDragEnded(group.representativeWindowId, $0) },
        ))
        .workspaceSidebarDrag(enabled: true) {
            WorkspaceSidebarDragPayload.tabGroup(group.representativeWindowId).itemProvider
        }
        .onHover { hover in
            hoveredTabGroupId = hover ? group.representativeWindowId :
                (hoveredTabGroupId == group.representativeWindowId ? nil : hoveredTabGroupId)
        }
    }
}
