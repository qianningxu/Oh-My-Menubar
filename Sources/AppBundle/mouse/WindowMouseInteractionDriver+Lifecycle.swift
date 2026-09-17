import AppKit

extension WindowMouseInteractionDriver {
    func noteGlobalDragActivity() {
        // AX resize notifications can arrive late or depend on app focus. Once
        // the pressed window actually changes size, start from the captured press.
        if resizeSession == nil, moveSession == nil, getCurrentMouseManipulationKind() == .none,
           isLeftMouseButtonDown, let candidate = pendingResizeCandidate,
           let rows = CGWindowListCopyWindowInfo(.optionIncludingWindow, candidate.windowId) as? [[String: Any]],
           let bounds = rows.first?[kCGWindowBounds as String] as? NSDictionary,
           let frame = CGRect(dictionaryRepresentation: bounds),
           abs(frame.width - candidate.observedRect.width) >= 1 || abs(frame.height - candidate.observedRect.height) >= 1 {
            startResize(windowId: candidate.windowId)
        }
        if moveSession != nil {
            renderMoveFrame(force: false)
        }
        if resizeSession != nil {
            sampleResizeFrame(force: false)
        }
    }

    func flushBeforeMouseUp() async {
        if moveSession != nil {
            renderMoveFrame(force: true)
        }
        guard let resizeSession, flushingResizeSession != resizeSession else { return }
        flushingResizeSession = resizeSession
        defer {
            if flushingResizeSession == resizeSession { flushingResizeSession = nil }
            finishResizeFlush(session: resizeSession)
        }
        guard let window = Window.get(byId: resizeSession.windowId) else { return }
        guard let rect = await finalResizeRect(for: resizeSession, window: window) else { return }
        guard self.resizeSession == resizeSession else { return }
        let pointerRect = resizeGesture?.predictedRect(mouse: MousePointerTracker.shared.currentSample.point) ?? rect
        let releaseRect = resizeProposal(window, rect: pointerRect)?.rect ?? rect
        updateResizePreviewIfNeeded(window: window, rect: releaseRect, force: true)
        enqueueLiveResizeFrame(window: window, frame: releaseRect)
        await drainLiveResizeFrameWrites()
        guard self.resizeSession == resizeSession else { return }
        let finalRect = resizeProposal(window, rect: window.lastKnownActualRect ?? rect)?.rect ?? rect
        applyResizeWithMouse(window, rect: finalRect)
        // Keep the preview and hidden native neighbors until every final AX write completes.
        if let workspace = window.nodeWorkspace,
           let weights = proposedResizeWeightMap(window, rect: finalRect) {
            let items = windowResizePreviewItems(in: workspace, weightMap: weights,
                excludingActiveWindowId: window.windowId)
            for item in items {
                guard let neighbor = Window.get(byId: item.id), !neighbor.isFloating else { continue }
                let target = liveResizeWindowContentRect(
                    groupRect: item.frame.monitorFrameNormalized(), isTabGroup: item.isTabGroup)
                enqueueLiveResizeFrame(window: neighbor, frame: target)
            }
            await drainLiveResizeFrameWrites()
            guard self.resizeSession == resizeSession else { return }
            WindowMouseInteractionOpacityController.shared.commitResizePositions(windowIds: items.map(\.id))
        }
        guard self.resizeSession == resizeSession else { return }
        WindowMouseInteractionOpacityController.shared.restore()
    }

    func stop() {
        logWindowDragLive("driver.stop moveSession=\(String(describing: moveSession)) resizeSession=\(String(describing: resizeSession)) manipulated=\(currentlyManipulatedWithMouseWindowId?.description ?? "nil") kind=\(getCurrentMouseManipulationKind()) mouseDown=\(isLeftMouseButtonDown)")
        DisplayRefreshDriver.shared.remove(owner: self)
        moveSession = nil
        resizeSession = nil
        flushingResizeSession = nil
        dragSourcePreviewState = nil
        pendingResizeCandidate = nil
        cancelLiveResizeFrameWrites()
        clearResizePointerConstraints()
        resetResizeTrackingState()
        WindowResizePreviewPanel.shared.endStableFrame()
        WindowResizePreviewPanel.shared.hide(reason: "driver.stop")
        WindowMouseInteractionOpacityController.shared.restore()
        WindowTabStripPanelController.shared.showChromeDuringMouseInteraction()
    }

    func finishResizeFlush(session: ResizeSession) {
        guard resizeSession == session else { return }
        if resizeSession == session {
            resizeSession = nil
        }
        pendingResizeCandidate = nil
        cancelLiveResizeFrameWrites()
        clearResizePointerConstraints()
        resetResizeTrackingState()
        WindowResizePreviewPanel.shared.endStableFrame()
        WindowResizePreviewPanel.shared.hide(reason: "driver.finishResizeFlush")
    }
}
