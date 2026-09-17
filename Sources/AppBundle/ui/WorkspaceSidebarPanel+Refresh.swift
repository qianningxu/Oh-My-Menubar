import AppKit

extension WorkspaceSidebarPanel {
    func refresh() {
        refresh(on: workspaceSidebarLocalPanelMonitor())
    }

    func refresh(on monitor: Monitor) {
        guard let layout = currentSidebarPanelLayout(on: monitor) else {
            resetHiddenSidebarState()
            return
        }

        if frame != layout.frame {
            setFrame(layout.frame, display: true, animate: false)
        }
        updateProjectPresentationLayout()
        if viewModel.isWorkspaceSidebarAutoHideEnabled {
            updateAutoHideVisibility(at: NSEvent.mouseLocation)
        } else {
            stopHoverMonitoring()
            viewModel.workspaceSidebarVisibleWidth = layout.frame.width
            viewModel.isWorkspaceSidebarExpanded = true
            ignoresMouseEvents = false
            orderFrontRegardless()
        }
    }

    func refreshForCurrentDragIfNeeded() {
        guard isMouseWindowDragInProgress() else { return }
        WorkspaceSidebarPanel.refreshAll()
    }

    func resetHiddenSidebarState() {
        stopHoverMonitoring()
        workspaceSidebarDropTargets = []
        TrayMenuModel.shared.setIfChanged(\.workspaceSidebarDropPreview, to: nil)
        TrayMenuModel.shared.setIfChanged(\.workspaceSidebarHoveredWorkspaceName, to: nil)
        viewModel.setIfChanged(\.workspaceSidebarVisibleWidth, to: 0)
        viewModel.setIfChanged(\.isWorkspaceSidebarExpanded, to: false)
        projectActionMenuPresentationExtraWidth = 0
        projectMenuPresentationExtraHeight = 0
        autoHideGeneration &+= 1
        orderOut(nil)
    }
}
