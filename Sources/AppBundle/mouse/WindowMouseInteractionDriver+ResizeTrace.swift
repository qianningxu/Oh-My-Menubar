import AppKit

extension WindowMouseInteractionDriver {
    /// Opt-in release-build diagnostics; no window titles or content are recorded.
    func traceResizeFrame(window: Window) {
        guard FileManager.default.fileExists(atPath: "/tmp/winmux-resize-trace.enabled"),
              let workspace = window.nodeWorkspace else { return }
        let proposed = resizeGesture?.latestRect ?? window.lastKnownActualRect
        let proposal = proposed.flatMap { resizeProposal(window, rect: $0) }
        let items = windowResizePreviewItems(in: workspace,
            weightMap: proposal?.weights ?? WindowResizePreviewWeightMap(), excludingActiveWindowId: nil)
            .filter { Window.get(byId: $0.id)?.isFloating != true }
        let ids = [window.windowId] + items.map(\.id)
        let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let frames = rows.filter { ids.contains(($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0) }
            .map { "\($0[kCGWindowNumber as String]!)=\($0[kCGWindowBounds as String]!)" }
        let minimums = workspace.rootTilingContainer.allLeafWindowsRecursive.map { "\($0.windowId):\(String(describing: $0.minimumSize))" }
        let line = "t=\(ProcessInfo.processInfo.systemUptime) presentation=preview raw=\(String(describing: ResizePointerConstraintGate.shared.sample.raw)) constrained=\(String(describing: ResizePointerConstraintGate.shared.sample.constrained)) source=\(window.windowId) requested=\(String(describing: proposed)) solved=\(String(describing: proposal?.rect)) previews=\(items.map { "\($0.id):\($0.frame)" }) observed=\(frames) minimums=\(minimums) generation=\(liveResizeFrameWriteGeneration) pending=\(pendingLiveResizeFrames) inFlight=\(liveResizeFramesInFlight)\n"
        let url = URL(fileURLWithPath: "/tmp/winmux-resize-trace.log")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let file = try? FileHandle(forWritingTo: url) {
            defer { try? file.close() }
            _ = try? file.seekToEnd()
            try? file.write(contentsOf: Data(line.utf8))
        }
    }
}
