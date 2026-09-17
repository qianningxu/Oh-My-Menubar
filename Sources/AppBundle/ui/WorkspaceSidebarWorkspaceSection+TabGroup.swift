import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    func workspaceTabGroupView(_ group: WorkspaceSidebarTabGroupViewModel) -> some View {
        let isDragging = activeSidebarDragSourceWindowId == group.representativeWindowId
        return VStack(alignment: .leading, spacing: workspaceSidebarNestedRowSpacing) {
            tabGroupHeaderButton(group)
            tabGroupTabs(group, isDragging: isDragging)
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.78), value: isDragging)
    }

    func tabGroupTabs(_ group: WorkspaceSidebarTabGroupViewModel, isDragging: Bool) -> some View {
        VStack(alignment: .leading, spacing: workspaceSidebarNestedRowSpacing) {
            ForEach(group.searchVisibleTabs ?? group.tabs) { tab in
                workspaceWindowButton(
                    tab,
                    allowsDrag: true,
                    subject: .window,
                    leadingHitInset: workspaceSidebarTabGroupChildLeadingIndent,
                    rowHeightOverride: workspaceSidebarNestedTabRowHeight,
                )
            }
        }
    }
}
