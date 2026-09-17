import AppKit
import SwiftUI

private let projectTabsBarFontSize = WinMuxBarStyle.projectTabsBarFontSize

struct WorkspaceSidebarHorizontalTabFrame: Equatable {
    let workspaceName: String
    let folderId: WorkspaceFolderId
    let frame: CGRect
}

struct WorkspaceSidebarHorizontalTabFramePreferenceKey: PreferenceKey {
    static let defaultValue: [WorkspaceSidebarHorizontalTabFrame] = []

    static func reduce(
        value: inout [WorkspaceSidebarHorizontalTabFrame],
        nextValue: () -> [WorkspaceSidebarHorizontalTabFrame]
    ) {
        value.append(contentsOf: nextValue())
    }
}

private struct WorkspaceSidebarProjectBarSizePreferenceKey: PreferenceKey {
    static let defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct WorkspaceSidebarHorizontalReorderTarget: Equatable {
    let workspaceName: String
    let folderId: WorkspaceFolderId
    let placement: WorkspaceReorderPlacement
}

struct WorkspaceSidebarWindowMenuItem: Equatable, Identifiable {
    let windowId: UInt32
    let title: String
    let tabName: String?
    let isFloating: Bool
    let isFocused: Bool

    var id: UInt32 { windowId }
    var menuTitle: String {
        "\(title) — \(isFloating ? "Floating" : tabName ?? "Tab")"
    }
}

func workspaceSidebarTiledWindowMenuItems(
    workspaces: [WorkspaceSidebarWorkspaceViewModel]
) -> [WorkspaceSidebarWindowMenuItem] {
    workspaces.flatMap { workspace in
        workspace.items.flatMap { item -> [WorkspaceSidebarWindowViewModel] in
            switch item.kind {
                case .window(let window): [window]
                case .tabGroup(let group): group.tabs
            }
        }.map { window in
            WorkspaceSidebarWindowMenuItem(
                windowId: window.windowId,
                title: window.title ?? window.appName,
                tabName: workspace.displayName,
                isFloating: false,
                isFocused: window.isFocused
            )
        }
    }
}

func workspaceSidebarHorizontalReorderTarget(
    sourceWorkspaceName: String,
    pointer: CGPoint,
    frames: [WorkspaceSidebarHorizontalTabFrame]
) -> WorkspaceSidebarHorizontalReorderTarget? {
    let orderedFrames = frames.sorted { $0.frame.minX < $1.frame.minX }
    guard let sourceIndex = orderedFrames.firstIndex(where: { $0.workspaceName == sourceWorkspaceName }) else {
        return nil
    }

    let candidates = orderedFrames.filter { $0.workspaceName != sourceWorkspaceName }
    if let containing = candidates.last(where: { $0.frame.contains(pointer) }) {
        return WorkspaceSidebarHorizontalReorderTarget(
            workspaceName: containing.workspaceName,
            folderId: containing.folderId,
            placement: pointer.x < containing.frame.midX
                ? .before(containing.workspaceName)
                : .after(containing.workspaceName),
        )
    }

    let insertionIndex = orderedFrames.firstIndex { pointer.x < $0.frame.midX } ?? orderedFrames.count
    let destinationIndex = insertionIndex > sourceIndex ? insertionIndex - 1 : insertionIndex
    guard orderedFrames.indices.contains(destinationIndex), destinationIndex != sourceIndex else {
        return nil
    }

    let target = orderedFrames[destinationIndex]
    return WorkspaceSidebarHorizontalReorderTarget(
        workspaceName: target.workspaceName,
        folderId: target.folderId,
        placement: destinationIndex < sourceIndex
            ? .before(target.workspaceName)
            : .after(target.workspaceName),
    )
}

func workspaceSidebarHorizontalVisibleWorkspaces(
    in snapshot: WorkspaceSidebarSnapshot
) -> [WorkspaceSidebarWorkspaceViewModel] {
    workspaceSidebarVisibleWorkspacesByProject(
        workspaces: snapshot.workspaces,
        selectedScopeId: snapshot.selectedMonitorScopeId,
        focusedMonitorScopeId: snapshot.focusedMonitorScopeId,
        targetMonitorScopeId: snapshot.targetMonitorScopeId,
        browsedProjectId: nil,
        projectsEnabled: true,
    )[snapshot.activeProjectId] ?? []
}

func workspaceSidebarHorizontalProjectPopupHeight(
    projectCount: Int,
    showsCreateAction: Bool = true
) -> CGFloat {
    let rowCount = max(projectCount, 0) + (showsCreateAction ? 1 : 0)
    guard rowCount > 0 else { return standardGap * 4 }
    let rowSpacing = CGFloat(max(rowCount - 1, 0)) * standardGap * 0.5
    let dividerHeight = showsCreateAction ? 0.5 + standardGap : 0
    return CGFloat(rowCount) * workspaceSidebarProjectPopupRowHeight + rowSpacing + dividerHeight + standardGap * 4
}

struct WorkspaceSidebarHorizontalBar: View {
    let snapshot: WorkspaceSidebarSnapshot
    let actions: WorkspaceSidebarActions

    @State private var renamingProjectId: WorkspaceProjectId?
    @State private var renamingProjectText = ""
    @State private var renamingWorkspaceName: String?
    @State private var renamingWorkspaceText = ""
    @State private var activeInUseOverrideWorkspaceName: String?
    @State private var hoveredWorkspaceName: String?
    @State private var workspaceReorderFrames: [WorkspaceSidebarHorizontalTabFrame] = []
    @StateObject private var workspaceDragDriver = WorkspaceSidebarWorkspaceReorderDriver()
    @State private var workspaceReorderSourceName: String?
    @State private var workspaceReorderTarget: WorkspaceSidebarHorizontalReorderTarget?
    @State private var workspaceDragStartX: CGFloat?
    @State private var workspaceDragOrder: [String]?
    @State private var workspaceDragOffset: CGFloat = 0
    @State private var pendingWorkspaceReorder: WorkspaceSidebarPendingHorizontalReorder?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.colorScheme) private var colorScheme


    private var activeProject: WorkspaceSidebarProjectViewModel? {
        snapshot.projects.first { $0.id == snapshot.activeProjectId }
            ?? snapshot.projects.first
    }

    private var projectWorkspaces: [WorkspaceSidebarWorkspaceViewModel] {
        workspaceSidebarHorizontalVisibleWorkspaces(in: snapshot)
    }

    @MainActor
    private var floatingWindowMenuItems: [WorkspaceSidebarWindowMenuItem] {
        globalFloatingWindowsContainer.children.compactMap { node -> WorkspaceSidebarWindowMenuItem? in
            guard let window = node as? Window, window.isBound else { return nil }
            return WorkspaceSidebarWindowMenuItem(
                windowId: window.windowId,
                title: sidebarDisplayLabel(for: window),
                tabName: nil,
                isFloating: true,
                isFocused: focus.windowOrNil == window
            )
        }.sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    @MainActor
    private func windowMenuItems(for workspace: WorkspaceSidebarWorkspaceViewModel) -> [WorkspaceSidebarWindowMenuItem] {
        workspaceSidebarTiledWindowMenuItems(workspaces: [workspace]) + floatingWindowMenuItems
    }

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(
            colorScheme: colorScheme,
            projectThemeFamily: workspaceSidebarProjectThemeFamily(
                projects: snapshot.projects,
                activeProjectId: snapshot.activeProjectId
            )
        )
    }

    private var currentPanel: WorkspaceSidebarPanel? {
        WorkspaceSidebarPanel.panel(for: snapshot.targetMonitorScopeId)
    }

    var body: some View {
        let contentHeight = WinMuxBarStyle.workspaceTabContentHeight
        workspaceTabStrip(contentHeight: contentHeight)
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: contentHeight)
        .padding(.horizontal, WinMuxBarStyle.projectTabsBarHorizontalInset)
        .winMuxCustomGlassBarSurface(
            palette,
            glassStyle: .workspaceBar,
            strokeOpacity: WinMuxBarStyle.workspaceBarStrokeOpacity
        )
        .padding(WinMuxBarStyle.workspaceBarShadowOutset)
        .background {
            GeometryReader { geometry in
                WinMuxDesignTokens.transparent.preference(
                    key: WorkspaceSidebarProjectBarSizePreferenceKey.self,
                    value: geometry.size
                )
            }
        }
        .coordinateSpace(name: "workspaceSidebarContent")
        .onPreferenceChange(WorkspaceSidebarProjectBarSizePreferenceKey.self) { size in
            currentPanel?.setProjectBarContentSize(size)
        }
        .onPreferenceChange(WorkspaceSidebarHorizontalTabFramePreferenceKey.self) { frames in
            workspaceReorderFrames = frames
        }
        .onPreferenceChange(WorkspaceSidebarDropTargetPreferenceKey.self) { frames in
            actions.setDropTargets(frames)
        }
        .onAppear {
            actions.setDropTargets([])
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace tabs bar")
        .onDisappear { clearWorkspaceReorderState() }
        .environment(\.workspaceSidebarProjectThemeFamily, workspaceSidebarProjectThemeFamily(
            projects: snapshot.projects,
            activeProjectId: snapshot.activeProjectId,
        ))
        .onChange(of: snapshot.activeProjectId) { _ in
            finishProjectRename(cancelled: true)
            finishWorkspaceRename(cancelled: true)
            activeInUseOverrideWorkspaceName = nil
            clearWorkspaceReorderState()
        }
        .onChange(of: snapshot.projects) { projects in
            if let renamingProjectId,
               !projects.contains(where: { $0.id == renamingProjectId })
            {
                finishProjectRename(cancelled: true)
            }
        }
        .onChange(of: snapshot.workspaces) { _ in
            if let pendingWorkspaceReorder,
               pendingWorkspaceReorder.order != projectWorkspaces.map(\.name) {
                self.pendingWorkspaceReorder = nil
            }
            if workspaceReorderSourceName != nil,
               workspaceDragOrder != projectWorkspaces.map(\.name) {
                clearWorkspaceReorderState()
            }
            if let renamingWorkspaceName,
               !snapshot.workspaces.contains(where: { $0.name == renamingWorkspaceName })
            {
                finishWorkspaceRename(cancelled: true)
            }
        }
    }

    @ViewBuilder
    private func projectControl(contentHeight: CGFloat) -> some View {
        let project = activeProject
        let name = project?.displayName ?? "Main"
        let textWidth = (name.uppercased() as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: projectTabsBarFontSize, weight: .regular)
        ]).width
        let controlWidth = min(max(ceil(textWidth) + standardGap * 11.5, standardGap * 23), standardGap * 34)

        if let renamingProjectId,
           let renamingProject = snapshot.projects.first(where: { $0.id == renamingProjectId }) {
            WorkspaceSidebarProjectRenameField(
                project: renamingProject,
                text: $renamingProjectText,
                onCommit: { finishProjectRename() },
                onCancel: { finishProjectRename(cancelled: true) },
                showsPlate: false,
                font: .systemFont(ofSize: projectTabsBarFontSize, weight: .regular)
            )
            .frame(width: controlWidth, height: contentHeight)
        } else {
            WorkspaceSidebarProjectMenu(
                projects: snapshot.projects,
                selectedProjectId: snapshot.activeProjectId,
                configuration: projectConfigurationItems,
                allowsCreation: projectsAreEnabled(),
                colorScheme: colorScheme,
                onSelect: { actions.send(.selectProject($0)) },
                onCreate: { onCreated in
                    createWorkspaceSidebarProject(onCreated: onCreated)
                },
                onRename: { actions.send(.renameProject($0, displayName: $1)) }
            )
            .frame(width: contentHeight, height: contentHeight)
            .help("Project: \(name) — Switch project")
        }
    }

    private var projectConfigurationItems: [WorkspaceSidebarNativeContextMenu.Item] {
        typealias Item = WorkspaceSidebarNativeContextMenu.Item
        let themes: [(String, AppearanceTheme?)] = [("Light", .light), ("Dark", .dark), ("System", nil)]
        var items = [Item(title: "Theme", children: themes.map { title, theme in
            Item(title: title, symbol: currentWorkspaceSidebarAppearancePreference() == theme ? "checkmark" : nil) {
                setWorkspaceSidebarAppearance(theme)
            }
        })]
        items.append(Item(
            title: "Auto hide",
            symbol: snapshot.isAutoHideEnabled ? "checkmark" : nil
        ) {
            actions.send(.setAutoHide(!snapshot.isAutoHideEnabled))
        })
        if projectsAreEnabled(), let project = activeProject {
            items.append(Item(title: "Rename project") { beginProjectRename(project) })
            items.append(Item(title: "Project color", children: workspaceSidebarProjectColorPresets.map { preset in
                Item(title: preset.name, symbol: project.colorHex.flatMap(normalizedWorkspaceSidebarColorHex) == preset.hex ? "checkmark" : nil) {
                    actions.send(.setProjectColor(project.id, colorHex: preset.hex))
                }
            }))
            items.append(Item(title: "Delete project", isEnabled: canDeleteWorkspaceProject(project.id)) {
                actions.send(.deleteProject(project.id))
            })
        }
        return items
    }

    private func workspaceTabStrip(contentHeight: CGFloat) -> some View {
                HStack(spacing: WinMuxSpacing.none) {
                    ForEach(Array(projectWorkspaces.enumerated()), id: \.element.id) { index, workspace in
                        if index > 0 {
                            WinMuxBarDivider(height: WinMuxSpacing.panel, palette: palette)
                                .padding(.horizontal, WinMuxSpacing.hairline)
                                .opacity(workspaceReorderSourceName != nil || pendingWorkspaceReorder != nil ? 0 : 1)
                        }
                        workspaceTab(workspace, contentHeight: contentHeight)
                            .frame(width: workspaceTabWidth(workspace), height: contentHeight)
                    }
                }
        .frame(height: contentHeight)
    }

    private func workspaceTabWidth(_ workspace: WorkspaceSidebarWorkspaceViewModel) -> CGFloat {
        let textWidth = (workspace.displayName as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: projectTabsBarFontSize, weight: .medium)
        ]).width
        return min(ceil(textWidth) + WinMuxBarStyle.contentInset * 2, WinMuxBarStyle.maximumTabWidth)
    }

    private func workspaceTab(
        _ workspace: WorkspaceSidebarWorkspaceViewModel,
        contentHeight: CGFloat,
    ) -> some View {
        let isActive = workspaceIsActive(workspace)
        let isInUseOnOtherDisplay = workspaceSidebarWorkspaceIsInUseOnOtherDisplay(
            workspace,
            selectedScopeId: snapshot.targetMonitorScopeId,
        )
        let isDropTarget = snapshot.dropPreview?.targetWorkspaceName == workspace.name
        let isReorderTarget = workspaceReorderTarget?.workspaceName == workspace.name
        let isReorderSource = workspaceReorderSourceName == workspace.name

        return WorkspaceSidebarHorizontalWorkspaceTab(
            workspace: workspace,
            contentHeight: contentHeight,
            isActive: isActive,
            isInUseOnOtherDisplay: isInUseOnOtherDisplay,
            isDropTarget: isDropTarget,
            isReorderTarget: isReorderTarget,
            isReorderSource: isReorderSource,
            isRenaming: renamingWorkspaceName == workspace.name,
            renamingText: $renamingWorkspaceText,
            activeInUseOverrideWorkspaceName: $activeInUseOverrideWorkspaceName,
            hoveredWorkspaceName: $hoveredWorkspaceName,
            actions: actions,
            allWindowMenuItems: windowMenuItems(for: workspace),
            workspaceDestinations: snapshot.workspaces.filter {
                $0.name != workspace.name && $0.projectId == workspace.projectId &&
                    (!workspace.isVisible || !$0.isVisible || $0.monitorScopeId == workspace.monitorScopeId)
            },
            projectDestinations: workspaceSidebarProjectDestinations(
                projects: snapshot.projects,
                currentProjectId: workspace.projectId,
            ),
            onSelect: {
                selectWorkspace(workspace)
            },
            onBeginRename: {
                beginWorkspaceRename(workspace)
            },
            onCommitRename: {
                finishWorkspaceRename()
            },
            onCancelRename: {
                finishWorkspaceRename(cancelled: true)
            },
            onClose: {
                actions.send(.closeWorkspace(workspace.name))
            },
            onMoveToProject: { projectId in
                actions.send(.moveWorkspaceToProject(workspace.name, projectId: projectId))
            },
            onReorderChanged: { pointer in
                updateWorkspaceReorder(workspace, pointer: pointer)
            },
            onReorderEnded: { _ in
                finishWorkspaceReorder(workspace)
            },
        )
        .offset(x: workspaceVisualOffset(for: workspace.name))
        .zIndex(isReorderSource ? 1 : 0)
        .animation(isReorderSource || reduceMotion ? nil : windowTabPillAnimation, value: workspaceReorderTarget)
        // Measure the stationary slot, outside the visual offset, so moving
        // neighbours cannot move their own reorder thresholds.
        .background {
            GeometryReader { geometry in
                WinMuxDesignTokens.transparent.preference(
                    key: WorkspaceSidebarHorizontalTabFramePreferenceKey.self,
                    value: [WorkspaceSidebarHorizontalTabFrame(
                        workspaceName: workspace.name,
                        folderId: workspace.folderId,
                        frame: geometry.frame(in: .named("workspaceSidebarContent")),
                    )],
                )
                .preference(
                    key: WorkspaceSidebarDropTargetPreferenceKey.self,
                    value: [WorkspaceSidebarDropTargetFrame(
                        kind: .workspace(workspace.name),
                        frame: geometry.frame(in: .named("workspaceSidebarContent")),
                    )],
                )
            }
        }
        .frame(height: contentHeight)
    }

    private func workspaceIsActive(_ workspace: WorkspaceSidebarWorkspaceViewModel) -> Bool {
        workspace.isVisible && workspace.monitorScopeId == snapshot.targetMonitorScopeId
    }

    private func selectWorkspace(_ workspace: WorkspaceSidebarWorkspaceViewModel) {
        guard shouldHandleWorkspaceSidebarActivation(
            isEditing: renamingWorkspaceName != nil || renamingProjectId != nil,
            isSidebarDragInProgress: isWorkspaceSidebarDragInProgress(),
        ) else { return }
        if workspaceSidebarWorkspaceIsInUseOnOtherDisplay(
            workspace,
            selectedScopeId: snapshot.targetMonitorScopeId,
        ) {
            activeInUseOverrideWorkspaceName = workspace.name
            return
        }
        activeInUseOverrideWorkspaceName = nil
        actions.send(.selectWorkspace(workspace.name))
    }

    private func beginProjectRename(_ project: WorkspaceSidebarProjectViewModel) {
        finishWorkspaceRename(cancelled: true)
        renamingProjectId = project.id
        renamingProjectText = project.displayName
        currentPanel?.prepareForInlineTextEditing()
    }

    private func finishProjectRename(cancelled: Bool = false) {
        guard let projectId = renamingProjectId else { return }
        let displayName = renamingProjectText.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingProjectId = nil
        renamingProjectText = ""
        currentPanel?.endInlineTextEditing()
        guard !cancelled, !displayName.isEmpty else { return }
        actions.send(.renameProject(projectId, displayName: displayName))
    }

    private func beginWorkspaceRename(_ workspace: WorkspaceSidebarWorkspaceViewModel) {
        finishProjectRename(cancelled: true)
        renamingWorkspaceName = workspace.name
        renamingWorkspaceText = workspace.displayName
        currentPanel?.prepareForInlineTextEditing()
    }

    private func finishWorkspaceRename(cancelled: Bool = false) {
        guard let workspaceName = renamingWorkspaceName else { return }
        let displayName = renamingWorkspaceText.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingWorkspaceName = nil
        renamingWorkspaceText = ""
        currentPanel?.endInlineTextEditing()
        guard !cancelled, !displayName.isEmpty else { return }
        actions.send(.renameWorkspace(workspaceName, displayName: displayName))
    }

    private func updateWorkspaceReorder(
        _ workspace: WorkspaceSidebarWorkspaceViewModel,
        pointer: CGPoint,
    ) {
        guard renamingWorkspaceName == nil, renamingProjectId == nil else { return }
        if workspaceReorderSourceName == nil {
            pendingWorkspaceReorder = nil
            workspaceDragStartX = pointer.x
            workspaceDragOrder = projectWorkspaces.map(\.name)
            workspaceReorderSourceName = workspace.name
            beginWorkspaceSidebarItemDrag()
            workspaceDragDriver.start(
                sourceWorkspaceName: workspace.name,
                projectId: workspace.projectId,
                onTick: { updateWorkspaceDragFromScreen(workspace) },
                onPointer: { _ in updateWorkspaceDragFromScreen(workspace) },
                onFinish: { finishWorkspaceReorder(workspace) }
            )
        }
        guard workspaceReorderSourceName == workspace.name,
              workspaceDragOrder == projectWorkspaces.map(\.name) else { return }
        let screenPoint = normalizeAppKitScreenPoint(NSEvent.mouseLocation)
        guard currentPanel?.frame.contains(NSEvent.mouseLocation) == true else {
            workspaceReorderTarget = nil
            workspaceDragOffset = 0
            if let intent = workspaceCanvasDropIntent(sourceWorkspaceName: workspace.name, screenPoint: screenPoint) {
                WindowDropIntentOverlayPanelController.shared.show(intent.overlay)
            } else {
                WindowDropIntentOverlayPanelController.shared.hide()
            }
            return
        }
        WindowDropIntentOverlayPanelController.shared.hide()
        workspaceDragOffset = pointer.x - (workspaceDragStartX ?? pointer.x)
        workspaceReorderTarget = workspaceSidebarHorizontalReorderTarget(
            sourceWorkspaceName: workspace.name,
            pointer: pointer,
            frames: workspaceReorderFrames,
        )
    }

    private func updateWorkspaceDragFromScreen(_ workspace: WorkspaceSidebarWorkspaceViewModel) {
        guard workspaceReorderSourceName == workspace.name,
              let pointer = currentPanel?.convertScreenPointToSidebarContentPoint(NSEvent.mouseLocation)
        else { return }
        updateWorkspaceReorder(workspace, pointer: pointer)
    }

    private func finishWorkspaceReorder(_ workspace: WorkspaceSidebarWorkspaceViewModel) {
        guard workspaceReorderSourceName == workspace.name else { return }
        defer { clearWorkspaceReorderState(keepPendingDrop: true) }
        let screenPoint = normalizeAppKitScreenPoint(NSEvent.mouseLocation)
        if currentPanel?.frame.contains(NSEvent.mouseLocation) != true {
            guard let intent = workspaceCanvasDropIntent(sourceWorkspaceName: workspace.name, screenPoint: screenPoint),
                  let action = intent.action else { return }
            switch action {
                case .tabStack(let targetWindowId):
                    mergeWorkspaceIntoActiveTabGroupFromSidebarIfPossible(
                        sourceWorkspaceName: workspace.name, pointer: screenPoint, targetWindowId: targetWindowId
                    )
                case .split(let position):
                    mergeWorkspaceIntoActiveViewFromSidebarIfPossible(
                        sourceWorkspaceName: workspace.name, pointer: screenPoint, position: position
                    )
            }
            return
        }
        guard workspaceDragOrder == projectWorkspaces.map(\.name),
              let pointer = currentPanel?.convertScreenPointToSidebarContentPoint(NSEvent.mouseLocation),
              let target = workspaceSidebarHorizontalReorderTarget(
                  sourceWorkspaceName: workspace.name, pointer: pointer, frames: workspaceReorderFrames),
              target.workspaceName != workspace.name
        else { return }
        let pending = WorkspaceSidebarPendingHorizontalReorder(
            order: projectWorkspaces.map(\.name),
            offsets: workspaceReorderOffsets(source: workspace.name, target: target))
        pendingWorkspaceReorder = pending
        // Hold the final preview until the model publishes its reordered snapshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if pendingWorkspaceReorder?.id == pending.id { pendingWorkspaceReorder = nil }
        }
        actions.send(.reorderWorkspace(
            workspace.name,
            folderId: target.folderId,
            placement: target.placement,
        ))
    }

    private func workspaceReorderOffsets(
        source: String, target: WorkspaceSidebarHorizontalReorderTarget
    ) -> [String: CGFloat] {
        let order = projectWorkspaces.map(\.name)
        let steps = workspaceSidebarHorizontalReorderSteps(
            order: order, source: source, placement: target.placement
        )
        let reordered = order.enumerated().sorted {
            $0.offset + (steps[$0.element] ?? 0) < $1.offset + (steps[$1.element] ?? 0)
        }.map(\.element)
        let widths = Dictionary(uniqueKeysWithValues: projectWorkspaces.map { ($0.name, workspaceTabWidth($0)) })
        let separatorWidth = WinMuxBarStyle.strokeWidth + WinMuxSpacing.hairline * 2
        func origins(_ names: [String]) -> [String: CGFloat] {
            var x: CGFloat = 0
            var result: [String: CGFloat] = [:]
            for name in names {
                result[name] = x
                x += (widths[name] ?? 0) + separatorWidth
            }
            return result
        }
        let previous = origins(order)
        return origins(reordered).reduce(into: [:]) { result, item in
            result[item.key] = item.value - (previous[item.key] ?? 0)
        }
    }

    private func workspaceVisualOffset(for name: String) -> CGFloat {
        if let pendingWorkspaceReorder,
           pendingWorkspaceReorder.order == projectWorkspaces.map(\.name) {
            return pendingWorkspaceReorder.offsets[name] ?? 0
        }
        guard let source = workspaceReorderSourceName else { return 0 }
        if source == name { return workspaceDragOffset }
        guard let target = workspaceReorderTarget else { return 0 }
        return workspaceReorderOffsets(source: source, target: target)[name] ?? 0
    }

    private func clearWorkspaceReorderState(keepPendingDrop: Bool = false) {
        workspaceDragDriver.stop()
        WindowDropIntentOverlayPanelController.shared.hide()
        if workspaceReorderSourceName != nil { endWorkspaceSidebarItemDrag() }
        workspaceReorderSourceName = nil
        workspaceReorderTarget = nil
        workspaceDragStartX = nil
        workspaceDragOrder = nil
        workspaceDragOffset = 0
        if !keepPendingDrop { pendingWorkspaceReorder = nil }
    }
}

private struct WorkspaceSidebarHorizontalWorkspaceTab: View {
    let workspace: WorkspaceSidebarWorkspaceViewModel
    let contentHeight: CGFloat
    let isActive: Bool
    let isInUseOnOtherDisplay: Bool
    let isDropTarget: Bool
    let isReorderTarget: Bool
    let isReorderSource: Bool
    let isRenaming: Bool
    @Binding var renamingText: String
    @Binding var activeInUseOverrideWorkspaceName: String?
    @Binding var hoveredWorkspaceName: String?
    let actions: WorkspaceSidebarActions
    let allWindowMenuItems: [WorkspaceSidebarWindowMenuItem]
    let workspaceDestinations: [WorkspaceSidebarWorkspaceViewModel]
    let projectDestinations: [WorkspaceSidebarProjectViewModel]
    let onSelect: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onClose: () -> Void
    let onMoveToProject: (WorkspaceProjectId) -> Void
    let onReorderChanged: (CGPoint) -> Void
    let onReorderEnded: (CGPoint) -> Void

    @State private var isDropTargeted = false
    @State private var isDropSettling = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    private var isHovered: Bool {
        hoveredWorkspaceName == workspace.name
    }

    private var titleColor: Color {
        winMuxBarForeground(palette)
    }

    var body: some View {
        HStack(spacing: WinMuxSpacing.hairline) {
            if isRenaming {
                WorkspaceSidebarWorkspaceRenameField(
                    text: $renamingText,
                    workspaceName: workspace.name,
                    onCommit: onCommitRename,
                    onCancel: onCancelRename,
                    font: .systemFont(ofSize: projectTabsBarFontSize, weight: isActive || isHovered ? .medium : .regular),
                )
                .padding(.horizontal, WinMuxBarStyle.contentInset)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
            } else {
                Button(action: onSelect) {
                    HStack(spacing: WinMuxBarStyle.iconSpacing) {
                        Text(workspace.displayName)
                            .font(.system(size: projectTabsBarFontSize, weight: isActive || isHovered ? .medium : .regular))
                            .foregroundStyle(titleColor)
                            .opacity(isActive || isHovered ? 1 : WinMuxBarStyle.workspaceTabUnfocusedTextOpacity)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, WinMuxBarStyle.contentInset)
                    .frame(
                        minWidth: 0,
                        maxWidth: .infinity,
                        minHeight: contentHeight,
                        maxHeight: contentHeight,
                        alignment: .center,
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredWorkspaceName = hovering ? workspace.name : nil
            actions.hoverWorkspace(workspace.name, hovering)
        }
        .overlay {
            WorkspaceSidebarNativeContextMenu(items: contextMenuItems, colorScheme: colorScheme)
        }
        .modifier(WorkspaceSidebarWorkspaceReorderGestureModifier(
            isEnabled: !isRenaming,
            onChanged: onReorderChanged,
            onEnded: onReorderEnded,
        ))
        .onDrop(of: [workspaceSidebarDragPayloadType], delegate: WorkspaceSidebarDropDelegate(
            target: .workspace(workspace.name),
            actions: actions,
            performPayloadDrop: handlePayloadDrop,
            isTargeted: $isDropTargeted,
            isSettling: $isDropSettling,
        ))
        .overlay {
            if activeInUseOverrideWorkspaceName == workspace.name {
                WorkspaceSidebarInUseOverrideOverlay(text: inUseOverrideText) {
                    activeInUseOverrideWorkspaceName = nil
                    actions.send(.overrideWorkspaceInUse(workspace.name))
                }
            }
        }
        .animation(.easeOut(duration: 0.10), value: isHovered)
    }

    private var contextMenuItems: [WorkspaceSidebarNativeContextMenu.Item] {
        typealias Item = WorkspaceSidebarNativeContextMenu.Item
        var items = [
            Item(title: "Rename tab", action: onBeginRename),
            Item(title: "Close workspace", isEnabled: workspace.tabSummary.windowCount > 0, action: onClose),
        ]
        if !allWindowMenuItems.isEmpty {
            var windows = allWindowMenuItems.filter { !$0.isFloating }.map(windowMenuItem)
            let floating = allWindowMenuItems.filter(\.isFloating).map(windowMenuItem)
            if !windows.isEmpty && !floating.isEmpty { windows.append(.separator) }
            windows.append(contentsOf: floating)
            items.append(Item(title: "All windows", children: windows))
        }
        items.append(Item(
            title: "Move to workspace",
            isEnabled: !workspaceDestinations.isEmpty,
            children: workspaceDestinations.map { destination in
                Item(title: destination.displayName) {
                    actions.send(.moveWorkspace(workspace.name, toWorkspace: destination.name))
                }
            }
        ))
        if !projectDestinations.isEmpty {
            items.append(Item(title: "Move to project", children: projectDestinations.map { project in
                Item(title: project.displayName) { onMoveToProject(project.id) }
            }))
        }
        return items
    }

    private func windowMenuItem(_ item: WorkspaceSidebarWindowMenuItem) -> WorkspaceSidebarNativeContextMenu.Item {
        WorkspaceSidebarNativeContextMenu.Item(
            title: item.menuTitle,
            symbol: item.isFloating ? "pin.fill" : item.isFocused ? "checkmark" : "macwindow"
        ) {
            actions.send(.selectWindow(item.windowId))
        }
    }

    @ViewBuilder
    private var workspaceIcon: some View {
        if let icon = appIconImage(
            bundleIdentifier: workspace.tabSummary.appBundleId,
            bundlePath: workspace.tabSummary.appBundlePath,
        ) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: workspaceSidebarAppIconSize + 2, height: workspaceSidebarAppIconSize + 2)
                .cornerRadius(4)
        } else {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(winMuxBarForeground(palette))
                .frame(width: workspaceSidebarAppIconSize + 2, height: workspaceSidebarAppIconSize + 2)
        }
    }

    private var inUseOverrideText: String {
        if let monitorName = workspace.monitorName, !monitorName.isEmpty {
            return "In use on \(monitorName)"
        }
        return "In use on another display"
    }

    private func handlePayloadDrop(_ payload: WorkspaceSidebarDragPayload) {
        guard workspaceSidebarPayloadSourceWorkspaceName(payload) != workspace.name else {
            actions.send(.clearDropPreview)
            WindowDragCursorProxyPanel.shared.hide()
            return
        }
        switch payload {
            case .window(let windowId):
                actions.send(.moveWindow(windowId, toWorkspace: workspace.name))
            case .tabGroup(let representativeWindowId):
                actions.send(.moveTabGroup(representativeWindowId, toWorkspace: workspace.name))
        }
    }
}
