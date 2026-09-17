import AppKit
import Common
import SwiftUI

// MARK: - Create Workspace Section

struct WorkspaceSidebarCreateWorkspaceSection: View {
    let projectId: WorkspaceProjectId
    let monitorScopeId: String
    let dragPreview: WorkspaceSidebarDropPreviewViewModel?
    let expansionProgress: CGFloat
    let layout: WorkspaceSidebarConfiguration
    let emitsDropTarget: Bool
    var fillsAvailableHeight = false
    let onCreateWorkspace: () -> Void
    let onDropPayload: @MainActor (WorkspaceSidebarDragPayload) -> Void
    let actions: WorkspaceSidebarActions

    @State private var isDropTargeted = false
    @State private var isDropSettling = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    private var sectionWidth: CGFloat { workspaceSidebarSectionWidth(expansionProgress, layout: layout) }
    private var isCompact: Bool { expansionProgress < workspaceSidebarRowsRevealProgress }
    private var showsDropTarget: Bool {
        guard dragPreview?.targetsNewWorkspace == true else { return false }
        if let targetProjectId = dragPreview?.targetProjectId {
            return targetProjectId == projectId &&
                (dragPreview?.targetMonitorScopeId == nil || dragPreview?.targetMonitorScopeId == monitorScopeId)
        }
        return workspaceSidebarDropTarget(at: MousePointerTracker.shared.currentSample.point)?.kind == .newWorkspace(
            projectId: projectId,
            monitorScopeId: monitorScopeId
        )
    }
    private var sectionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarSectionCornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: workspaceSidebarStandardGap) {
            if showsDropTarget, let dragPreview {
                WorkspaceSidebarDropPreviewView(
                    preview: dragPreview,
                    rowHeight: workspaceSidebarWorkspaceRowHeight,
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .opacity),
                    removal: .opacity,
                ))
            } else {
                createButton
            }
        }
        .frame(width: sectionWidth, alignment: isCompact ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
        .frame(maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .zIndex(showsDropTarget ? 1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: showsDropTarget)
        .background {
            GeometryReader { geometry in
                WinMuxDesignTokens.transparent.preference(
                    key: WorkspaceSidebarDropTargetPreferenceKey.self,
                    value: emitsDropTarget ? [WorkspaceSidebarDropTargetFrame(
                        kind: .newWorkspace(projectId: projectId, monitorScopeId: monitorScopeId),
                        frame: geometry.frame(in: .named("workspaceSidebarContent")),
                    )] : [],
                )
            }
        }
        .onDrop(of: [workspaceSidebarDragPayloadType], delegate: WorkspaceSidebarDropDelegate(
            target: .newWorkspace(projectId: projectId, monitorScopeId: monitorScopeId),
            actions: actions,
            performPayloadDrop: onDropPayload,
            isTargeted: $isDropTargeted,
            isSettling: $isDropSettling,
        ))
    }

    private var createButton: some View {
        Button {
            guard shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) else { return }
            onCreateWorkspace()
        } label: {
            HStack(spacing: workspaceSidebarHeaderSpacing) {
                if isCompact {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.content(.secondary))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    HStack(spacing: standardGap * 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.content(.secondary))
                        Text("New folder")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.content(.secondary))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.vertical, isCompact ? workspaceSidebarStandardGap / 2 : 4)
            .padding(.horizontal, workspaceSidebarSectionInnerHorizontalInset + workspaceSidebarHeaderRowLeadingPadding)
            .frame(
                width: sectionWidth,
                height: isCompact ? workspaceSidebarWorkspaceSectionHeightCompact : workspaceSidebarWorkspaceSectionHeightExpanded,
                alignment: isCompact ? .center : .leading,
            )
            .background {
                sectionShape.fill(isDropTargeted ? palette.componentBackground(.active) : WinMuxDesignTokens.transparent)
            }
            .overlay {
                if isDropTargeted {
                    sectionShape.strokeBorder(
                        palette.geistBorder(.active),
                        style: StrokeStyle(lineWidth: 0.5, dash: [3, 2.5])
                    )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New folder")
        .accessibilityLabel("New folder")
    }
}
