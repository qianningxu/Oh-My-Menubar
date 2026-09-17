import AppKit

extension WindowMouseInteractionDriver {
    func startResize(windowId: UInt32) {
        guard isLeftMouseButtonDown, flushingResizeSession == nil else { return }
        let session = resizeSession.flatMap { $0.windowId == windowId ? $0 : nil } ?? ResizeSession(windowId: windowId)
        let isNewSession = resizeSession != session
        logWindowDragLive("resize.start window=\(windowId) isNewSession=\(isNewSession) existingSession=\(String(describing: resizeSession)) mouseDown=\(isLeftMouseButtonDown) kind=\(getCurrentMouseManipulationKind())")
        if isNewSession, let window = Window.get(byId: windowId), window.lastAppliedLayoutPhysicalRect == nil {
            if let candidate = pendingResizeCandidate, candidate.windowId == windowId {
                window.lastAppliedLayoutPhysicalRect = candidate.baseRect
            } else if let anchor = draggedWindowAnchorRect(for: windowId) {
                window.lastAppliedLayoutPhysicalRect = liveResizeWindowContentRect(
                    groupRect: anchor, isTabGroup: getCurrentMouseDragSubject() == .group)
            }
        }
        if isNewSession {
            cancelLiveResizeFrameWrites()
            clearResizePointerConstraints()
        }
        setCurrentMouseManipulationKind(.resize)
        WindowTabStripPanelController.shared.setIgnoresMouseEvents(true)
        moveSession = nil
        dragSourcePreviewState = nil
        if isNewSession {
            resetResizeTrackingState()
            clearPendingWindowDragIntent()
        }
        resizeSession = session
        currentlyManipulatedWithMouseWindowId = windowId
        WindowMouseInteractionOpacityController.shared.beginResize(activeWindowId: windowId)
        configureResizeChrome(windowId: windowId)
        startDisplayLoop()
        sampleResizeFrame(force: true)
    }

    func configureResizeChrome(windowId: UInt32) {
        guard let window = Window.get(byId: windowId) else {
            logWindowDragLive("resize.configureChrome missing-window window=\(windowId)")
            WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction()
            return
        }
        WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction(showFrameOnly: false)
        if resizeGesture == nil {
            let sample = MousePointerTracker.shared.currentSample
            resizeGesture = makeResizeGesture(window: window, observedRect: window.lastKnownActualRect, sample: sample)
        }
        refreshResizePointerConstraints(window: window)
        guard let rect = resizeGesture?.predictedRect(mouse: MousePointerTracker.shared.currentSample.point) ??
            window.lastAppliedLayoutPhysicalRect ?? window.lastKnownActualRect
        else { return }
        beginStableResizePreviewFrame(for: window)
        updateResizePreviewIfNeeded(window: window, rect: rect, force: true)
    }

    func resetResizeTrackingState() {
        resizeGesture = nil
        isResizeSampleInFlight = false
        isMouseUpResetScheduled = false
        lastRenderedResizePreviewRect = nil
    }
}
