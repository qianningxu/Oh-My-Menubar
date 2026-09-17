import AppKit
import SwiftUI

extension WorkspaceSidebarView {
    func isWorkspaceReorderEnabled(
        workspace _: WorkspaceSidebarWorkspaceViewModel,
        expansionProgress: CGFloat,
        isPinnedActiveWorkspace: Bool,
        isInteractive: Bool
    ) -> Bool {
        workspaceSidebarWorkspaceReorderIsEnabled(
            isCompact: expansionProgress < workspaceSidebarRowsRevealProgress,
            isSearchFiltering: isSidebarSearchFiltering,
            isRenamingWorkspace: renamingWorkspaceName != nil || renamingProjectId != nil || renamingFolderId != nil,
            isPinnedActiveWorkspace: isPinnedActiveWorkspace,
            isInteractive: isInteractive
        )
    }

    func isWorkspaceReorderSource(_ workspace: WorkspaceSidebarWorkspaceViewModel) -> Bool {
        workspaceSidebarWorkspaceSourceIsProjectedDragAnchor(
            isSource: workspaceReorderDrag?.sourceWorkspaceName == workspace.name &&
                workspaceReorderDrag?.projectId == workspace.folderId.backingProjectId,
            target: workspaceReorderDrag?.target
        )
    }

    func isFolderReorderEnabled(
        projectId: WorkspaceProjectId,
        expansionProgress: CGFloat,
        isInteractive: Bool
    ) -> Bool {
        workspaceSidebarFolderReorderIsEnabled(
            projectId: projectId,
            isCompact: expansionProgress < workspaceSidebarRowsRevealProgress,
            isSearchFiltering: isSidebarSearchFiltering,
            isRenamingWorkspace: renamingWorkspaceName != nil || renamingProjectId != nil || renamingFolderId != nil,
            isInteractive: isInteractive
        )
    }

    func isFolderReorderSource(_ projectId: WorkspaceProjectId) -> Bool {
        folderReorderDrag?.sourceProjectId == projectId
    }

    func workspaceListEntries(
        workspaces: [WorkspaceSidebarWorkspaceViewModel],
        projectId: WorkspaceProjectId
    ) -> [WorkspaceSidebarWorkspaceListEntry] {
        workspaceSidebarWorkspaceListEntries(
            workspaces: workspaces,
            projectId: projectId,
            sourceWorkspaceName: workspaceReorderDrag?.sourceWorkspaceName,
            sourceWorkspace: workspaceReorderPreviewWorkspace(),
            target: workspaceReorderDrag?.target
        )
    }

    func folderListEntries(
        sections: [WorkspaceSidebarFolderSection]
    ) -> [WorkspaceSidebarFolderListEntry] {
        workspaceSidebarFolderListEntries(
            sections: sections,
            sourceProjectId: folderReorderDrag?.sourceProjectId,
            target: folderReorderDrag?.target
        )
    }

    func isWorkspaceFolderDropTarget(_ projectId: WorkspaceProjectId) -> Bool {
        guard let target = workspaceReorderDrag?.target,
              case .moveToFolder(let folderTarget) = target
        else { return false }
        return folderTarget.projectId == projectId
    }

    func isWorkspaceFolderInteractionTarget(_ projectId: WorkspaceProjectId) -> Bool {
        workspaceSidebarWorkspaceInteractionProjectId(workspaceReorderDrag) == projectId
    }

    func isProjectReorderDropTarget(_ projectId: WorkspaceProjectId) -> Bool {
        workspaceSidebarProjectFrameIsVisibleDropTarget(
            projectId: projectId,
            sourceProjectId: workspaceReorderDrag?.projectId
        )
    }

    func isWorkspaceProjectPreviewTarget(_ projectId: WorkspaceProjectId) -> Bool {
        guard workspaceSidebarWorkspaceInteractionProjectId(workspaceReorderDrag) == projectId else {
            return false
        }
        return workspaceSidebarIsProjectPreviewTarget(
            projectId: projectId,
            sourceWorkspaceName: workspaceReorderDrag?.sourceWorkspaceName,
            sourceWorkspace: workspaceReorderPreviewWorkspace(),
            target: workspaceReorderDrag?.target
        )
    }

    func workspaceReorderPlaceholder(
        expansionProgress: CGFloat,
        nestedContentIndent: CGFloat = 0
    ) -> some View {
        WorkspaceSidebarWorkspaceReorderPlaceholder(
            width: workspaceSidebarSectionWidth(expansionProgress, layout: snapshot.configuration),
            nestedContentIndent: nestedContentIndent,
            previewWorkspace: workspaceReorderPreviewWorkspace()
        )
    }

    func workspaceReorderPreviewWorkspace() -> WorkspaceSidebarWorkspaceViewModel? {
        guard let sourceWorkspaceName = workspaceReorderDrag?.sourceWorkspaceName else { return nil }
        return snapshot.workspaces.first { $0.name == sourceWorkspaceName }
    }

    func updateWorkspaceReorderDrag(
        workspace: WorkspaceSidebarWorkspaceViewModel,
        projectId: WorkspaceProjectId,
        pointer: CGPoint,
        startsTracking: Bool = true,
        advancesPreview: Bool = false,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        let beginsTracking = startsTracking && !workspaceReorderDriver.isTracking(
            sourceWorkspaceName: workspace.name,
            projectId: projectId
        )
        if beginsTracking {
            WindowDragCursorProxyPanel.shared.hide()
            clearFolderReorderDragImmediately()
            workspaceReorderHitTestFrames = workspaceReorderFrames
            workspaceReorderHitTestFolderFrames = folderReorderFrames
            startWorkspaceReorderTrackingIfNeeded(workspace: workspace, projectId: projectId)
        }
        workspaceReorderDriver.note(pointer: pointer)
        if workspaceReorderDrag == nil {
            NotificationCenter.default.post(name: workspaceSidebarDismissProjectMenusNotification, object: nil)
            isProjectMenuOpen = false
        }
        let interactionFolderFrames = workspaceSidebarFolderReorderFramesForInteraction(
            liveFrames: folderReorderFrames,
            frozenFrames: workspaceReorderHitTestFolderFrames
        )
        let interactionFolderProjectId = workspaceSidebarWorkspaceFolderTarget(
            sourceWorkspaceName: workspace.name,
            sourceProjectId: projectId,
            pointer: pointer,
            frames: interactionFolderFrames
        )?.projectId
        let candidateTarget = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: workspace.name,
            sourceProjectId: projectId,
            pointer: pointer,
            workspaceFrames: workspaceSidebarWorkspaceReorderFramesForInteraction(
                liveFrames: workspaceReorderFrames,
                frozenFrames: workspaceReorderHitTestFrames,
                destinationProjectId: interactionFolderProjectId
            ),
            folderFrames: interactionFolderFrames
        )
        let hitTestFrames = workspaceSidebarWorkspaceReorderFramesForHitTesting(
            liveFrames: workspaceReorderFrames,
            frozenFrames: workspaceReorderHitTestFrames
        )
        let hitTestFolderFrames = workspaceSidebarFolderReorderFramesForHitTesting(
            liveFrames: folderReorderFrames,
            frozenFrames: workspaceReorderHitTestFolderFrames
        )
        let isPointerInsideSidebar = WorkspaceSidebarPanel.panel(
            containing: MousePointerTracker.shared.currentSample.point
        ) != nil
        let isPointerInSourceOriginalSlot = candidateTarget == nil &&
            workspaceSidebarWorkspacePointerIsInSourceOriginalSlot(
                sourceWorkspaceName: workspace.name,
                sourceProjectId: projectId,
                pointer: pointer,
                frames: hitTestFrames
            )
        let lastValidTarget: WorkspaceSidebarWorkspaceDragTarget? = if let candidateTarget {
            candidateTarget
        } else if isPointerInSourceOriginalSlot {
            nil
        } else {
            workspaceReorderDrag?.lastValidTarget
        }
        let desiredPreviewTarget = candidateTarget ?? (
            isPointerInSourceOriginalSlot ? nil : lastValidTarget ?? workspaceReorderDrag?.target
        )
        let target: WorkspaceSidebarWorkspaceDragTarget?
        let nextPreviewStepAt: TimeInterval?
        if !isPointerInsideSidebar {
            target = nil
            nextPreviewStepAt = nil
        } else if advancesPreview {
            let resolution = workspaceSidebarWorkspacePacedPreviewResolution(
                currentTarget: workspaceReorderDrag?.target,
                desiredTarget: desiredPreviewTarget,
                nextPreviewStepAt: workspaceReorderDrag?.nextPreviewStepAt,
                now: now,
                sourceWorkspaceName: workspace.name,
                sourceProjectId: projectId,
                frames: hitTestFrames,
                folderFrames: hitTestFolderFrames
            )
            target = resolution.target
            nextPreviewStepAt = resolution.nextPreviewStepAt
        } else {
            target = workspaceReorderDrag?.target
            // Pointer events update the exact destination without advancing
            // structural presentation. Keep the current transition deadline
            // so another sibling cannot start before this one has completed.
            nextPreviewStepAt = workspaceReorderDrag?.nextPreviewStepAt
        }
        let exactSidebarTarget = candidateTarget ?? (
            isPointerInSourceOriginalSlot ? nil : lastValidTarget
        )
        updateWorkspaceCanvasDropIntentOverlay(
            sourceWorkspaceName: workspace.name,
            screenPoint: MousePointerTracker.shared.currentSample.point,
            hasSidebarTarget: isPointerInsideSidebar && exactSidebarTarget != nil
        )
        if let current = workspaceReorderDrag,
           current.sourceWorkspaceName == workspace.name,
           current.projectId == projectId,
           current.target == target,
           current.lastValidTarget == lastValidTarget,
           current.nextPreviewStepAt == nextPreviewStepAt
        {
            return
        }
        let targetChanged = workspaceReorderDrag?.target != target
        var transaction = Transaction()
        transaction.animation = targetChanged ? workspaceSidebarWorkspaceReorderAnimation : nil
        withTransaction(transaction) {
            workspaceReorderDrag = WorkspaceSidebarWorkspaceReorderDragState(
                sourceWorkspaceName: workspace.name,
                projectId: projectId,
                target: target,
                lastValidTarget: lastValidTarget,
                nextPreviewStepAt: nextPreviewStepAt
            )
        }
    }

    func startWorkspaceReorderTrackingIfNeeded(
        workspace: WorkspaceSidebarWorkspaceViewModel,
        projectId: WorkspaceProjectId
    ) {
        guard !workspaceReorderDriver.isTracking(sourceWorkspaceName: workspace.name, projectId: projectId) else {
            return
        }
        workspaceReorderDriver.start(
            sourceWorkspaceName: workspace.name,
            projectId: projectId,
            onTick: {
                continueWorkspaceReorderDragFromMouse(
                    sourceWorkspaceName: workspace.name,
                    projectId: projectId
                )
            },
            onPointer: { screenPoint in
                continueWorkspaceReorderDragFromPointerEvent(
                    sourceWorkspaceName: workspace.name,
                    projectId: projectId,
                    screenPoint: screenPoint
                )
            },
            onFinish: {
                finishWorkspaceReorderDragFromMouse(
                    sourceWorkspaceName: workspace.name,
                    projectId: projectId
                )
            }
        )
    }

    func continueWorkspaceReorderDragFromPointerEvent(
        sourceWorkspaceName: String,
        projectId: WorkspaceProjectId,
        screenPoint: CGPoint
    ) {
        guard let workspace = snapshot.workspaces.first(where: { $0.name == sourceWorkspaceName }),
              let pointer = workspaceReorderContentPointer(screenPoint: screenPoint)
        else { return }
        updateWorkspaceReorderDrag(
            workspace: workspace,
            projectId: projectId,
            pointer: pointer,
            startsTracking: false,
            advancesPreview: false
        )
    }

    func continueWorkspaceReorderDragFromMouse(
        sourceWorkspaceName: String,
        projectId: WorkspaceProjectId
    ) {
        noteCurrentMousePointerSample()
        guard let workspace = snapshot.workspaces.first(where: { $0.name == sourceWorkspaceName }),
              let pointer = currentWorkspaceReorderContentPointer()
        else { return }
        updateWorkspaceReorderDrag(
            workspace: workspace,
            projectId: projectId,
            pointer: pointer,
            startsTracking: false,
            advancesPreview: true
        )
    }

    func finishWorkspaceReorderDragFromMouse(
        sourceWorkspaceName: String,
        projectId: WorkspaceProjectId
    ) {
        noteCurrentMousePointerSample()
        guard let drag = workspaceReorderDrag,
              drag.sourceWorkspaceName == sourceWorkspaceName,
              drag.projectId == projectId,
              let workspace = snapshot.workspaces.first(where: { $0.name == sourceWorkspaceName })
        else {
            cancelWorkspaceReorderDrag()
            return
        }
        finishWorkspaceReorderDrag(
            workspace: workspace,
            projectId: projectId,
            pointer: currentWorkspaceReorderContentPointer() ?? workspaceReorderDriver.latestPointer ?? .zero
        )
    }

    func currentWorkspaceReorderContentPointer() -> CGPoint? {
        workspaceReorderContentPointer(screenPoint: MousePointerTracker.shared.currentSample.point)
    }

    /// Reorder frames live in the sidebar's named SwiftUI content space while
    /// the mouse tracker stores normalized screen coordinates.  Keep this
    /// conversion at the boundary so every mouse-up path hits the same slot.
    func workspaceReorderContentPointer(screenPoint: CGPoint) -> CGPoint? {
        currentPanel()?.convertScreenPointToSidebarContentPoint(
            denormalizedAppKitScreenPoint(screenPoint)
        )
    }

    func finishWorkspaceReorderDrag(
        workspace: WorkspaceSidebarWorkspaceViewModel,
        projectId: WorkspaceProjectId,
        pointer: CGPoint,
        screenPoint: CGPoint? = nil
    ) {
        guard let drag = workspaceReorderDrag,
              drag.sourceWorkspaceName == workspace.name,
              drag.projectId == projectId,
              !drag.isCommitting
        else { return }
        // The display-link tick has already resolved the last valid sidebar
        // slot. Re-hit-testing on mouse-up races the preview animation and was
        // the source of drops unexpectedly jumping to a folder edge.
        let screenPoint = screenPoint ?? MousePointerTracker.shared.currentSample.point
        // The only intentional reason to discard the sidebar slot is a real
        // canvas destination. Treat every other mouse-up (including a panel
        // hit-test miss during the release frame) as a commit to the last
        // concrete sidebar slot.
        let canvasDropIntent = workspaceCanvasDropIntent(
            sourceWorkspaceName: workspace.name,
            screenPoint: screenPoint
        )
        let hasCanvasDropIntent = canvasDropIntent != nil
        let interactionFolderFrames = workspaceSidebarFolderReorderFramesForInteraction(
            liveFrames: folderReorderFrames,
            frozenFrames: workspaceReorderHitTestFolderFrames
        )
        let interactionFolderProjectId = workspaceSidebarWorkspaceFolderTarget(
            sourceWorkspaceName: workspace.name,
            sourceProjectId: projectId,
            pointer: pointer,
            frames: interactionFolderFrames
        )?.projectId
        let finalCandidate = workspaceSidebarWorkspaceDragTarget(
            sourceWorkspaceName: workspace.name,
            sourceProjectId: projectId,
            pointer: pointer,
            workspaceFrames: workspaceSidebarWorkspaceReorderFramesForInteraction(
                liveFrames: workspaceReorderFrames,
                frozenFrames: workspaceReorderHitTestFrames,
                destinationProjectId: interactionFolderProjectId
            ),
            folderFrames: interactionFolderFrames
        )
        let finalPointerIsInSourceOriginalSlot = finalCandidate == nil &&
            workspaceSidebarWorkspacePointerIsInSourceOriginalSlot(
                sourceWorkspaceName: workspace.name,
                sourceProjectId: projectId,
                pointer: pointer,
                frames: workspaceSidebarWorkspaceReorderFramesForHitTesting(
                    liveFrames: workspaceReorderFrames,
                    frozenFrames: workspaceReorderHitTestFrames
                )
            )
        let target = finalPointerIsInSourceOriginalSlot
            ? nil
            : workspaceSidebarWorkspaceDragFinishTarget(
                finalCandidate: finalCandidate,
                lastValidTarget: drag.lastValidTarget,
                currentTarget: drag.target,
                hasCanvasDropIntent: hasCanvasDropIntent
            )
        guard let target else {
            clearWorkspaceReorderDragImmediately()
            WindowDropIntentOverlayPanelController.shared.hide()
            guard let dropIntent = canvasDropIntent else {
                activateWorkspaceAfterUncommittedReorderDrag(
                    workspace: workspace,
                    projectId: projectId,
                    screenPoint: screenPoint
                )
                return
            }
            // The centre cell remains part of the canvas guide, but it is not
            // an operation for a sidebar workspace drag. Releasing there is a
            // deliberate no-op rather than falling through to a stale sidebar
            // reorder target.
            guard let action = dropIntent.action else { return }
            switch action {
                case .tabStack(let targetWindowId):
                    mergeWorkspaceIntoActiveTabGroupFromSidebarIfPossible(
                        sourceWorkspaceName: workspace.name,
                        pointer: screenPoint,
                        targetWindowId: targetWindowId
                    )
                case .split(let position):
                    mergeWorkspaceIntoActiveViewFromSidebarIfPossible(
                        sourceWorkspaceName: workspace.name,
                        pointer: screenPoint,
                        position: position
                    )
            }
            return
        }
        guard let action = workspaceSidebarWorkspaceDragFinishAction(
            sourceWorkspaceName: workspace.name,
            target: target
        ) else {
            clearWorkspaceReorderDragImmediately()
            WindowDropIntentOverlayPanelController.shared.hide()
            return
        }

        // Stop sampling immediately, but keep the projected landing slot on
        // screen until the authoritative sidebar snapshot reflects the move.
        // Clearing the preview before that refresh produces a visible snap
        // back to the old order on mouse-up.
        var committingDrag = drag
        // The one-step preview may still be catching up. Mouse-up must retain
        // the exact final hit-test destination instead of that visual waypoint.
        committingDrag.target = target
        committingDrag.lastValidTarget = target
        committingDrag.nextPreviewStepAt = nil
        committingDrag.isCommitting = true
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            workspaceReorderDrag = committingDrag
        }
        workspaceReorderDriver.stop()
        WindowDropIntentOverlayPanelController.shared.hide()
        actions.send(action)
        Task { @MainActor in
            await updateWorkspaceSidebarModel()
            guard workspaceReorderDrag?.sourceWorkspaceName == workspace.name,
                  workspaceReorderDrag?.projectId == projectId
            else { return }
            clearWorkspaceReorderDragImmediately()
        }
    }

    func activateWorkspaceAfterUncommittedReorderDrag(
        workspace: WorkspaceSidebarWorkspaceViewModel,
        projectId: WorkspaceProjectId,
        screenPoint: CGPoint
    ) {
        guard WorkspaceSidebarPanel.panel(containing: screenPoint) != nil else { return }
        guard allowsWorkspaceActivation(projectId: projectId) else { return }
        if workspaceSidebarWorkspaceIsInUseOnOtherDisplay(
            workspace,
            selectedScopeId: snapshot.targetMonitorScopeId
        ) {
            activeInUseOverrideWorkspaceName = workspace.name
            return
        }
        guard shouldHandleWorkspaceSidebarActivation(
            isEditing: false,
            isSidebarDragInProgress: false
        ) else { return }
        activeInUseOverrideWorkspaceName = nil
        beginPendingWorkspaceActivation(workspace.name)
        actions.send(.selectWorkspace(workspace.name))
    }

    func cancelWorkspaceReorderDrag() {
        clearWorkspaceReorderDragImmediately()
        WindowDropIntentOverlayPanelController.shared.hide()
    }

    func clearWorkspaceReorderDragImmediately() {
        let hadWorkspaceReorderDrag = workspaceReorderDrag != nil || workspaceReorderDriver.isTracking
        workspaceReorderDriver.stop()
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            workspaceReorderDrag = nil
        }
        workspaceReorderHitTestFrames = []
        workspaceReorderHitTestFolderFrames = []
        if hadWorkspaceReorderDrag {
            WindowDragCursorProxyPanel.shared.hide()
        }
    }

    func updateFolderReorderDrag(
        section: WorkspaceSidebarFolderSection,
        pointer: CGPoint,
        startsTracking: Bool = true
    ) {
        if startsTracking {
            WindowDragCursorProxyPanel.shared.hide()
            clearWorkspaceReorderDragImmediately()
            folderReorderHitTestFrames = folderReorderFrames
            startFolderReorderTrackingIfNeeded(projectId: section.project.id)
        }
        folderReorderDriver.note(pointer: pointer)
        if folderReorderDrag == nil {
            NotificationCenter.default.post(name: workspaceSidebarDismissProjectMenusNotification, object: nil)
            isProjectMenuOpen = false
        }
        let target = workspaceSidebarFolderReorderTarget(
            sourceProjectId: section.project.id,
            pointer: pointer,
            frames: workspaceSidebarFolderReorderFramesForHitTesting(
                liveFrames: folderReorderFrames,
                frozenFrames: folderReorderHitTestFrames
            )
        )
        if let current = folderReorderDrag,
           current.sourceProjectId == section.project.id,
           current.target == target
        {
            return
        }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            folderReorderDrag = WorkspaceSidebarFolderReorderDragState(
                sourceProjectId: section.project.id,
                target: target
            )
        }
    }

    func startFolderReorderTrackingIfNeeded(projectId: WorkspaceProjectId) {
        guard !folderReorderDriver.isTracking(sourceProjectId: projectId) else { return }
        folderReorderDriver.start(
            sourceProjectId: projectId,
            onTick: {
                continueFolderReorderDragFromMouse(sourceProjectId: projectId)
            },
            onFinish: {
                finishFolderReorderDragFromMouse(sourceProjectId: projectId)
            }
        )
    }

    func continueFolderReorderDragFromMouse(sourceProjectId: WorkspaceProjectId) {
        noteCurrentMousePointerSample()
        guard let section = folderReorderSection(projectId: sourceProjectId),
              let pointer = currentWorkspaceReorderContentPointer()
        else { return }
        updateFolderReorderDrag(section: section, pointer: pointer, startsTracking: false)
    }

    func finishFolderReorderDragFromMouse(sourceProjectId: WorkspaceProjectId) {
        noteCurrentMousePointerSample()
        guard let drag = folderReorderDrag,
              drag.sourceProjectId == sourceProjectId,
              let section = folderReorderSection(projectId: sourceProjectId)
        else {
            cancelFolderReorderDrag()
            return
        }
        finishFolderReorderDrag(
            section: section,
            pointer: currentWorkspaceReorderContentPointer() ?? folderReorderDriver.latestPointer ?? .zero
        )
    }

    func finishFolderReorderDrag(
        section: WorkspaceSidebarFolderSection,
        pointer: CGPoint
    ) {
        let target = workspaceSidebarFolderReorderTarget(
            sourceProjectId: section.project.id,
            pointer: pointer,
            frames: workspaceSidebarFolderReorderFramesForHitTesting(
                liveFrames: folderReorderFrames,
                frozenFrames: folderReorderHitTestFrames
            )
        ) ?? folderReorderDrag?.target
        clearFolderReorderDragImmediately()
        guard let target else { return }
        actions.send(.reorderFolder(section.folder.id, placement: target.placement))
    }

    func cancelFolderReorderDrag() {
        clearFolderReorderDragImmediately()
    }

    func clearFolderReorderDragImmediately() {
        let hadFolderReorderDrag = folderReorderDrag != nil || folderReorderDriver.isTracking
        folderReorderDriver.stop()
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            folderReorderDrag = nil
        }
        folderReorderHitTestFrames = []
        if hadFolderReorderDrag {
            WindowDragCursorProxyPanel.shared.hide()
        }
    }

    func folderReorderSection(projectId: WorkspaceProjectId) -> WorkspaceSidebarFolderSection? {
        guard let folder = snapshot.folders.first(where: { $0.id.backingProjectId == projectId }),
              !folder.isUnfolded
        else { return nil }
        let workspaces = workspaceSidebarNonEmptyFolderWorkspaces(
            snapshot.workspaces.filter { $0.folderId == folder.id }
        )
        guard !workspaces.isEmpty else { return nil }
        return WorkspaceSidebarFolderSection(folder: folder, workspaces: workspaces)
    }

    func updateWorkspaceCanvasDropIntentOverlay(
        sourceWorkspaceName: String,
        screenPoint: CGPoint,
        hasSidebarTarget: Bool
    ) {
        guard !hasSidebarTarget,
              let dropIntent = workspaceCanvasDropIntent(
                sourceWorkspaceName: sourceWorkspaceName,
                screenPoint: screenPoint
              )
        else {
            WindowDropIntentOverlayPanelController.shared.hide()
            return
        }
        WindowDropIntentOverlayPanelController.shared.show(dropIntent.overlay)
    }

}
