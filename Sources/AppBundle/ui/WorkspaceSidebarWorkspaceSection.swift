import AppKit
import Common
import SwiftUI

struct WorkspaceSidebarWorkspaceSection: View {
    let workspace: WorkspaceSidebarWorkspaceViewModel
    let dragPreview: WorkspaceSidebarDropPreviewViewModel?
    let expansionProgress: CGFloat
    let layout: WorkspaceSidebarConfiguration
    let emitsDropTarget: Bool
    let isFromOtherDisplay: Bool
    let isInUseOnOtherDisplay: Bool
    let isOnFocusedMonitor: Bool
    let allowsWorkspaceActivation: Bool
    let isPinnedActiveWorkspace: Bool
    let isActiveOnTargetMonitor: Bool
    let isPendingActivationOnTargetMonitor: Bool
    let projectContextLabel: String?
    let projectContextColor: Color?
    let projectDestinations: [WorkspaceSidebarProjectViewModel]
    let nestedContentIndent: CGFloat
    let nestedContentTrailingInset: CGFloat
    @Binding var renamingWorkspaceName: String?
    @Binding var renamingWorkspaceText: String
    let onBeginRenameWorkspace: @MainActor () -> Void
    let onCommitRenameWorkspace: @MainActor () -> Void
    let onCancelRenameWorkspace: @MainActor () -> Void
    let selectedSearchTarget: WorkspaceSidebarSearchSelection?
    let isSearchFiltering: Bool
    let isWorkspaceReorderEnabled: Bool
    let isWorkspaceReorderSource: Bool
    let isWorkspaceReorderInProgress: Bool
    let onWorkspaceReorderDragChanged: (CGPoint) -> Void
    let onWorkspaceReorderDragEnded: (CGPoint) -> Void
    @Binding var activeInUseOverrideWorkspaceName: String?
    let onBeginWorkspaceActivation: @MainActor (String) -> Void
    let actions: WorkspaceSidebarActions

    @State var isHovered = false
    @State var hoveredWindowId: UInt32? = nil
    @State var hoveredTabGroupId: UInt32? = nil
    @State var isDropTargeted = false
    @State var isDropSettling = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) var projectThemeFamily

    let headerHeight: CGFloat = workspaceSidebarWorkspaceSectionHeaderHeight
    let rowHeight: CGFloat = workspaceSidebarWorkspaceRowHeight

    var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }
    var contentWidth: CGFloat { workspaceSidebarContentWidth(expansionProgress, layout: layout) }
    var sectionWidth: CGFloat {
        max(workspaceSidebarSectionWidth(expansionProgress, layout: layout) - nestedContentTrailingInset, 1)
    }
    var isCompact: Bool { expansionProgress < workspaceSidebarRowsRevealProgress }
    var showsWindowRows: Bool { false }
    var sectionMinHeight: CGFloat? {
        if !isCompact, allowsWorkspaceActivation, isInUseOnOtherDisplay, workspace.items.isEmpty {
            return workspaceSidebarInUseOverrideEmptySectionMinHeight
        }
        return nil
    }
    var isDropTarget: Bool { dragPreview?.targetWorkspaceName == workspace.name }
    var activeSidebarDragSourceWindowId: UInt32? { dragPreview?.sourceWindowId }
    var isShowingInUseOverlay: Bool { activeInUseOverrideWorkspaceName == workspace.name }
    var isSearchSelectedWorkspace: Bool { selectedSearchTarget == .workspace(workspace.name) }
    var isRenamingWorkspace: Bool { renamingWorkspaceName == workspace.name }
    var isPointerHoverVisible: Bool {
        workspaceSidebarPointerHoverIsVisible(
            isHovered: isHovered,
            isWorkspaceReorderInProgress: isWorkspaceReorderInProgress
        )
    }
    var isVisuallyActiveOnTargetMonitor: Bool {
        isActiveOnTargetMonitor || isPendingActivationOnTargetMonitor
    }
    var inUseOverrideText: String {
        if let monitorName = workspace.monitorName, !monitorName.isEmpty {
            return "In use on \(monitorName)"
        }
        return "In use on another display"
    }
    var sectionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarSectionCornerRadius, style: .continuous)
    }

    var body: some View {
        interactiveSectionContent
            .padding(.vertical, isCompact ? workspaceSidebarStandardGap / 2 : 0)
            .padding(.horizontal, workspaceSidebarSectionInnerHorizontalInset)
            .frame(width: sectionWidth, alignment: .leading)
            .frame(minHeight: sectionMinHeight, alignment: .top)
            .clipped()
            .opacity(compactFocusOpacity)
            .contentShape(Rectangle())
            .onHover { hover in
                let visibleHover = hover && !isWorkspaceReorderInProgress
                isHovered = visibleHover
                actions.hoverWorkspace(workspace.name, visibleHover)
            }
            .onChange(of: isWorkspaceReorderInProgress) { isReordering in
                guard isReordering else { return }
                isHovered = false
                hoveredWindowId = nil
                hoveredTabGroupId = nil
                actions.hoverWorkspace(workspace.name, false)
            }
            .onDrop(of: [workspaceSidebarDragPayloadType], delegate: WorkspaceSidebarDropDelegate(
                target: .workspace(workspace.name),
                actions: actions,
                performPayloadDrop: handlePayloadDrop,
                isTargeted: $isDropTargeted,
                isSettling: $isDropSettling,
            ))
            .help(isInUseOnOtherDisplay ? inUseOverrideText : workspace.displayName)
            .zIndex(isDropTarget ? 1 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: dragPreview)
            .animation(reduceMotion ? workspaceSidebarReducedMotionHoverAnimation : workspaceSidebarHoverAnimation, value: isHovered)
            .animation(reduceMotion ? workspaceSidebarReducedMotionHoverAnimation : workspaceSidebarHoverAnimation, value: hoveredWindowId)
            .animation(reduceMotion ? workspaceSidebarReducedMotionHoverAnimation : workspaceSidebarHoverAnimation, value: hoveredTabGroupId)
            .animation(reduceMotion ? workspaceSidebarReducedMotionHoverAnimation : workspaceSidebarHoverAnimation, value: isOnFocusedMonitor)
            .background {
                sectionBackground
            }
            .overlay(alignment: .center) {
                inUseOverrideOverlay
                    .opacity(allowsWorkspaceActivation && isShowingInUseOverlay ? 1 : 0)
                    .allowsHitTesting(allowsWorkspaceActivation && isShowingInUseOverlay)
                    .zIndex(5)
            }
            .background {
                GeometryReader { geometry in
                    WinMuxDesignTokens.transparent.preference(
                        key: WorkspaceSidebarDropTargetPreferenceKey.self,
                        value: emitsDropTarget ? [WorkspaceSidebarDropTargetFrame(
                            kind: .workspace(workspace.name),
                            frame: geometry.frame(in: .named("workspaceSidebarContent")),
                        )] : [],
                    )
                    .preference(
                        key: WorkspaceSidebarWorkspaceReorderFramePreferenceKey.self,
                        value: [WorkspaceSidebarWorkspaceReorderFrame(
                            workspaceName: workspace.name,
                            projectId: workspace.folderId.backingProjectId,
                            frame: geometry.frame(in: .named("workspaceSidebarContent")),
                            isReorderable: isWorkspaceReorderEnabled,
                        )]
                    )
                }
            }
    }

    @ViewBuilder
    var tabContextMenuItems: some View {
        Button {
            debugWorkspaceSidebarRenameLog("workspaceContextRename workspace=\(workspace.name) displayName=\(workspace.displayName) compact=\(isCompact)")
            onBeginRenameWorkspace()
        } label: {
            Text("Rename tab")
        }
        if !projectDestinations.isEmpty {
            Menu("Move to") {
                ForEach(projectDestinations) { project in
                    Button(project.displayName) {
                        actions.send(.moveWorkspaceToProject(workspace.name, projectId: project.id))
                    }
                }
            }
        }
    }
}

func workspaceSidebarProjectDestinations(
    projects: [WorkspaceSidebarProjectViewModel],
    currentProjectId: WorkspaceProjectId
) -> [WorkspaceSidebarProjectViewModel] {
    projects.filter { $0.id != currentProjectId }
}

func workspaceSidebarPointerHoverIsVisible(
    isHovered: Bool,
    isWorkspaceReorderInProgress: Bool
) -> Bool {
    isHovered && !isWorkspaceReorderInProgress
}
