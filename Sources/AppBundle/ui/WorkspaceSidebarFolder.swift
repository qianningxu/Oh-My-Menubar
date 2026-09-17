import SwiftUI

struct WorkspaceSidebarFolderSection: Identifiable, Equatable {
    let folder: WorkspaceSidebarFolderViewModel
    let workspaces: [WorkspaceSidebarWorkspaceViewModel]

    var id: WorkspaceFolderId { folder.id }
    var isDefault: Bool { folder.isUnfolded }

    // Drag/reorder code still uses the legacy raw-ID carrier at its boundary.
    // Ownership comes from `folder.projectId`, never from this conversion.
    var project: WorkspaceSidebarProjectViewModel {
        WorkspaceSidebarProjectViewModel(
            id: folder.id.backingProjectId,
            displayName: folder.displayName,
            colorHex: nil
        )
    }
}

struct WorkspaceSidebarProjectReorderDropArea<Content: View>: View {
    let projectId: WorkspaceProjectId
    let isDropTarget: Bool
    let minimumHeight: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(minHeight: minimumHeight, alignment: .topLeading)
            .background {
                GeometryReader { geometry in
                    WinMuxDesignTokens.transparent.preference(
                        key: WorkspaceSidebarFolderReorderFramePreferenceKey.self,
                        value: [WorkspaceSidebarFolderReorderFrame(
                            projectId: projectId,
                            frame: geometry.frame(in: .named("workspaceSidebarContent")),
                            isDropTarget: isDropTarget,
                        )]
                    )
                }
            }
    }
}

func workspaceSidebarFolderSections(
    projectId: WorkspaceProjectId,
    workspaces: [WorkspaceSidebarWorkspaceViewModel],
    folders: [WorkspaceSidebarFolderViewModel],
) -> [WorkspaceSidebarFolderSection] {
    let workspacesByFolder = Dictionary(grouping: workspaces, by: \.folderId)
    return folders.filter { $0.projectId == projectId }.map { folder in
        WorkspaceSidebarFolderSection(
            folder: folder,
            workspaces: workspaceSidebarNonEmptyFolderWorkspaces(workspacesByFolder[folder.id] ?? [])
        )
    }
}

func workspaceSidebarFolderSections(
    projectId: WorkspaceProjectId,
    workspaces: [WorkspaceSidebarWorkspaceViewModel],
    projects: [WorkspaceSidebarProjectViewModel]
) -> [WorkspaceSidebarFolderSection] {
    workspaceSidebarFolderSections(
        projectId: projectId,
        workspaces: workspaces,
        folders: projects.map {
            WorkspaceSidebarFolderViewModel(
                id: WorkspaceFolderId($0.id),
                projectId: projectId,
                displayName: $0.displayName,
                colorHex: nil,
                isUnfolded: $0.id == workspaceProjectDefaultId
            )
        }
    )
}

func workspaceSidebarNonEmptyFolderWorkspaces(
    _ workspaces: [WorkspaceSidebarWorkspaceViewModel]
) -> [WorkspaceSidebarWorkspaceViewModel] {
    workspaces.filter { !$0.tabSummary.isEmpty || !$0.items.isEmpty }
}

func workspaceSidebarFolderUsesGroupPresentation(
    _ folder: WorkspaceSidebarFolderViewModel
) -> Bool {
    !folder.isUnfolded
}

func workspaceSidebarFolderShowsContent(
    isExpanded: Bool,
    hasItems: Bool,
    isWorkspaceDragTargeted: Bool,
    isShowingProjectedContent: Bool
) -> Bool {
    (isExpanded && hasItems) || isWorkspaceDragTargeted || isShowingProjectedContent
}

func workspaceSidebarFolderIsVisuallyExpanded(
    isExpanded: Bool,
    isWorkspaceDragTargeted: Bool,
    isShowingProjectedContent: Bool
) -> Bool {
    isExpanded || isWorkspaceDragTargeted || isShowingProjectedContent
}

func workspaceSidebarCurrentFolderProjectId(
    workspaces: [WorkspaceSidebarWorkspaceViewModel],
    targetMonitorScopeId: String
) -> WorkspaceProjectId? {
    workspaces.first {
        $0.isVisible && $0.monitorScopeId == targetMonitorScopeId
    }?.folderId.backingProjectId ?? workspaces.first(where: \.isFocused)?.folderId.backingProjectId
}

func workspaceSidebarCompactFolderSections(
    _ sections: [WorkspaceSidebarFolderSection],
    currentProjectId: WorkspaceProjectId?
) -> [WorkspaceSidebarFolderSection] {
    guard let currentProjectId,
          let currentSection = sections.first(where: { $0.project.id == currentProjectId })
    else {
        return sections
    }
    return [currentSection]
}

private struct WorkspaceSidebarFolderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

struct WorkspaceSidebarFolder<Content: View>: View {
    let section: WorkspaceSidebarFolderSection
    let expansionProgress: CGFloat
    let layout: WorkspaceSidebarConfiguration
    let monitorScopeId: String
    let isExpanded: Bool
    let onToggle: () -> Void
    let onDropPayload: @MainActor (WorkspaceSidebarDragPayload) -> Void
    let projectDestinations: [WorkspaceSidebarProjectViewModel]
    let actions: WorkspaceSidebarActions
    let emitsDropTarget: Bool
    let dropPreview: WorkspaceSidebarDropPreviewViewModel?
    let isWorkspaceDragTargeted: Bool
    let isShowingProjectedContent: Bool
    let isFolderReorderEnabled: Bool
    let isFolderReorderSource: Bool
    @Binding var renamingFolderId: WorkspaceFolderId?
    @Binding var renamingFolderText: String
    let onBeginRenameFolder: @MainActor (WorkspaceSidebarFolderViewModel) -> Void
    let onCommitRenameFolder: @MainActor () -> Void
    let onCancelRenameFolder: @MainActor () -> Void
    let onFolderReorderDragChanged: (CGPoint) -> Void
    let onFolderReorderDragEnded: (CGPoint) -> Void
    @ViewBuilder let content: () -> Content

    @State private var isDropTargeted = false
    @State private var isDropSettling = false
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }
    private var sectionWidth: CGFloat { workspaceSidebarSectionWidth(expansionProgress, layout: layout) }
    private var usesGroupPresentation: Bool {
        workspaceSidebarFolderUsesGroupPresentation(section.folder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: usesGroupPresentation ? 0 : workspaceSidebarNestedRowSpacing) {
            if usesGroupPresentation {
                folderHeader
            }

            if showsFolderContent {
                if isVisuallyExpanded {
                    folderContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    // A reorder preview can move between folders on adjacent
                    // display frames. Do not animate that transient reveal:
                    // opacity/move transitions here were the last source of
                    // the visible folder flash during a drag.
                    folderContent
                }
            }
        }
        .frame(width: sectionWidth, alignment: .leading)
        .background {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named("workspaceSidebarContent"))
                WinMuxDesignTokens.transparent
                    .preference(
                        key: WorkspaceSidebarDropTargetPreferenceKey.self,
                        value: emitsDropTarget ? [WorkspaceSidebarDropTargetFrame(
                            kind: .folder(section.project.id, monitorScopeId: monitorScopeId),
                            frame: frame,
                        )] : [],
                    )
                    .preference(
                        key: WorkspaceSidebarFolderReorderFramePreferenceKey.self,
                        value: [WorkspaceSidebarFolderReorderFrame(
                            projectId: section.project.id,
                            frame: frame,
                            isDropTarget: emitsDropTarget,
                        )]
                    )
            }
        }
        .background {
            if usesGroupPresentation {
                RoundedRectangle(cornerRadius: workspaceSidebarSectionCornerRadius, style: .continuous)
                    .fill(folderBlockFill)
            }
        }
        .overlay {
            if usesGroupPresentation && (showsFolderContent || isFolderInteractionActive) {
                RoundedRectangle(cornerRadius: workspaceSidebarSectionCornerRadius, style: .continuous)
                    .strokeBorder(folderBlockBorder, lineWidth: 1)
            }
        }
        .shadow(
            color: folderBlockShadow,
            radius: usesFolderHoverTreatment ? WinMuxSpacing.compact : WinMuxSpacing.none,
            y: usesFolderHoverTreatment ? WinMuxSpacing.hairline : WinMuxSpacing.none,
        )
        .padding(.vertical, usesGroupPresentation ? workspaceSidebarFolderOuterVerticalMargin : 0)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onDrop(of: [workspaceSidebarDragPayloadType], delegate: WorkspaceSidebarDropDelegate(
            target: .folder(section.project.id, monitorScopeId: monitorScopeId),
            actions: actions,
            performPayloadDrop: onDropPayload,
            isTargeted: $isDropTargeted,
            isSettling: $isDropSettling,
        ))
        .contextMenu {
            if !section.folder.isUnfolded {
                Button("Rename folder") {
                    onBeginRenameFolder(section.folder)
                }
                if !projectDestinations.isEmpty {
                    Menu("Move to project") {
                        ForEach(projectDestinations) { project in
                            Button(project.displayName) {
                                actions.send(.moveFolderToProject(section.folder.id, projectId: project.id))
                            }
                        }
                    }
                }
                Divider()
                Button(role: .destructive) {
                    actions.send(.deleteFolder(section.folder.id))
                } label: {
                    Text("Delete folder")
                }
                .disabled(!canDeleteWorkspaceFolder(section.folder.id))
            }
        }
        .modifier(WorkspaceSidebarProjectedDragAnchorModifier(isActive: isFolderReorderSource))
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.88), value: showsFolderContent)
        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.86), value: isFolderInteractionActive)
    }

    private var isRenamingFolder: Bool {
        renamingFolderId == section.folder.id
    }

    private var folderHeader: some View {
        Group {
            if isRenamingFolder {
                folderHeaderContent
            } else {
                Button(action: onToggle) {
                    folderHeaderContent
                        .contentShape(Rectangle())
                }
                // PlainButtonStyle still applies a brief pressed-state
                // repaint on macOS. Persisting the folder state can keep that
                // frame visible long enough to look like a flash.
                .buttonStyle(WorkspaceSidebarFolderButtonStyle())
            }
        }
        .frame(width: sectionWidth, height: workspaceSidebarWorkspaceSectionHeaderHeight, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(WorkspaceSidebarWorkspaceReorderGestureModifier(
            isEnabled: isFolderReorderEnabled,
            onChanged: onFolderReorderDragChanged,
            onEnded: onFolderReorderDragEnded
        ))
        .help(isVisuallyExpanded ? "Hide folder" : "Show folder")
    }

    private var folderHeaderContent: some View {
        HStack(spacing: workspaceSidebarHeaderSpacing) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.content(.secondary))
                .frame(width: workspaceSidebarAppIconSize + 2, height: workspaceSidebarAppIconSize + 2)
            if isRenamingFolder {
                WorkspaceSidebarProjectRenameField(
                    project: section.project,
                    text: $renamingFolderText,
                    onCommit: onCommitRenameFolder,
                    onCancel: onCancelRenameFolder,
                    showsPlate: false,
                    font: .systemFont(ofSize: 13.5, weight: .semibold),
                )
                .layoutPriority(1)
            } else {
                Text(section.project.displayName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(palette.content(.primary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(isVisuallyExpanded ? 90 : 0))
                    .foregroundStyle(palette.content(.secondary))
                    .frame(width: 10, height: 18)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, workspaceSidebarHeaderRowLeadingPadding)
        .padding(.trailing, workspaceSidebarRowHorizontalPadding)
        .frame(height: workspaceSidebarWorkspaceSectionHeaderHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var folderContent: some View {
        VStack(alignment: .leading, spacing: workspaceSidebarNestedRowSpacing) {
            content()
        }
        .padding(.top, usesGroupPresentation ? workspaceSidebarStandardGap : 0)
        .padding(.bottom, usesGroupPresentation ? workspaceSidebarStandardGap : 0)
        .frame(width: sectionWidth, alignment: .leading)
    }

    private var showsFolderContent: Bool {
        if !usesGroupPresentation {
            return true
        }
        return workspaceSidebarFolderShowsContent(
            isExpanded: isExpanded,
            hasItems: !section.workspaces.isEmpty,
            isWorkspaceDragTargeted: isWorkspaceDragTargeted,
            isShowingProjectedContent: isShowingProjectedContent
        )
    }

    private var isVisuallyExpanded: Bool {
        if !usesGroupPresentation {
            return true
        }
        return workspaceSidebarFolderIsVisuallyExpanded(
            isExpanded: isExpanded,
            isWorkspaceDragTargeted: isWorkspaceDragTargeted,
            isShowingProjectedContent: isShowingProjectedContent
        )
    }

    private var isFolderTargeted: Bool {
        isDropTargeted
    }

    private var isFolderInteractionActive: Bool {
        // Reorder targeting is represented by the insertion slot itself.
        // Do not animate the surrounding folder plate, border, or shadow as
        // the pointer crosses folders: that visual churn is perceived as a
        // flash even with a stable row layout.
        isFolderTargeted || isHovered
    }

    private var usesFolderHoverTreatment: Bool {
        // Reorder previews may switch folders many times per second. They
        // should reveal an insertion slot, not repaint an entire folder as a
        // drop target; that made the background flash unpredictably. Keep the
        // ordinary folder hover treatment tied to the actual pointer hover.
        isHovered
    }

    private var folderBlockFill: Color {
        if isFolderTargeted {
            return palette.componentBackground(.active)
        }
        if usesFolderHoverTreatment {
            return palette.color(palette.activeGeistFamily, .color5)
        }
        return palette.color(palette.activeGeistFamily, .color1)
    }

    private var folderBlockBorder: Color {
        if isFolderTargeted {
            return palette.geistBorder(.active)
        }
        if usesFolderHoverTreatment {
            return palette.color(palette.activeGeistFamily, .color7)
        }
        return palette.color(palette.activeGeistFamily, .color5)
    }

    private var folderBlockShadow: Color {
        guard usesFolderHoverTreatment else { return WinMuxDesignTokens.transparent }
        return palette.color(palette.activeGeistFamily, .color8).opacity(0.18)
    }

}
