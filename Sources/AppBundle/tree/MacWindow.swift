import AppKit
import Common

func shouldRaiseNewlyDetectedDialog(
    isStartup: Bool,
    wasRestored: Bool,
    wasDetectedAsDialog: Bool,
    appIsActive: Bool,
    appWasFrontmostWhenDetected: Bool,
) -> Bool {
    !isStartup && !wasRestored && wasDetectedAsDialog && (appIsActive || appWasFrontmostWhenDetected)
}

@MainActor
final class NewlyDetectedDialogRaiseQueue {
    private var entries: [(windowId: UInt32, action: () -> Void)] = []

    func schedule(windowId: UInt32, action: @escaping () -> Void) {
        entries.removeAll { $0.windowId == windowId }
        entries.append((windowId, action))
    }

    func drain() {
        let pendingEntries = entries
        entries.removeAll()
        for entry in pendingEntries {
            entry.action()
        }
    }
}

@MainActor
private let newlyDetectedDialogRaiseQueue = NewlyDetectedDialogRaiseQueue()

@MainActor
func raiseNewlyDetectedDialogsAfterFocusSync() {
    newlyDetectedDialogRaiseQueue.drain()
}

@MainActor
func focusNewlyDetectedDialog(_ window: Window) {
    guard window.isFloating,
          window.visualWorkspace?.isVisible == true,
          window.focusWindow()
    else { return }
    // Keep logical and native focus aligned so the next refresh cannot put
    // the previous tiled window back above this newly opened dialog.
    window.nativeFocus()
}

final class MacWindow: Window {
    let macApp: MacApp
    private var prevUnhiddenProportionalPositionInsideWorkspaceRect: CGPoint?
    private var hiddenInCorner: OptimalHideCorner?

    @MainActor
    private init(_ id: UInt32, _ actor: MacApp, lastFloatingSize: CGSize?, parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, index: Int) {
        self.macApp = actor
        super.init(id: id, actor, lastFloatingSize: lastFloatingSize, parent: parent, adaptiveWeight: adaptiveWeight, index: index)
    }

    @MainActor static var allWindowsMap: [UInt32: MacWindow] = [:]
    @MainActor static var allWindows: [MacWindow] { Array(allWindowsMap.values) }

    @MainActor
    @discardableResult
    static func getOrRegister(windowId: UInt32, macApp: MacApp) async throws -> MacWindow? {
        if let existing = allWindowsMap[windowId] {
            _ = try await existing.getAxRect()
            return existing
        }
        // NSRunningApplication.isActive can lag behind an app opening a new
        // dialog. Capture the actual frontmost process before the AX awaits.
        let appWasFrontmostWhenDetected = NSWorkspace.shared.frontmostApplication?.processIdentifier == macApp.pid
        let rect = try await macApp.getAxRect(windowId)
        let targetWorkspace = targetWorkspaceForNewWindow(
            isStartup: isStartup,
            windowRect: rect,
            focusedWorkspace: focus.workspace,
        )
        let data = try await unbindAndGetBindingDataForNewWindow(
            windowId,
            macApp,
            targetWorkspace,
            window: nil,
        )
        let wasDetectedAsDialog = data.parent is Workspace || data.parent is GlobalFloatingWindowsContainer

        // atomic synchronous section
        if let existing = allWindowsMap[windowId] { return existing }
        let window = MacWindow(windowId, macApp, lastFloatingSize: rect?.size, parent: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
        window.lastKnownActualRect = rect
        allWindowsMap[windowId] = window

        try await debugWindowsIfRecording(window)
        let didRestorePersistedFrozenWorld = try await restorePersistedFrozenWorldIfNeeded(newlyDetectedWindow: window)
        let didRestoreClosedWindowsCache = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window)
        if !didRestorePersistedFrozenWorld && !didRestoreClosedWindowsCache {
            try await tryOnWindowDetected(window)
        }
        if shouldRaiseNewlyDetectedDialog(
            isStartup: isStartup,
            wasRestored: didRestorePersistedFrozenWorld || didRestoreClosedWindowsCache,
            wasDetectedAsDialog: wasDetectedAsDialog,
            appIsActive: macApp.nsApp.isActive,
            appWasFrontmostWhenDetected: appWasFrontmostWhenDetected,
        ) {
            newlyDetectedDialogRaiseQueue.schedule(windowId: windowId) { [weak macApp] in
                guard let macApp,
                      !macApp.nsApp.isTerminated,
                      let dialog = MacWindow.allWindowsMap[windowId]
                else { return }
                focusNewlyDetectedDialog(dialog)
            }
        }
        return window
    }

    // var description: String {
    //     let description = [
    //         ("title", title),
    //         ("role", axWindow.get(Ax.roleAttr)),
    //         ("subrole", axWindow.get(Ax.subroleAttr)),
    //         ("identifier", axWindow.get(Ax.identifierAttr)),
    //         ("modal", axWindow.get(Ax.modalAttr).map { String($0) } ?? ""),
    //         ("windowId", String(windowId)),
    //     ].map { "\($0.0): '\(String(describing: $0.1))'" }.joined(separator: ", ")
    //     return "Window(\(description))"
    // }

    func isWindowHeuristic(_ windowLevel: MacOsWindowLevel?) async throws -> Bool { // todo cache
        try await macApp.isWindowHeuristic(windowId, windowLevel)
    }

    func isDialogHeuristic(_ windowLevel: MacOsWindowLevel?) async throws -> Bool { // todo cache
        try await macApp.isDialogHeuristic(windowId, windowLevel)
    }

    func dumpAxInfo() async throws -> [String: Json] {
        try await macApp.dumpWindowAxInfo(windowId: windowId)
    }

    func setNativeFullscreen(_ value: Bool) {
        macApp.setNativeFullscreen(windowId, value)
    }

    func setNativeMinimized(_ value: Bool) {
        macApp.setNativeMinimized(windowId, value)
    }

    // skipClosedWindowsCache is an optimization when it's definitely not necessary to cache closed window.
    //                        If you are unsure, it's better to pass `false`
    @MainActor
    func garbageCollect(skipClosedWindowsCache: Bool) {
        if MacWindow.allWindowsMap.removeValue(forKey: windowId) == nil {
            return
        }
        if !skipClosedWindowsCache { cacheClosedWindowIfNeeded() }
        let workspaceToClose = workspaceToCloseAfterClosingLastWindow(self)
        let parent = unbindFromParent().parent
        let deadWindowWorkspace = parent.nodeWorkspace
        let currentFocus = focus
        let previousFocus = prevFocus
        let previousPreviousFocus = prevPrevFocus
        let refreshSnapshot = refreshSessionFocusSnapshot
        let refreshSnapshotCloseFallback = refreshSnapshot?.fallbackWhenFocusedWindowCloses?.liveOrNil
        let refreshSnapshotPreviousFocus = refreshSessionFocusSnapshot?.prevFocus?.liveOrNil
        let refreshSnapshotPreviousPreviousFocus = refreshSessionFocusSnapshot?.prevPrevFocus?.liveOrNil
        debugFocusLog(
            "MacWindow.garbageCollect closing=\(windowId) currentFocus=\(debugDescribe(currentFocus)) prev=\(debugDescribe(previousFocus)) prevPrev=\(debugDescribe(previousPreviousFocus)) snapshot=\(debugDescribe(refreshSnapshot))"
        )
        if let replacementFocus = focusAfterWindowClosure(
            closingWindow: self,
            deadWindowWorkspace: deadWindowWorkspace,
            currentFocus: currentFocus,
            previousFocus: previousFocus,
            previousPreviousFocus: previousPreviousFocus,
            refreshSnapshotCloseFallback: refreshSnapshotCloseFallback,
            refreshSnapshotPreviousFocus: refreshSnapshotPreviousFocus,
            refreshSnapshotPreviousPreviousFocus: refreshSnapshotPreviousPreviousFocus,
            previousFocusedWorkspace: prevFocusedWorkspace,
            previousFocusedWorkspaceDate: prevFocusedWorkspaceDate,
        ) {
            switch parent.cases {
                case .tilingContainer, .workspace, .macosHiddenAppsWindowsContainer, .macosFullscreenWindowsContainer:
                    debugFocusLog("MacWindow.garbageCollect replacement closing=\(windowId) replacement=\(debugDescribe(replacementFocus))")
                    _ = setFocus(to: replacementFocus)
                    if replacementFocus.windowOrNil != currentFocus.windowOrNil {
                        replacementFocus.windowOrNil?.nativeFocus()
                    }
                case .macosPopupWindowsContainer, .macosMinimizedWindowsContainer:
                    break // Don't switch back on popup destruction
            }
        }
        closeWorkspaceIfEmptiedByLastWindowClosure(workspaceToClose)
    }

    @MainActor override var title: String { get async throws { try await macApp.getAxTitle(windowId) ?? "" } }
    @MainActor override var isMacosFullscreen: Bool { get async throws { try await macApp.isMacosNativeFullscreen(windowId) == true } }
    @MainActor override var isMacosMinimized: Bool { get async throws { try await macApp.isMacosNativeMinimized(windowId) == true } }

    @MainActor
    override func nativeFocus() {
        macApp.nativeFocus(windowId)
    }

    @MainActor
    func requestCloseAndWait(timeout: TimeInterval = 1.5) async -> Bool {
        guard (try? await macApp.pressCloseButton(windowId)) == true else {
            return await garbageCollectIfNoLongerAccessible()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? await macApp.containsAxWindow(windowId)) == false {
                garbageCollect(skipClosedWindowsCache: true)
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    /// Some apps leave an AX window identifier behind after their last real
    /// window has gone away. A missing close button must not keep that ghost
    /// entry alive in a tab, but an unavailable AX query remains inconclusive.
    @MainActor
    private func garbageCollectIfNoLongerAccessible() async -> Bool {
        let isStillExposed = try? await macApp.containsAxWindow(windowId)
        guard shouldGarbageCollectAfterFailedClose(isWindowStillExposed: isStillExposed) else {
            return false
        }
        garbageCollect(skipClosedWindowsCache: true)
        return true
    }

    override func closeAxWindow() {
        garbageCollect(skipClosedWindowsCache: true)
        macApp.closeAndUnregisterAxWindow(windowId)
    }

    // todo it's part of the window layout and should be moved to layoutRecursive.swift
    @MainActor
    func hideInCorner(_ corner: OptimalHideCorner, force: Bool = false) async throws {
        try checkCancellation()
        if !force, isHiddenInCorner, hiddenInCorner == corner {
            return
        }
        guard let nodeMonitor else { return }
        var savedPosition = prevUnhiddenProportionalPositionInsideWorkspaceRect
        // Don't accidentally override prevUnhiddenEmulationPosition in case of subsequent `hideInCorner` calls
        if !isHiddenInCorner {
            guard let windowRect = try await getAxRect() else { return }
            try checkCancellation()
            // Check for isHiddenInCorner for the second time because of the suspension point above
            if !isHiddenInCorner {
                let topLeftCorner = windowRect.topLeftCorner
                let monitorRect = windowRect.center.monitorApproximation.rect // Similar to layoutFloatingWindow. Non idempotent
                let absolutePoint = topLeftCorner - monitorRect.topLeftCorner
                savedPosition =
                    CGPoint(x: absolutePoint.x / monitorRect.width, y: absolutePoint.y / monitorRect.height)
            }
        }
        let p: CGPoint
        switch corner {
            case .bottomLeftCorner:
                guard let s = try await getAxSize() else { fallthrough }
                try checkCancellation()
                // Zoom will jump off if you do one pixel offset https://github.com/nikitabobko/WinMux/issues/527
                // todo this ad hoc won't be necessary once I implement optimization suggested by Zalim
                let onePixelOffset = macApp.appId == .zoom ? .zero : CGPoint(x: 1, y: -1)
                p = nodeMonitor.visibleRect.bottomLeftCorner + onePixelOffset + CGPoint(x: -s.width, y: 0)
            case .bottomRightCorner:
                // Zoom will jump off if you do one pixel offset https://github.com/nikitabobko/WinMux/issues/527
                // todo this ad hoc won't be necessary once I implement optimization suggested by Zalim
                let onePixelOffset = macApp.appId == .zoom ? .zero : CGPoint(x: 1, y: 1)
                p = nodeMonitor.visibleRect.bottomRightCorner - onePixelOffset
        }
        try checkCancellation()
        // Commit hidden state only with the matching frame write. A cancelled
        // layout must not leave a visible window marked hidden, or hide a
        // window after a newer workspace activation has restored it.
        prevUnhiddenProportionalPositionInsideWorkspaceRect = savedPosition
        lastAppliedLayoutPhysicalRect = nil
        lastAppliedLayoutVirtualRect = nil
        setAxFrame(p, nil)
        hiddenInCorner = corner
    }

    @MainActor
    func unhideFromCorner(restoringTiledOverlay: Bool = false) {
        guard let prevUnhiddenProportionalPositionInsideWorkspaceRect else { return }
        guard let nodeWorkspace else { return } // hiding only makes sense for workspace windows
        guard let parent else { return }

        func restoreToSavedWorkspacePosition() {
            let workspaceRect = nodeWorkspace.workspaceMonitor.rect
            var newX = workspaceRect.topLeftX + workspaceRect.width * prevUnhiddenProportionalPositionInsideWorkspaceRect.x
            var newY = workspaceRect.topLeftY + workspaceRect.height * prevUnhiddenProportionalPositionInsideWorkspaceRect.y
            let windowWidth = lastKnownActualRect?.width ?? lastFloatingSize?.width ?? 0
            let windowHeight = lastKnownActualRect?.height ?? lastFloatingSize?.height ?? 0
            newX = newX.coerce(in: workspaceRect.minX ... max(workspaceRect.minX, workspaceRect.maxX - windowWidth))
            newY = newY.coerce(in: workspaceRect.minY ... max(workspaceRect.minY, workspaceRect.maxY - windowHeight))
            setAxFrame(CGPoint(x: newX, y: newY), nil)
        }

        switch getChildParentRelation(child: self, parent: parent) {
            // Just a small optimization to avoid unnecessary AX calls for non floating windows
            // Tiling windows should be unhidden with layoutRecursive anyway
            case .floatingWindow:
                restoreToSavedWorkspacePosition()
            case .tiling where restoringTiledOverlay:
                restoreToSavedWorkspacePosition()
            case .macosNativeFullscreenWindow, .macosNativeHiddenAppWindow, .macosNativeMinimizedWindow,
                 .macosPopupWindow, .tiling, .rootTilingContainer, .shimContainerRelation: break
        }

        // Restoring a tiled window requires a real write, even when its
        // requested tile frame matches the frame cached before hiding.
        lastAppliedLayoutPhysicalRect = nil
        lastAppliedLayoutVirtualRect = nil
        self.prevUnhiddenProportionalPositionInsideWorkspaceRect = nil
        self.hiddenInCorner = nil
    }

    override var isHiddenInCorner: Bool {
        prevUnhiddenProportionalPositionInsideWorkspaceRect != nil
    }

    override func getAxSize() async throws -> CGSize? {
        try await macApp.getAxSize(windowId)
    }

    override func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        macApp.setAxFrame(windowId, topLeft, size)
    }

    func setAxFrameBlocking(_ topLeft: CGPoint?, _ size: CGSize?) async throws {
        try await macApp.setAxFrameBlocking(windowId, topLeft, size)
    }

    func setLiveResizeFrame(
        from current: Rect?,
        to requested: Rect,
        completion: @MainActor @Sendable @escaping (Rect?) -> Void
    ) {
        macApp.setLiveResizeFrame(windowId, from: current, to: requested, completion: completion)
    }

    override func getAxRect() async throws -> Rect? {
        let rect = try await macApp.getAxRect(windowId)
        let windowId = self.windowId
        await MainActor.run {
            Window.get(byId: windowId)?.lastKnownActualRect = rect
        }
        return rect
    }
}

func shouldGarbageCollectAfterFailedClose(isWindowStillExposed: Bool?) -> Bool {
    isWindowStillExposed == false
}
