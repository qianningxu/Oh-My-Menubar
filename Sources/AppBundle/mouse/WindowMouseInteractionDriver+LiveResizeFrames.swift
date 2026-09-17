import AppKit

private let liveResizeDrainPollNanoseconds: UInt64 = 4_000_000
private let liveResizeDrainPollLimit = 120

extension WindowMouseInteractionDriver {
    /// Keep exactly one AX write in flight for each native window and replace
    /// its queued successor with the newest frame. Cancelling every submitted
    /// write can starve a slower app for the whole gesture.
    func enqueueLiveResizeFrame(window: Window, frame: Rect) {
        let windowId = window.windowId
        if let pending = pendingLiveResizeFrames[windowId],
           !resizePreviewHasVisibleChange(from: pending, to: frame) {
            return
        }
        if let inFlight = liveResizeFramesInFlight[windowId],
           !resizePreviewHasVisibleChange(from: inFlight, to: frame) {
            pendingLiveResizeFrames.removeValue(forKey: windowId)
            return
        }

        pendingLiveResizeFrames[windowId] = frame
        if liveResizeFramesInFlight[windowId] == nil {
            beginNextLiveResizeFrameWrite(windowId: windowId)
        }
    }

    func cancelLiveResizeFrameWrites() {
        for id in liveResizeFramesInFlight.keys {
            (Window.get(byId: id) as? MacWindow)?.macApp.cancelLiveResizeFrame(id)
        }
        liveResizeFrameWriteGeneration &+= 1
        pendingLiveResizeFrames.removeAll()
        liveResizeFramesInFlight.removeAll()
    }

    func drainLiveResizeFrameWrites() async {
        let drainingGeneration = liveResizeFrameWriteGeneration
        for _ in 0 ..< liveResizeDrainPollLimit {
            guard drainingGeneration == liveResizeFrameWriteGeneration else { return }
            if pendingLiveResizeFrames.isEmpty, liveResizeFramesInFlight.isEmpty {
                return
            }
            try? await Task.sleep(nanoseconds: liveResizeDrainPollNanoseconds)
        }

        // A nonresponsive AX client must not leave stale queued geometry at
        // mouse-up. Cancel its old generation and apply only its newest target.
        var finalTargets = liveResizeFramesInFlight
        for (windowId, frame) in pendingLiveResizeFrames {
            finalTargets[windowId] = frame
        }
        liveResizeFrameWriteGeneration &+= 1
        pendingLiveResizeFrames.removeAll()
        liveResizeFramesInFlight.removeAll()

        for (windowId, requested) in finalTargets {
            guard let window = Window.get(byId: windowId) else { continue }
            if let macWindow = window as? MacWindow {
                try? await macWindow.setAxFrameBlocking(requested.topLeftCorner, requested.size)
                if let observed = try? await macWindow.getAxRect() {
                    publishLiveResizeFrame(window: window, frame: observed)
                    learnLiveResizeMinimumIfClamped(
                        window: window, requested: requested, observedSize: observed.size)
                }
            } else {
                window.setAxFrame(requested.topLeftCorner, requested.size)
                publishLiveResizeFrame(window: window, frame: requested)
            }
        }
    }

    private func beginNextLiveResizeFrameWrite(windowId: UInt32) {
        guard liveResizeFramesInFlight[windowId] == nil,
              let requested = pendingLiveResizeFrames.removeValue(forKey: windowId),
              let window = Window.get(byId: windowId)
        else { return }

        liveResizeFramesInFlight[windowId] = requested
        if resizeSession?.windowId != windowId {
            suppressPostDragAxObserverEvents(for: [windowId])
        }
        let generation = liveResizeFrameWriteGeneration
        if let macWindow = window as? MacWindow {
            macWindow.setLiveResizeFrame(
                from: window.lastKnownActualRect,
                to: requested
            ) { [weak self] observed in
                self?.nativeLiveResizeFrameDidApply(
                    windowId: windowId,
                    requested: requested,
                    observed: observed,
                    generation: generation)
            }
        } else {
            window.setAxFrame(requested.topLeftCorner, requested.size)
            nativeLiveResizeFrameDidApply(
                windowId: windowId,
                requested: requested,
                observed: requested,
                generation: generation)
        }
    }

    private func nativeLiveResizeFrameDidApply(
        windowId: UInt32,
        requested: Rect,
        observed: Rect?,
        generation: UInt64
    ) {
        guard generation == liveResizeFrameWriteGeneration,
              let inFlight = liveResizeFramesInFlight[windowId],
              !resizePreviewHasVisibleChange(from: inFlight, to: requested),
              let window = Window.get(byId: windowId)
        else { return }

        if let observed {
            publishLiveResizeFrame(window: window, frame: observed)
            learnLiveResizeMinimumIfClamped(
                window: window, requested: requested, observedSize: observed.size)
        }
        liveResizeFramesInFlight.removeValue(forKey: windowId)
        beginNextLiveResizeFrameWrite(windowId: windowId)
    }

    private func publishLiveResizeFrame(window: Window, frame: Rect) {
        window.lastKnownActualRect = frame

    }

    private func learnLiveResizeMinimumIfClamped(
        window: Window,
        requested: Rect,
        observedSize: CGSize
    ) {
        guard resizeSession?.windowId != window.windowId else { return }
        guard let minimum = learnedMinimumSizeAfterNativeClamp(
            current: window.minimumSize,
            requested: requested.size,
            observed: observedSize,
            tolerance: resizePreviewVisibleChangeThreshold
        ) else { return }
        window.minimumSize = minimum

        guard let sourceId = resizeSession?.windowId,
              let source = Window.get(byId: sourceId),
              let actualSourceRect = resizeGesture?.latestRect ?? source.lastKnownActualRect
        else { return }
        refreshResizePointerConstraints(window: source)
        updateResizePreviewIfNeeded(window: source, rect: actualSourceRect, force: true)
    }
}
