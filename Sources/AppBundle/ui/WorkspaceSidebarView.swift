import AppKit
import Common
import SwiftUI

// Shared interaction helpers retained for compatibility tests and legacy actions.
// The rendered panel is WorkspaceSidebarHorizontalBar.
@MainActor
struct WorkspaceSidebarView {
    @Environment(\.colorScheme) var colorScheme

    let snapshot: WorkspaceSidebarSnapshot
    let actions: WorkspaceSidebarActions
    let showsNotePad: Bool
    let onToggleNotePad: () -> Void
    @State var projectSwipeTranslation: CGFloat = 0
    @State var projectSwipeStartProjectId: WorkspaceProjectId? = nil
    @State var projectSwipeDidCrossBreakPoint = false
    @State var projectPagerWidth: CGFloat = 0
    @State var browseMode: WorkspaceSidebarBrowseMode = .activeProject
    @State var activeInUseOverrideWorkspaceName: String? = nil
    @State var isProjectMenuOpen = false
    @State var keepProjectMenuOpenOnNextProjectsChange = false
    @State var isProjectActionMenuPresentationActive = false
    @State var isSidebarCollapsing = false
    @State var isSidebarExpanding = false
    @State var renamingProjectId: WorkspaceProjectId? = nil
    @State var renamingProjectText = ""
    @State var renamingFolderId: WorkspaceFolderId? = nil
    @State var renamingFolderText = ""
    @State var renamingWorkspaceName: String? = nil
    @State var renamingWorkspaceText = ""
    @State var committedWorkspaceRenameName: String? = nil
    @State var searchText = ""
    @State var isSearchEditing = false
    @State var searchEditingPanel: WorkspaceSidebarPanel? = nil
    @State var selectedSearchTarget: WorkspaceSidebarSearchSelection? = nil
    @State var lastProjectEdgeDragDirection: Int? = nil
    @State var lastProjectEdgeDragSwitchAt: Date = .distantPast
    @State var showsPinnedActiveWorkspaceForBrowsedProject = true
    @State var workspaceReorderFrames: [WorkspaceSidebarWorkspaceReorderFrame] = []
    @State var workspaceReorderHitTestFrames: [WorkspaceSidebarWorkspaceReorderFrame] = []
    @State var workspaceReorderHitTestFolderFrames: [WorkspaceSidebarFolderReorderFrame] = []
    @State var folderReorderFrames: [WorkspaceSidebarFolderReorderFrame] = []
    @State var folderReorderHitTestFrames: [WorkspaceSidebarFolderReorderFrame] = []
    @State var workspaceReorderDrag: WorkspaceSidebarWorkspaceReorderDragState? = nil
    @StateObject var workspaceReorderDriver = WorkspaceSidebarWorkspaceReorderDriver()
    @State var folderReorderDrag: WorkspaceSidebarFolderReorderDragState? = nil
    @StateObject var folderReorderDriver = WorkspaceSidebarFolderReorderDriver()
    @State var folderExpansionOverrides: [WorkspaceFolderId: Bool] = [:]
    @State var pendingWorkspaceActivation: WorkspaceSidebarPendingActivation? = nil

    init(
        snapshot: WorkspaceSidebarSnapshot,
        actions: WorkspaceSidebarActions = WorkspaceSidebarActions(),
        showsNotePad: Bool = true,
        onToggleNotePad: @escaping () -> Void = {},
    ) {
        self.snapshot = snapshot
        self.actions = actions
        self.showsNotePad = showsNotePad
        self.onToggleNotePad = onToggleNotePad
    }

    var activeProjectThemeFamily: WorkspaceSidebarProjectThemeFamily? {
        workspaceSidebarProjectThemeFamily(
            projects: snapshot.projects,
            activeProjectId: snapshot.activeProjectId
        )
    }

    var sidebarPalette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(
            colorScheme: colorScheme,
            projectThemeFamily: activeProjectThemeFamily
        )
    }

    func normalizeActiveSidebarWidthIfNeeded(
        visibleWidth: CGFloat? = nil,
        expandedWidth: CGFloat
    ) {
        guard !browseMode.isSplit else { return }
        let currentWidth = visibleWidth ?? snapshot.visibleWidth
        guard currentWidth > expandedWidth + 0.5 else { return }
        guard let panel = currentPanel() else { return }
        panel.viewModel.isWorkspaceSidebarExpanded = true
        panel.animateVisibleSidebarWidth(
            expandedWidth,
            animation: .easeInOut(duration: panel.animationDuration)
        )
    }

    func isFolderExpanded(_ folderId: WorkspaceFolderId) -> Bool {
        folderExpansionOverrides[folderId] ?? workspaceSidebarFolderIsExpanded(folderId)
    }

    func setFolderExpanded(_ folderId: WorkspaceFolderId, _ isExpanded: Bool) {
        folderExpansionOverrides[folderId] = isExpanded
        setWorkspaceSidebarFolderExpanded(folderId, isExpanded: isExpanded)
    }

    func syncFolderExpansionOverrides() {
        folderExpansionOverrides = Dictionary(uniqueKeysWithValues: snapshot.folders.map {
            ($0.id, workspaceSidebarFolderIsExpanded($0.id))
        })
    }

    func beginProjectRename(_ project: WorkspaceSidebarProjectViewModel, browseIfNeeded: Bool = true) {
        debugWorkspaceSidebarRenameLog("beginProjectRename project=\(project.id.rawValue) displayName=\(project.displayName) active=\(snapshot.activeProjectId.rawValue) visibleWidth=\(snapshot.visibleWidth)")
        finishSidebarSearch(clearText: false)
        finishFolderRename(cancelled: true)
        if browseIfNeeded && project.id != snapshot.activeProjectId {
            browseMode = .split(otherProjectId: project.id)
        }
        renamingProjectId = project.id
        renamingProjectText = project.displayName
        isProjectMenuOpen = false
        currentPanel()?.prepareForInlineTextEditing()
    }

    func finishProjectRename(cancelled: Bool = false) {
        guard let projectId = renamingProjectId else { return }
        let displayName = renamingProjectText.trimmingCharacters(in: .whitespacesAndNewlines)
        debugWorkspaceSidebarRenameLog("finishProjectRename project=\(projectId.rawValue) cancelled=\(cancelled) raw=\(renamingProjectText) trimmed=\(displayName)")
        renamingProjectId = nil
        renamingProjectText = ""
        currentPanel()?.endInlineTextEditing()
        guard !cancelled, !displayName.isEmpty else { return }
        actions.send(.renameProject(projectId, displayName: displayName))
    }

    func beginFolderRename(_ folder: WorkspaceSidebarFolderViewModel) {
        debugWorkspaceSidebarRenameLog("beginFolderRename folder=\(folder.id.rawValue) displayName=\(folder.displayName)")
        finishSidebarSearch(clearText: false)
        finishProjectRename(cancelled: true)
        renamingFolderId = folder.id
        renamingFolderText = folder.displayName
        currentPanel()?.prepareForInlineTextEditing()
    }

    func finishFolderRename(cancelled: Bool = false) {
        guard let folderId = renamingFolderId else { return }
        let displayName = renamingFolderText.trimmingCharacters(in: .whitespacesAndNewlines)
        debugWorkspaceSidebarRenameLog("finishFolderRename folder=\(folderId.rawValue) cancelled=\(cancelled) raw=\(renamingFolderText) trimmed=\(displayName)")
        renamingFolderId = nil
        renamingFolderText = ""
        currentPanel()?.endInlineTextEditing()
        guard !cancelled, !displayName.isEmpty else { return }
        actions.send(.renameFolder(folderId, displayName: displayName))
    }

    func beginWorkspaceRename(_ workspace: WorkspaceSidebarWorkspaceViewModel) {
        debugWorkspaceSidebarRenameLog("beginWorkspaceRename workspace=\(workspace.name) displayName=\(workspace.displayName) targetScope=\(snapshot.targetMonitorScopeId) activeProject=\(snapshot.activeProjectId.rawValue) visibleWidth=\(snapshot.visibleWidth)")
        finishSidebarSearch(clearText: false)
        finishProjectRename(cancelled: true)
        finishFolderRename(cancelled: true)
        committedWorkspaceRenameName = nil
        renamingWorkspaceName = workspace.name
        renamingWorkspaceText = workspace.displayName
        currentPanel()?.prepareForInlineTextEditing()
    }

    func finishWorkspaceRename(cancelled: Bool = false) {
        guard let workspaceName = renamingWorkspaceName else { return }
        let displayName = renamingWorkspaceText.trimmingCharacters(in: .whitespacesAndNewlines)
        debugWorkspaceSidebarRenameLog("finishWorkspaceRename workspace=\(workspaceName) cancelled=\(cancelled) raw=\(renamingWorkspaceText) trimmed=\(displayName) targetScope=\(snapshot.targetMonitorScopeId)")
        currentPanel()?.endInlineTextEditing()
        guard !cancelled, !displayName.isEmpty else {
            clearWorkspaceRenameState()
            return
        }
        committedWorkspaceRenameName = workspaceName
        renamingWorkspaceText = displayName
        actions.send(.renameWorkspace(workspaceName, displayName: displayName))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard committedWorkspaceRenameName == workspaceName else { return }
            clearWorkspaceRenameState()
        }
    }

    func clearWorkspaceRenameState() {
        renamingWorkspaceName = nil
        renamingWorkspaceText = ""
        committedWorkspaceRenameName = nil
        currentPanel()?.endInlineTextEditing()
    }

    func reconcileWorkspaceRenameState() {
        guard let renamingWorkspaceName else { return }
        let renamedWorkspace = snapshot.workspaces.first { workspace in
            workspace.name == renamingWorkspaceName
        }
        if renamedWorkspace == nil {
            finishWorkspaceRename(cancelled: true)
        } else if committedWorkspaceRenameName == renamingWorkspaceName,
                  renamedWorkspace?.displayName == renamingWorkspaceText
        {
            clearWorkspaceRenameState()
        }
    }

    func currentPanel() -> WorkspaceSidebarPanel? {
        WorkspaceSidebarPanel.panel(for: snapshot.targetMonitorScopeId)
    }

    func beginSidebarSearchIfNeeded(panel: WorkspaceSidebarPanel? = nil) {
        guard workspaceSidebarSearchIsEnabled else {
            finishSidebarSearch(clearText: true)
            return
        }
        guard renamingProjectId == nil, renamingFolderId == nil, renamingWorkspaceName == nil, !isSearchEditing else { return }
        guard snapshot.visibleWidth > snapshot.configuration.collapsedWidth + 0.5 || isSidebarExpanding else { return }
        let editingPanel = panel ?? currentPanel() ?? WorkspaceSidebarPanel.shared
        adoptCommandSidebarSearchIfNeeded(panel: editingPanel)
    }

    func adoptCommandSidebarSearchIfNeeded(panel editingPanel: WorkspaceSidebarPanel) {
        guard workspaceSidebarSearchIsEnabled else {
            editingPanel.shouldLockNextSidebarSearchExpansion = false
            editingPanel.bufferedCommandSidebarSearchKeys = []
            finishSidebarSearch(clearText: true)
            return
        }
        guard renamingProjectId == nil, renamingFolderId == nil, renamingWorkspaceName == nil else { return }
        if !isSearchEditing {
            isSearchEditing = true
            searchEditingPanel = editingPanel
            selectFirstSearchTarget()
        }
        let locksExpansion = editingPanel.commandExpansionLocksCollapse || editingPanel.shouldLockNextSidebarSearchExpansion
        editingPanel.shouldLockNextSidebarSearchExpansion = false
        editingPanel.beginInlineTextEditing(
            locksExpansion: locksExpansion,
            cancelsOnPointerExit: false,
            onCancel: {
                finishSidebarSearch(clearText: true)
            },
            onKeyDown: { key in
                handleSidebarSearchKey(key)
            },
        )
        let bufferedKeys = editingPanel.bufferedCommandSidebarSearchKeys
        editingPanel.bufferedCommandSidebarSearchKeys = []
        for key in bufferedKeys {
            handleSidebarSearchKey(key)
        }
    }

    func finishSidebarSearch(clearText: Bool) {
        let panel = searchEditingPanel
        if isSearchEditing {
            isSearchEditing = false
            (panel ?? currentPanel() ?? WorkspaceSidebarPanel.shared).endInlineTextEditing()
            searchEditingPanel = nil
        }
        if clearText {
            searchText = ""
        }
        selectedSearchTarget = nil
    }

    func handleSidebarSearchKey(_ key: WorkspaceSidebarInlineTextKey) {
        guard workspaceSidebarSearchIsEnabled else {
            finishSidebarSearch(clearText: true)
            return
        }
        switch key {
            case .text(let inserted):
                searchText += inserted
                selectFirstSearchTarget()
            case .deleteBackward:
                if !searchText.isEmpty {
                    searchText.removeLast()
                }
                selectFirstSearchTarget()
            case .deleteWordBackward:
                searchText.deleteLastWord()
                selectFirstSearchTarget()
            case .deleteToBeginningOfLine:
                searchText = ""
                selectedSearchTarget = nil
            case .deleteForward:
                break
            case .commit:
                activateSelectedSearchTarget()
            case .cancel:
                let panel = searchEditingPanel ?? WorkspaceSidebarPanel.shared
                finishSidebarSearch(clearText: true)
                closeWorkspaceSidebarFromCommand(panel)
            case .moveUp:
                moveSearchSelection(delta: -1)
            case .moveDown:
                moveSearchSelection(delta: 1)
            case .ignored:
                break
        }
    }

    func selectFirstSearchTarget() {
        selectedSearchTarget = searchText.isEmpty ? nil : currentSearchSelections().first
    }

    func moveSearchSelection(delta: Int) {
        let selections = currentSearchSelections()
        guard !selections.isEmpty else {
            selectedSearchTarget = nil
            return
        }
        guard let selectedSearchTarget,
              let index = selections.firstIndex(of: selectedSearchTarget)
        else {
            self.selectedSearchTarget = selections.first
            return
        }
        let nextIndex = max(0, min(selections.count - 1, index + delta))
        self.selectedSearchTarget = selections[nextIndex]
    }

    func activateSelectedSearchTarget() {
        guard let selectedSearchTarget else { return }
        let panel = searchEditingPanel ?? WorkspaceSidebarPanel.shared
        switch selectedSearchTarget {
            case .workspace(let workspaceName):
                beginPendingWorkspaceActivation(workspaceName)
                actions.send(.selectWorkspace(workspaceName))
        }
        finishSidebarSearch(clearText: true)
        closeWorkspaceSidebarFromCommand(panel)
    }

    func currentSearchSelections() -> [WorkspaceSidebarSearchSelection] {
        let workspaces = currentFilteredProjectWorkspaces()
        return workspaceSidebarSearchSelections(workspaces: workspaces)
    }

    func currentFilteredProjectWorkspaces() -> [WorkspaceSidebarWorkspaceViewModel] {
        let visibleWorkspacesByProject = workspaceSidebarVisibleWorkspacesByProject(
            workspaces: snapshot.workspaces,
            selectedScopeId: snapshot.selectedMonitorScopeId,
            focusedMonitorScopeId: snapshot.focusedMonitorScopeId,
            targetMonitorScopeId: snapshot.targetMonitorScopeId,
            browsedProjectId: browsedProjectId,
            projectsEnabled: projectsAreEnabled(),
        )
        let filteredWorkspacesByProject = workspaceSidebarFilteredWorkspacesByProject(
            visibleWorkspacesByProject,
            projects: snapshot.projects,
            query: sidebarSearchQuery,
        )
        let projectId: WorkspaceProjectId
        if let index = projectPagerDisplayIndex, snapshot.projects.indices.contains(index) {
            projectId = snapshot.projects[index].id
        } else {
            projectId = snapshot.activeProjectId
        }
        return filteredWorkspacesByProject[projectId] ?? []
    }
}

extension WorkspaceSidebarView {
    var browsedProjectId: WorkspaceProjectId? {
        browseMode.otherProjectId
    }

    var sidebarSearchQuery: String {
        workspaceSidebarEffectiveSearchQuery(searchText)
    }

    var isSidebarSearchFiltering: Bool {
        !sidebarSearchQuery.isEmpty
    }
}

private func workspaceSidebarDragPointer(from notification: Notification) -> CGPoint? {
    (notification.userInfo?[workspaceSidebarDragPointerUserInfoKey] as? NSValue)?.pointValue
}

private func notificationPanel(from notification: Notification) -> WorkspaceSidebarPanel? {
    notification.object as? WorkspaceSidebarPanel
}

struct WorkspaceSidebarContainerView: View {
    @ObservedObject var viewModel: TrayMenuModel
    let actions: WorkspaceSidebarActions

    var body: some View {
        WorkspaceSidebarHorizontalBar(
            snapshot: workspaceSidebarSnapshot(from: viewModel),
            actions: actions,
        )
    }
}
