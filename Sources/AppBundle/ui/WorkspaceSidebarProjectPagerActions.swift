import AppKit
import Common
import SwiftUI

extension WorkspaceSidebarProjectPager {
    @ViewBuilder
    var compactProjectIndicator: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .center, spacing: standardGap * 0) {
                    ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                        projectDot(project, index: index)
                            .id(project.id)
                    }
                }
                .frame(width: sectionWidth, alignment: .center)
            }
            .frame(width: sectionWidth, height: compactProjectControlsHeight, alignment: .center)
            .clipped()
            .onAppear {
                scrollCompactProjectTrackToCurrent(proxy)
            }
            .onChange(of: selectedProjectId) { _ in
                scrollCompactProjectTrackToCurrent(proxy)
            }
            .onChange(of: compactProjectControlsHeight) { _ in
                scrollCompactProjectTrackToCurrent(proxy)
            }
        }
    }

    var projectDotTrack: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: standardGap * 2) {
                    ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                        projectDot(project, index: index)
                            .id(project.id)
                    }
                }
                .padding(.horizontal, standardGap * 2)
                .frame(minHeight: workspaceSidebarPagerHeight, alignment: .leading)
                .background {
                    GeometryReader { geometry in
                        WinMuxDesignTokens.transparent
                            .onAppear {
                                updateProjectTrackMetrics(geometry)
                            }
                            .onChange(of: geometry.frame(in: .named("workspaceSidebarProjectTrack")).minX) { _ in
                                updateProjectTrackMetrics(geometry)
                            }
                            .onChange(of: geometry.size.width) { _ in
                                updateProjectTrackMetrics(geometry)
                            }
                    }
                }
            }
            .frame(width: projectTrackWidth, height: workspaceSidebarPagerHeight, alignment: .leading)
            .coordinateSpace(name: "workspaceSidebarProjectTrack")
            .clipped()
            .mask(projectTrackFadeMask)
            .onAppear {
                scrollProjectTrackToCurrent(proxy)
            }
            .onChange(of: selectedProjectId) { _ in
                scrollProjectTrackToCurrent(proxy)
            }
            .onChange(of: projectTrackScrollTargetId) { projectId in
                scrollProjectTrack(to: projectId, proxy: proxy, animated: true)
            }
            .onChange(of: projectTrackWidth) { _ in
                scrollProjectTrackToCurrent(proxy)
            }
        }
    }

    private var projectTrackFadeMask: some View {
        let showsLeadingFade = projectTrackContentMinX < -2
        let showsTrailingFade = projectTrackContentMinX + projectTrackContentWidth > projectTrackViewportWidth + 2
        return LinearGradient(
            stops: [
                .init(color: showsLeadingFade ? WinMuxDesignTokens.transparent : WinMuxDesignTokens.mask, location: 0),
                .init(color: WinMuxDesignTokens.mask, location: showsLeadingFade ? 0.08 : 0),
                .init(color: WinMuxDesignTokens.mask, location: showsTrailingFade ? 0.92 : 1),
                .init(color: showsTrailingFade ? WinMuxDesignTokens.transparent : WinMuxDesignTokens.mask, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func updateProjectTrackMetrics(_ geometry: GeometryProxy) {
        let frame = geometry.frame(in: .named("workspaceSidebarProjectTrack"))
        projectTrackContentMinX = frame.minX
        projectTrackContentWidth = geometry.size.width
        projectTrackViewportWidth = projectTrackWidth
    }

    private func scrollProjectTrackToCurrent(_ proxy: ScrollViewProxy) {
        guard let selectedProject else { return }
        scrollProjectTrack(to: projectTrackScrollTargetId ?? selectedProject.id, proxy: proxy, animated: true)
    }

    private func scrollProjectTrack(to projectId: WorkspaceProjectId?, proxy: ScrollViewProxy, animated: Bool) {
        guard let projectId else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(projectId, anchor: .center)
                }
            } else {
                proxy.scrollTo(projectId, anchor: .center)
            }
        }
    }

    private func scrollCompactProjectTrackToCurrent(_ proxy: ScrollViewProxy) {
        guard let selectedProject else { return }
        scrollProjectTrack(to: selectedProject.id, proxy: proxy, animated: true)
    }

    @ViewBuilder
    var projectMenu: some View {
        Group {
            if let selectedProject, renamingProjectId == selectedProject.id {
                WorkspaceSidebarProjectRenameField(
                    project: selectedProject,
                    text: $renamingProjectText,
                    onCommit: onCommitRenameProject,
                    onCancel: onCancelRenameProject,
                )
            } else {
                projectMenuButton
            }
        }
            .frame(width: projectMenuWidth, height: workspaceSidebarPagerHeight, alignment: .trailing)
            .contextMenu {
                if let selectedProject {
                    projectContextMenuItems(for: selectedProject)
                }
            }
    }

    var projectControls: some View {
        VStack(alignment: .trailing, spacing: standardGap * 2) {
            HStack(alignment: .center, spacing: standardGap * 3) {
                Spacer(minLength: 0)
                projectMenu
                    .frame(width: projectMenuWidth, height: workspaceSidebarPagerHeight, alignment: .trailing)
            }
            .frame(width: sectionWidth, height: workspaceSidebarPagerHeight, alignment: .trailing)

            projectDotTrack
                .frame(width: projectTrackWidth, height: workspaceSidebarPagerHeight, alignment: .leading)
        }
        .frame(width: sectionWidth, height: expandedProjectControlsHeight, alignment: .bottomTrailing)
    }

    private var projectMenuButton: some View {
        Button {
            isProjectMenuOpen.toggle()
        } label: {
            HStack(spacing: standardGap * 2) {
                Text(selectedProject?.displayName ?? "Folder")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.content(isHovered || isProjectMenuOpen ? .primary : .secondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.content(isHovered || isProjectMenuOpen ? .primary : .secondary))
                    .rotationEffect(.degrees(isProjectMenuOpen ? 180 : 0))
            }
            .modifier(WorkspaceSidebarDropdownControlStyle(isActive: isProjectMenuOpen))
        }
        .buttonStyle(.plain)
        .frame(height: workspaceSidebarPagerHeight, alignment: .center)
    }

    @ViewBuilder
    var projectPopup: some View {
        if isProjectMenuOpen {
            WorkspaceSidebarProjectPopup(
                projects: projects,
                selectedProjectId: selectedProjectId,
                onSelect: { projectId in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        onSelectProject(projectId)
                    }
                },
                onCreate: { _ in
                    onCreateProject()
                    isProjectMenuOpen = false
                },
                onRename: { project in
                    onBeginRenameProject(project)
                    isProjectMenuOpen = false
                },
                onSetColor: onSetProjectColor,
                onDelete: { project in
                    onDeleteProject(project)
                    isProjectMenuOpen = false
                },
                showsCreateAction: false,
                menuWidth: projectPopupWidth,
            )
            .frame(width: projectPopupWidth)
            .offset(
                x: 0,
                y: -(expandedProjectControlsHeight + workspaceSidebarSectionGap)
            )
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .bottomTrailing)),
                removal: .opacity,
            ))
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.88), value: isProjectMenuOpen)
            .zIndex(100)
        }
    }

    @ViewBuilder
    func projectContextMenuItems(for project: WorkspaceSidebarProjectViewModel) -> some View {
        Button("Rename folder") {
            onBeginRenameProject(project)
        }
        if projectsAreEnabled() {
            Menu("Color") {
                let selectedColorHex = project.colorHex.flatMap(normalizedWorkspaceSidebarColorHex)
                    ?? workspaceSidebarDefaultProjectColorHex
                ForEach(workspaceSidebarProjectColorPresets) { preset in
                    Button {
                        onSetProjectColor(project, preset.hex)
                    } label: {
                        Label {
                            Text(preset.name)
                        } icon: {
                            Image(nsImage: workspaceSidebarProjectColorSwatchImage(
                                hex: preset.hex,
                                isSelected: selectedColorHex == preset.hex,
                            ))
                        }
                    }
                }
            }
        }
        Button(role: .destructive) {
            onDeleteProject(project)
        } label: {
            Text("Delete folder")
        }
        .disabled(!canDeleteWorkspaceProject(project.id))
    }
}
