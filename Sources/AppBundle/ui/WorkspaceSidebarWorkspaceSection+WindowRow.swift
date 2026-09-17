import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    func workspaceWindowButton(
        _ window: WorkspaceSidebarWindowViewModel,
        allowsDrag: Bool,
        subject: WindowDragSubject = .window,
        leadingHitInset: CGFloat = standardGap * 0,
        rowHeightOverride: CGFloat? = nil,
    ) -> some View {
        let isPointerHovered = hoveredWindowId == window.windowId
        let isRowHovered = isPointerHovered
        let resolvedRowHeight = rowHeightOverride ?? rowHeight
        let rowStyle: WorkspaceSidebarWindowRow.Style = leadingHitInset > 0 ? .tabGroupChild : .window
        return ZStack(alignment: .trailing) {
            Button {
                guard allowsWorkspaceActivation else { return }
                guard shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) else { return }
                if isInUseOnOtherDisplay {
                    activeInUseOverrideWorkspaceName = workspace.name
                    return
                }
                activeInUseOverrideWorkspaceName = nil
                onBeginWorkspaceActivation(workspace.name)
                actions.send(.selectWindow(window.windowId))
            } label: {
                WorkspaceSidebarWindowRow(
                    title: window.title ?? window.appName,
                    badge: nil,
                    isFocused: window.isFocused,
                    suppressFocusedStyle: isSearchFiltering,
                    rowHeight: resolvedRowHeight,
                    isHovered: isRowHovered,
                    isActiveInteraction: activeSidebarDragSourceWindowId == window.windowId,
                    style: rowStyle,
                    appBundleIds: [window.appBundleId],
                    appBundlePaths: [window.appBundlePath],
                    reservesCloseButtonSpace: true,
                    leadingContentInset: 0,
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(WorkspaceSidebarTabRowButtonStyle())
            .padding(.leading, leadingHitInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .workspaceSidebarDrag(enabled: allowsDrag) {
                let payload: WorkspaceSidebarDragPayload = subject == .group
                    ? .tabGroup(window.windowId)
                    : .window(window.windowId)
                return payload.itemProvider
            }

            if isPointerHovered {
                workspaceWindowCloseButton(window)
                    .padding(.trailing, workspaceSidebarWindowCloseButtonTrailingInset)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(WorkspaceSidebarOptionalDragModifier(
            isEnabled: allowsDrag,
            onChanged: { pointer in
                if subject == .group {
                    actions.tabGroupDragChanged(window.windowId, pointer)
                } else {
                    actions.windowDragChanged(window.windowId, pointer)
                }
            },
            onEnded: { pointer in
                if subject == .group {
                    actions.tabGroupDragEnded(window.windowId, pointer)
                } else {
                    actions.windowDragEnded(window.windowId, pointer)
                }
            },
        ))
        .onHover { hover in
            hoveredWindowId = nextWorkspaceSidebarHoveredWindowId(
                currentHoveredWindowId: hoveredWindowId,
                windowId: window.windowId,
                isHovering: hover,
            )
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.78), value: activeSidebarDragSourceWindowId == window.windowId)
    }

    func workspaceWindowCloseButton(
        _ window: WorkspaceSidebarWindowViewModel,
    ) -> some View {
        Button {
            actions.send(.closeWindow(window.windowId))
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(palette.content(.secondary))
                .frame(width: workspaceSidebarWindowCloseButtonSize, height: workspaceSidebarWindowCloseButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Close \(window.title ?? window.appName)")
        .accessibilityLabel("Close \(window.title ?? window.appName)")
    }

    func workspaceTabCloseButton() -> some View {
        Button {
            actions.send(.closeWorkspace(workspace.name))
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(palette.content(.secondary))
                .frame(width: workspaceSidebarWindowCloseButtonSize, height: workspaceSidebarWindowCloseButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Close \(workspace.displayName)")
        .accessibilityLabel("Close \(workspace.displayName)")
    }
}
