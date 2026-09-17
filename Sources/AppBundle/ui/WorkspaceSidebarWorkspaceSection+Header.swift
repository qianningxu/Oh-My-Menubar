import AppKit
import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    @ViewBuilder
    var headerButton: some View {
        Group {
            if isRenamingWorkspace {
                // NSTextField cannot become the first responder while nested
                // inside a SwiftUI Button. Keep the editor outside the row's
                // activation button for the duration of the rename.
                header
            } else if !isCompact, shouldShowComposedExpandedHeader {
                header
            } else {
                Button(action: handleSectionClick) {
                    header
                        .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(WorkspaceSidebarTabRowButtonStyle())
            }
        }
        .padding(.leading, headerButtonLeadingIndent)
        .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in handleSectionDoubleClick() }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var header: some View {
        Group {
            if isCompact {
                compactTabBadge
            } else {
                expandedHeader
            }
        }
    }

    var headerButtonLeadingIndent: CGFloat {
        isCompact || nestedContentIndent <= 0 ? 0 : nestedContentIndent
    }

    var expandedHeader: some View {
        Group {
            if shouldShowComposedExpandedHeader {
                composedExpandedHeader
            } else {
                standardExpandedHeader
            }
        }
    }

    var shouldShowComposedExpandedHeader: Bool {
        workspaceSidebarShowsComposedTabHeader(
            isRenamingWorkspace: isRenamingWorkspace,
            sidebarLabel: workspace.sidebarLabel,
            hasComposedTabs: !composedHeaderTabs.isEmpty,
        )
    }

    var standardExpandedHeader: some View {
        HStack(spacing: workspaceSidebarAppIconTextSpacing) {
            expandedTabIcon
            if isRenamingWorkspace {
                WorkspaceSidebarWorkspaceRenameField(
                    text: $renamingWorkspaceText,
                    workspaceName: workspace.name,
                    onCommit: onCommitRenameWorkspace,
                    onCancel: onCancelRenameWorkspace,
                    font: NSFont.systemFont(
                        ofSize: 13.5,
                        weight: isVisuallyActiveOnTargetMonitor ? .semibold : .medium
                    ),
                )
                .layoutPriority(1)
            } else {
                VStack(alignment: .leading, spacing: standardGap * 0.5) {
                    Text(workspace.displayName)
                        .font(.system(size: 13.5, weight: isVisuallyActiveOnTargetMonitor ? .semibold : .medium))
                        .foregroundStyle(palette.content(isVisuallyActiveOnTargetMonitor ? .primary : .secondary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let subtitle = workspace.tabSummary.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(palette.content(.secondary))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .contentShape(Rectangle())
                .layoutPriority(1)
            }
            if let projectContextLabel, let projectContextColor {
                Text(projectContextLabel)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(projectContextColor)
                    .lineLimit(1)
                    .padding(.horizontal, standardGap * 2.5)
                    .frame(height: 15)
                    .background {
                        Capsule(style: .continuous)
                            .fill(palette.componentBackground(.normal))
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(palette.geistBorder(.normal), lineWidth: 0.75)
                    }
            }
            Spacer(minLength: 0)
            if workspace.tabSummary.windowCount > 0 {
                WinMuxDesignTokens.transparent
                    .frame(width: isHeaderCloseButtonVisible ? workspaceSidebarWindowCloseButtonReservedWidth : 4)
            }
        }
        .padding(.leading, workspaceSidebarRowHorizontalPadding)
        .padding(.trailing, workspaceSidebarRowHorizontalPadding)
        .frame(height: workspaceSidebarTabRowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .workspaceSidebarTabRowChrome(
            palette,
            isSelected: isHeaderRowSelected,
            isHovered: isPointerHoverVisible,
            isActiveInteraction: isHeaderRowActiveInteraction
        )
    }

    var composedExpandedHeader: some View {
        HStack(spacing: workspaceSidebarStandardGap) {
            ForEach(composedHeaderTabs) { tab in
                composedHeaderTab(tab, showsTitle: composedHeaderShowsTitles)
            }
        }
        .frame(height: workspaceSidebarTabRowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var composedHeaderTabs: [WorkspaceSidebarWindowViewModel] {
        guard workspace.tabSummary.windowCount > 1 else { return [] }
        return workspace.items.flatMap { item -> [WorkspaceSidebarWindowViewModel] in
            switch item.kind {
                case .window(let window):
                    return [window]
                case .tabGroup(let group):
                    return group.tabs
            }
        }
    }

    var composedHeaderShowsTitles: Bool {
        composedHeaderTabs.count <= 2
    }

    func composedHeaderTab(_ tab: WorkspaceSidebarWindowViewModel, showsTitle: Bool) -> some View {
        let isPointerHovered = hoveredWindowId == tab.windowId
        return ZStack(alignment: .trailing) {
            Button {
                handleComposedHeaderTabClick(tab)
            } label: {
                HStack(spacing: showsTitle ? 5 : 0) {
                    composedHeaderTabIcon(tab)
                    if showsTitle {
                        Text(composedHeaderTabTitle(tab))
                            .font(.system(size: 13.5, weight: tab.isFocused ? .semibold : .medium))
                            .foregroundStyle(palette.content(tab.isFocused ? .primary : .secondary))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.72)
                    }
                    Spacer(minLength: 0)
                    WinMuxDesignTokens.transparent
                        .frame(width: workspaceSidebarWindowCloseButtonReservedWidth)
                }
                .padding(.leading, workspaceSidebarRowHorizontalPadding)
                .padding(.trailing, workspaceSidebarWindowCloseButtonTrailingInset)
                .frame(height: workspaceSidebarTabRowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .workspaceSidebarTabRowChrome(
                    palette,
                    isSelected: tab.isFocused,
                    isHovered: isPointerHovered,
                    isActiveInteraction: activeSidebarDragSourceWindowId == tab.windowId
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(WorkspaceSidebarTabRowButtonStyle())

            if isPointerHovered {
                workspaceWindowCloseButton(tab)
                    .padding(.trailing, workspaceSidebarWindowCloseButtonTrailingInset)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in handleSectionDoubleClick() }
        )
        .workspaceSidebarDrag(enabled: true) {
            WorkspaceSidebarDragPayload.window(tab.windowId).itemProvider
        }
        .modifier(WorkspaceSidebarOptionalDragModifier(
            isEnabled: true,
            onChanged: { actions.windowDragChanged(tab.windowId, $0) },
            onEnded: { actions.windowDragEnded(tab.windowId, $0) },
        ))
        .onHover { hover in
            hoveredWindowId = nextWorkspaceSidebarHoveredWindowId(
                currentHoveredWindowId: hoveredWindowId,
                windowId: tab.windowId,
                isHovering: hover,
            )
        }
        .animation(workspaceSidebarHoverAnimation, value: isPointerHovered)
        .accessibilityLabel(composedHeaderTabTitle(tab))
    }

    @ViewBuilder
    func composedHeaderTabIcon(_ tab: WorkspaceSidebarWindowViewModel) -> some View {
        if let icon = appIconImage(
            bundleIdentifier: tab.appBundleId,
            bundlePath: tab.appBundlePath
        ) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: workspaceSidebarAppIconSize + 2, height: workspaceSidebarAppIconSize + 2)
                .cornerRadius(4)
        } else {
            Image(systemName: "macwindow")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.content(.secondary))
                .frame(width: workspaceSidebarAppIconSize + 2, height: workspaceSidebarAppIconSize + 2)
        }
    }

    func composedHeaderTabTitle(_ tab: WorkspaceSidebarWindowViewModel) -> String {
        if !tab.appName.isEmpty {
            return tab.appName
        }
        return tab.title?.takeIf { !$0.isEmpty } ?? "Window"
    }

    @ViewBuilder
    var expandedTabIcon: some View {
        if let icon = appIconImage(
            bundleIdentifier: workspace.tabSummary.appBundleId,
            bundlePath: workspace.tabSummary.appBundlePath
        ) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: workspaceSidebarAppIconSize + 2, height: workspaceSidebarAppIconSize + 2)
                .cornerRadius(4)
        }
    }

    var isHeaderRowSelected: Bool {
        !showsWindowRows && !isSearchFiltering && (isVisuallyActiveOnTargetMonitor || isPinnedActiveWorkspace)
    }

    var isHeaderRowActiveInteraction: Bool {
        isWorkspaceReorderSource ||
            isDropTarget ||
            isDropTargeted ||
            isDropSettling ||
            isSearchSelectedWorkspace ||
            isPendingActivationOnTargetMonitor
    }

    var isHeaderCloseButtonVisible: Bool {
        !shouldShowComposedExpandedHeader && workspaceSidebarTabCloseButtonIsVisible(
            isCompact: isCompact,
            isRenamingWorkspace: isRenamingWorkspace,
            isPointerHoverVisible: isPointerHoverVisible,
            windowCount: workspace.tabSummary.windowCount
        )
    }

    var compactTabBadge: some View {
        Group {
            if workspace.tabSummary.isEmpty {
                workspaceBadge
            } else {
                tabIcon
            }
        }
        .frame(width: workspaceSidebarBadgeWidth, height: workspaceSidebarBadgeWidth)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    var tabIcon: some View {
        if let icon = appIconImage(
            bundleIdentifier: workspace.tabSummary.appBundleId,
            bundlePath: workspace.tabSummary.appBundlePath
        ) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: workspaceSidebarCompactAppIconSize, height: workspaceSidebarCompactAppIconSize)
                .cornerRadius(4)
                .scaleEffect(workspaceSidebarCompactAppIconOpticalScale)
        } else {
            workspaceBadge
                .font(.system(size: 12, weight: isVisuallyActiveOnTargetMonitor ? .bold : .semibold))
                .frame(width: workspaceSidebarCompactAppIconSize, height: workspaceSidebarCompactAppIconSize)
        }
    }
}

func workspaceSidebarShowsComposedTabHeader(
    isRenamingWorkspace: Bool,
    sidebarLabel _: String,
    hasComposedTabs: Bool,
) -> Bool {
    !isRenamingWorkspace &&
        hasComposedTabs
}

func workspaceSidebarTabCloseButtonIsVisible(
    isCompact: Bool,
    isRenamingWorkspace: Bool,
    isPointerHoverVisible: Bool,
    windowCount: Int
) -> Bool {
    !isCompact && !isRenamingWorkspace && isPointerHoverVisible && windowCount > 0
}
