import AppKit
import SwiftUI

extension WindowTabStripView {
    func tabItem(
        _ tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
        itemHeight: CGFloat,
    ) -> some View {
        let isHovered = hoveredTabId == tab.windowId
        let isEditing = editingTabId == tab.windowId
        let projectDestinations = projectDestinations(for: tab)
        return ZStack(alignment: .trailing) {
            if isEditing {
                tabRenameEditor(tab, context: context, itemHeight: itemHeight)
            } else {
                tabButton(tab, context: context, itemHeight: itemHeight, isHovered: isHovered)
            }

            if isHovered && draggingTabId == nil && !isEditing && context.showsTabTitles {
                tabCloseButton(tab)
                    .padding(.trailing, windowTabStripCloseButtonTrailingInset)
                    .transition(.opacity)
            }
        }
        .frame(width: context.tabWidth, height: itemHeight, alignment: .leading)
        .offset(x: tabVisualOffset(for: tab, context: context))
        // Keep hit thresholds on stationary slots while their contents move.
        .background {
            GeometryReader { proxy in
                WinMuxDesignTokens.transparent.preference(
                    key: WindowTabStripTabFramePreferenceKey.self,
                    value: [tab.windowId: proxy.frame(in: .named(context.scrollCoordinateSpaceName))],
                )
            }
        }
        .zIndex(draggingTabId == tab.windowId || isEditing ? 1 : 0)
        .transaction { $0.animation = nil }
        .onHover { hovering in
            updateHoveredTab(tab.windowId, hovering: hovering)
        }
        .overlay {
            WorkspaceSidebarNativeContextMenu(
                items: [
                    .init(title: "Rename tab") { beginRenamingTab(tab) },
                ] + (projectDestinations.isEmpty ? [] : [
                    .init(title: "Move to project", children: projectDestinations.map { project in
                        .init(title: project.displayName) {
                            moveWindowToProjectFromTabStrip(tab.windowId, projectId: project.id)
                        }
                    }),
                ]),
                colorScheme: barColorScheme
            )
        }
    }

    private func tabButton(
        _ tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
        itemHeight: CGFloat,
        isHovered: Bool,
    ) -> some View {
        Button {
            guard !isWindowTabStripDragInProgress() else { return }
            if NSApp.currentEvent?.clickCount == 2 {
                beginRenamingTab(tab)
            } else {
                focusWindowFromTabStripClick(tab.windowId, fallbackWorkspace: tab.workspaceName)
            }
        } label: {
            WindowTabItemView(
                tab: tab,
                width: context.tabWidth,
                height: itemHeight,
                isDragSource: draggingTabId == tab.windowId,
                isHovered: isHovered,
                showsTitle: context.showsTabTitles,
                reservesCloseButtonSpace: context.showsTabTitles
            )
        }
        .buttonStyle(.plain)
        .highPriorityGesture(tabDragGesture(for: tab, context: context))
    }

    private func tabRenameEditor(
        _ tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
        itemHeight: CGFloat,
    ) -> some View {
        ZStack(alignment: .leading) {
            WindowTabItemView(
                tab: tab,
                width: context.tabWidth,
                height: itemHeight,
                isDragSource: false,
                isHovered: true,
                showsTitle: true,
                reservesCloseButtonSpace: false,
                hidesTitle: true
            )
            WindowTabRenameTextField(
                text: $editingTabTitle,
                onCommit: { commitRenamingTab(tab) },
                onCancel: cancelRenamingTab,
            )
            .padding(.leading, WinMuxBarStyle.contentInset + workspaceSidebarAppIconSize + 2 + WinMuxBarStyle.iconSpacing)
            .padding(.trailing, WinMuxBarStyle.contentInset)
            .frame(width: context.tabWidth, height: itemHeight, alignment: .leading)
        }
    }

    func beginRenamingTab(_ tab: WindowTabItemViewModel) {
        guard !isWindowTabStripDragInProgress(), draggingTabId == nil else { return }
        editingTabId = tab.windowId
        editingTabTitle = tab.title
    }

    func commitRenamingTab(_ tab: WindowTabItemViewModel) {
        let nextTitle = editingTabTitle
        editingTabId = nil
        editingTabTitle = ""
        renameWindowTabFromTabStrip(tab.windowId, displayName: nextTitle, fallbackWorkspace: tab.workspaceName)
    }

    func cancelRenamingTab() {
        editingTabId = nil
        editingTabTitle = ""
    }

    private func projectDestinations(
        for tab: WindowTabItemViewModel
    ) -> [WorkspaceSidebarProjectViewModel] {
        guard let currentProjectId = trayModel.workspaceSidebarWorkspaces
            .first(where: { $0.name == tab.workspaceName })?
            .projectId
        else { return [] }
        return workspaceSidebarProjectDestinations(
            projects: trayModel.workspaceSidebarProjects,
            currentProjectId: currentProjectId,
        )
    }

    private func tabCloseButton(_ tab: WindowTabItemViewModel) -> some View {
        Button {
            closeWindowFromTabStrip(tab.windowId, fallbackWorkspace: tab.workspaceName)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(winMuxBarForeground(palette))
                .frame(width: windowTabStripCloseButtonSize, height: windowTabStripCloseButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Close \(tab.title)")
        .accessibilityLabel("Close \(tab.title)")
    }
}
