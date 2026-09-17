import AppKit

extension WindowMouseInteractionDriver {
    func makePendingResizeCandidate(sample capturedSample: MousePointerSample? = nil) async -> PendingResizeCandidate? {
        guard getCurrentMouseManipulationKind() == .none else { return nil }
        let sample = capturedSample ?? MousePointerTracker.shared.currentSample
        // Capture the native window under the press, including an unfocused app.
        // Do not await AX here: a fast drag may already have moved its edge.
        let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let candidate = rows.compactMap { row -> (Window, CGFloat)? in
            guard let id = (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let window = Window.get(byId: id), window.parent is TilingContainer,
                  !window.isHiddenInCorner, window.nodeWorkspace?.isVisible == true,
                  let rect = window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect,
                  sample.point.x >= rect.minX - 8, sample.point.x <= rect.maxX + 8,
                  sample.point.y >= rect.minY - 8, sample.point.y <= rect.maxY + 8,
                  resizeGestureCandidateEdges(mouse: sample.point, rect: rect).hasAny
            else { return nil }
            let distance = min(abs(sample.point.x - rect.minX), abs(sample.point.x - rect.maxX),
                abs(sample.point.y - rect.minY), abs(sample.point.y - rect.maxY))
            return (window, distance)
        }.min { $0.1 < $1.1 }?.0
        guard let window = candidate,
              let observedRect = window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect
        else { return nil }
        let baseRect = window.lastAppliedLayoutPhysicalRect ?? observedRect
        let edges = resizeGestureCandidateEdges(mouse: sample.point, rect: observedRect)
        guard edges.hasAny else { return nil }
        return PendingResizeCandidate(
            windowId: window.windowId,
            baseRect: baseRect,
            observedRect: observedRect,
            edges: edges,
            mouseSample: sample,
        )
    }

    func cachedResizeCandidateIsViable(window: Window, sample: MousePointerSample) -> Bool {
        guard let cachedRect = window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect else { return true }
        return resizeGestureCandidateEdges(mouse: sample.point, rect: cachedRect).hasAny
    }
}
