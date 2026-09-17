import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    @ViewBuilder
    var interactiveSectionContent: some View {
        if isCompact {
            Button(action: handleSectionClick) {
                sectionContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .contentShape(sectionShape)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(sectionShape)
        } else {
            sectionContent.contentShape(sectionShape)
        }
    }

    var sectionContent: some View {
        VStack(alignment: .leading, spacing: workspaceSidebarNestedRowSpacing) {
            headerSlot
                .frame(height: headerHeight)
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
                .contentShape(Rectangle())
                .contextMenu {
                    tabContextMenuItems
                }
            windowRows
            dropPreviewRow
        }
    }

    @ViewBuilder
    var headerSlot: some View {
        if isCompact {
            header
                .frame(height: headerHeight)
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .modifier(WorkspaceSidebarWorkspaceReorderGestureModifier(
                    isEnabled: isWorkspaceReorderEnabled,
                    onChanged: onWorkspaceReorderDragChanged,
                    onEnded: onWorkspaceReorderDragEnded
                ))
        } else {
            expandedHeaderSlot
        }
    }

    var expandedHeaderSlot: some View {
        ZStack(alignment: .trailing) {
            headerButton
                .frame(height: headerHeight)

            if isHeaderCloseButtonVisible {
                workspaceTabCloseButton()
                    .padding(.trailing, workspaceSidebarWindowCloseButtonTrailingInset)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .frame(height: headerHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(WorkspaceSidebarWorkspaceReorderGestureModifier(
            isEnabled: isWorkspaceReorderEnabled && !shouldShowComposedExpandedHeader,
            onChanged: onWorkspaceReorderDragChanged,
            onEnded: onWorkspaceReorderDragEnded
        ))
    }
}
