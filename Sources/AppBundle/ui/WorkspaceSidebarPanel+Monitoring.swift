import AppKit

let workspaceSidebarWorkspaceActivityRevealDuration: TimeInterval = 1.25

extension WorkspaceSidebarPanel {
    static func updateHoverStateForVisiblePanels() {
        for panel in allPanels {
            panel.updateHoverStateFromMousePosition()
        }
    }

    func startHoverMonitoring() {
        isHoverMonitoring = true
        updateHoverStateFromMousePosition()
    }

    func stopHoverMonitoring() {
        isHoverMonitoring = false
    }

    func scheduleHoverStateUpdate(at deadline: Date) {
        let delay = max(0, deadline.timeIntervalSinceNow)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isHoverMonitoring else { return }
            guard Date() >= deadline else {
                self.scheduleHoverStateUpdate(at: deadline)
                return
            }
            self.updateHoverStateFromMousePosition()
        }
    }

    func updateHoverStateFromMousePosition() {
        updateMousePassthrough()
        updateAutoHideVisibility(at: NSEvent.mouseLocation)
        setHovering(isMouseInsideHoverRegion())
    }

    func updateAutoHideVisibility(at pointer: CGPoint) {
        guard viewModel.isWorkspaceSidebarAutoHideEnabled else {
            showProjectBar()
            return
        }
        guard let screen = workspaceSidebarPanelScreen(),
              let layout = currentSidebarPanelLayout()
        else {
            hideProjectBarImmediately()
            return
        }
        let shouldShow = workspaceSidebarAutoHideShouldShow(
            isCurrentlyVisible: isVisible,
            pointer: pointer,
            screenFrame: screen.frame,
            barFrame: layout.frame,
            isInteractionLocked: shouldLockExpansionForSidebarDrag()
        )
        if shouldShow {
            showProjectBar(layout: layout)
        } else {
            scheduleProjectBarHide()
        }
    }

    func revealProjectBarFromCommand() {
        commandExpansionLocksCollapse = true
        showProjectBar()
    }

    func revealProjectBarForWorkspaceActivity() {
        guard viewModel.isWorkspaceSidebarAutoHideEnabled else { return }
        workspaceActivityRevealUntil = Date().addingTimeInterval(
            workspaceSidebarWorkspaceActivityRevealDuration
        )
        showProjectBar()
        scheduleHoverStateUpdate(at: workspaceActivityRevealUntil)
    }

    func revealProjectBarFromOptionKey() {
        guard viewModel.isWorkspaceSidebarAutoHideEnabled else { return }
        optionKeyExpansionLocksCollapse = true
        showProjectBar()
    }

    func releaseOptionKeyProjectBarReveal() {
        guard optionKeyExpansionLocksCollapse else { return }
        optionKeyExpansionLocksCollapse = false
        updateAutoHideVisibility(at: NSEvent.mouseLocation)
    }

    func releaseCommandProjectBarReveal() {
        commandExpansionLocksCollapse = false
        updateAutoHideVisibility(at: NSEvent.mouseLocation)
    }

    private func showProjectBar(layout: WorkspaceSidebarPanelLayout? = nil) {
        autoHideGeneration &+= 1
        guard let layout = layout ?? currentSidebarPanelLayout() else { return }
        if frame != layout.frame {
            setFrame(layout.frame, display: true, animate: false)
        }
        viewModel.workspaceSidebarVisibleWidth = layout.frame.width
        viewModel.isWorkspaceSidebarExpanded = true
        updateProjectPresentationLayer()
        ignoresMouseEvents = false
        orderFrontRegardless()
        isHoverMonitoring = viewModel.isWorkspaceSidebarAutoHideEnabled
    }

    private func scheduleProjectBarHide() {
        autoHideGeneration &+= 1
        let generation = autoHideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) { [weak self] in
            guard let self, self.autoHideGeneration == generation,
                  self.viewModel.isWorkspaceSidebarAutoHideEnabled,
                  let screen = self.workspaceSidebarPanelScreen(),
                  let layout = self.currentSidebarPanelLayout(),
                  !workspaceSidebarAutoHideShouldShow(
                      isCurrentlyVisible: self.isVisible,
                      pointer: NSEvent.mouseLocation,
                      screenFrame: screen.frame,
                      barFrame: layout.frame,
                      isInteractionLocked: self.shouldLockExpansionForSidebarDrag()
                  )
            else { return }
            self.hideProjectBarImmediately()
        }
    }

    private func hideProjectBarImmediately() {
        autoHideGeneration &+= 1
        isHoverMonitoring = false
        viewModel.workspaceSidebarVisibleWidth = 0
        viewModel.isWorkspaceSidebarExpanded = false
        orderOut(nil)
    }

    func updateProjectPresentationLayer() {
        applyWinMuxLayer(.menuBarSurface)
    }
}

func workspaceSidebarAutoHideShouldShow(
    isCurrentlyVisible: Bool,
    pointer: CGPoint,
    screenFrame: NSRect,
    barFrame: NSRect,
    isInteractionLocked: Bool,
) -> Bool {
    let revealHeight = WinMuxSpacing.hairline
    let revealRegion = NSRect(
        x: screenFrame.minX,
        y: screenFrame.maxY - revealHeight,
        width: screenFrame.width,
        height: revealHeight
    )
    if revealRegion.contains(pointer) { return true }
    guard isCurrentlyVisible else { return false }
    if isInteractionLocked { return true }
    let keepVisibleRegion = NSRect(
        x: screenFrame.minX,
        y: min(barFrame.minY, screenFrame.maxY - 1),
        width: screenFrame.width,
        height: max(screenFrame.maxY - min(barFrame.minY, screenFrame.maxY - 1), 1)
    )
    return keepVisibleRegion.contains(pointer)
}
