import CoreGraphics
import Common
import Darwin
import Foundation

private let mouseInteractionHiddenWindowAlpha: Float = 0
private let mouseInteractionVisibleWindowAlpha: Float = 1

@MainActor
final class WindowMouseInteractionOpacityController {
    static let shared = WindowMouseInteractionOpacityController()

    private let visibleWindowInventory: MouseInteractionVisibleWindowInventoryCache
    private var hiddenWindowIds: Set<UInt32> = []
    private var temporarilyMovedWindows: [UInt32: Rect] = [:]
    private var activeWindowId: UInt32?

    private init() {
        let inventory = MouseInteractionVisibleWindowInventoryCache(
            load: mouseInteractionVisibleWindowIdsToHide
        )
        visibleWindowInventory = inventory
        inventory.didRefresh = { [weak self] windowIds in
            self?.applyVisibleWindowInventory(windowIds)
        }
    }

    func prepareWindowInventory() {
        guard !isUnitTest else { return }
        visibleWindowInventory.refreshIfNeeded()
    }

    /// Use upstream's off-screen parking as well as opacity: foreign-window
    /// alpha alone does not reliably hide content at a moving preview's edges.
    func beginResize(activeWindowId: UInt32) {
        guard !isUnitTest, let source = Window.get(byId: activeWindowId),
              let workspace = source.nodeWorkspace else { return }
        visibleWindowInventory.invalidate()
        self.activeWindowId = nil
        let neighbors = workspace.rootTilingContainer.allLeafWindowsRecursive.filter {
            $0.windowId != activeWindowId && !$0.isHiddenInCorner
        }
        moveWindowsOutOfView(windowsToHide: neighbors, activeWindowId: activeWindowId,
            hidesPassiveTabGroupChrome: true)
        applyHiddenWindowIds(Set(neighbors.map(\.windowId)), activeWindowId: activeWindowId)
    }

    func update(activeWindowId: UInt32, hidesPassiveTabGroupChrome: Bool) {
        guard !isUnitTest else { return }
        self.activeWindowId = activeWindowId
        let windowsToHide = mouseInteractionManagedWindowsToHide(activeWindowId: activeWindowId)
        var discoveredWindowIds = Set(windowsToHide.map(\.windowId))
        if let cachedWindowIds = visibleWindowInventory.freshWindowIds {
            discoveredWindowIds.formUnion(cachedWindowIds)
        }
        moveWindowsOutOfView(
            windowsToHide: windowsToHide,
            activeWindowId: activeWindowId,
            hidesPassiveTabGroupChrome: hidesPassiveTabGroupChrome,
        )
        applyHiddenWindowIds(discoveredWindowIds, activeWindowId: activeWindowId)
        visibleWindowInventory.refreshIfNeeded()
    }

    private func applyVisibleWindowInventory(_ windowIds: Set<UInt32>) {
        guard let activeWindowId else { return }
        applyHiddenWindowIds(windowIds, activeWindowId: activeWindowId)
    }

    private func applyHiddenWindowIds(_ discoveredWindowIds: Set<UInt32>, activeWindowId: UInt32) {
        let nextHiddenIds = nextMouseInteractionHiddenWindowIds(
            activeWindowId: activeWindowId,
            currentlyHidden: hiddenWindowIds,
            discovered: discoveredWindowIds,
        )
        setWindowListAlpha(
            windowIds: Array(hiddenWindowIds.subtracting(nextHiddenIds)),
            alpha: mouseInteractionVisibleWindowAlpha,
        )
        setWindowListAlpha(
            windowIds: Array(nextHiddenIds.subtracting(hiddenWindowIds)),
            alpha: mouseInteractionHiddenWindowAlpha,
        )
        hiddenWindowIds = nextHiddenIds
    }

    func commitResizePositions(windowIds: [UInt32]) {
        // These windows have already accepted their final positions under the
        // preview. Do not restore their pre-drag rectangles on reveal.
        for id in windowIds { temporarilyMovedWindows.removeValue(forKey: id) }
    }

    func restore() {
        activeWindowId = nil
        visibleWindowInventory.invalidate()
        if !hiddenWindowIds.isEmpty {
            setWindowListAlpha(windowIds: Array(hiddenWindowIds), alpha: mouseInteractionVisibleWindowAlpha)
        }
        hiddenWindowIds.removeAll()
        suppressPostDragAxObserverEvents(for: temporarilyMovedWindows.keys)
        for (windowId, rect) in temporarilyMovedWindows {
            guard let window = Window.get(byId: windowId) else { continue }
            window.lastKnownActualRect = rect
            window.setAxFrame(rect.topLeftCorner, rect.size)
        }
        temporarilyMovedWindows.removeAll()
        WindowTabStripPanelController.shared.clearHiddenPassiveTabGroupChrome()
    }

    func shouldSuppressObserverEvent(windowId: UInt32?) -> Bool {
        guard let windowId else { return false }
        return hiddenWindowIds.contains(windowId) || temporarilyMovedWindows.keys.contains(windowId)
    }

    private func moveWindowsOutOfView(
        windowsToHide: [Window],
        activeWindowId: UInt32,
        hidesPassiveTabGroupChrome: Bool
    ) {
        if hidesPassiveTabGroupChrome {
            WindowTabStripPanelController.shared.setHiddenPassiveTabGroupChrome(
                passiveTabGroupChromeIdsToHide(windows: windowsToHide, activeWindowId: activeWindowId)
            )
        } else {
            WindowTabStripPanelController.shared.clearHiddenPassiveTabGroupChrome()
        }
        let visibleIds = Set(windowsToHide.map(\.windowId))
        for staleId in temporarilyMovedWindows.keys where !visibleIds.contains(staleId) {
            guard let rect = temporarilyMovedWindows.removeValue(forKey: staleId),
                  let window = Window.get(byId: staleId)
            else { continue }
            window.lastKnownActualRect = rect
            window.setAxFrame(rect.topLeftCorner, rect.size)
        }
        for window in windowsToHide where temporarilyMovedWindows[window.windowId] == nil {
            guard let rect = window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect else { continue }
            temporarilyMovedWindows[window.windowId] = rect
            window.lastKnownActualRect = rect
            window.setAxFrame(mouseInteractionHiddenTopLeftCorner(for: rect), nil)
        }
    }
}

@MainActor
final class MouseInteractionVisibleWindowInventoryCache {
    typealias Load = @Sendable () -> Set<UInt32>
    typealias Now = @MainActor () -> TimeInterval
    typealias DidRefresh = @MainActor (Set<UInt32>) -> Void

    static let maximumSnapshotAge: TimeInterval = 0.5

    var didRefresh: DidRefresh?

    private let load: Load
    private let now: Now
    private var snapshot: (windowIds: Set<UInt32>, capturedAt: TimeInterval)?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0

    init(
        load: @escaping Load,
        now: @escaping Now = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.load = load
        self.now = now
    }

    var freshWindowIds: Set<UInt32>? {
        let currentTime = now()
        guard let snapshot,
              currentTime >= snapshot.capturedAt,
              currentTime - snapshot.capturedAt <= Self.maximumSnapshotAge
        else { return nil }
        return snapshot.windowIds
    }

    func refreshIfNeeded() {
        guard refreshTask == nil, freshWindowIds == nil else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let load = load
        refreshTask = Task { [weak self] in
            let windowIds = await Task.detached(priority: .userInitiated) {
                load()
            }.value
            guard !Task.isCancelled, let self, generation == self.refreshGeneration else { return }
            self.refreshTask = nil
            self.snapshot = (windowIds, self.now())
            self.didRefresh?(windowIds)
        }
    }

    func invalidate() {
        refreshGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        snapshot = nil
    }

    deinit {
        refreshTask?.cancel()
    }
}

func nextMouseInteractionHiddenWindowIds(
    activeWindowId: UInt32,
    currentlyHidden: Set<UInt32>,
    discovered: Set<UInt32>,
) -> Set<UInt32> {
    var result = discovered
    result.formUnion(currentlyHidden)
    result.remove(activeWindowId)
    return result
}

@MainActor
private func passiveTabGroupChromeIdsToHide(windows: [Window], activeWindowId: UInt32) -> Set<ObjectIdentifier> {
    let activeTabGroup = Window.get(byId: activeWindowId)?.nearestWindowTabGroup
    return Set(windows.compactMap { window in
        guard let tabGroup = window.nearestWindowTabGroup,
              tabGroup.usesWindowTabBehavior,
              tabGroup !== activeTabGroup
        else {
            return nil
        }
        return ObjectIdentifier(tabGroup)
    })
}

@MainActor
private func mouseInteractionManagedWindowsToHide(activeWindowId: UInt32) -> [Window] {
    MacWindow.allWindows.compactMap { window in
        guard window.windowId != activeWindowId,
              !window.isHiddenInCorner,
              window.nodeWorkspace?.isVisible == true
        else {
            return nil
        }
        return window
    }
}

private func mouseInteractionVisibleWindowIdsToHide() -> Set<UInt32> {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windowInfos = CGWindowListCopyWindowInfo(options, CGWindowID(0)) as? [[String: Any]] else {
        return []
    }

    let currentProcessId = ProcessInfo.processInfo.processIdentifier
    return Set(windowInfos.compactMap { info -> UInt32? in
        guard let windowId = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
              layer == 0,
              let ownerProcessId = (info[kCGWindowOwnerPID as String] as? NSNumber)?.intValue,
              ownerProcessId != currentProcessId,
              let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
              alpha > 0.01,
              let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
              bounds.width > 8,
              bounds.height > 8
        else {
            return nil
        }
        return windowId
    })
}

private func mouseInteractionHiddenTopLeftCorner(for rect: Rect) -> CGPoint {
    let monitorRect = rect.center.monitorApproximation.visibleRect
    return monitorRect.bottomRightCorner + CGPoint(x: 8, y: 8)
}

@MainActor
private func setWindowListAlpha(windowIds: [UInt32], alpha: Float) {
    guard !windowIds.isEmpty else { return }
    let skyLight = SLSWindowAlpha.shared
    if let setWindowListAlpha = skyLight.setWindowListAlpha {
        let ids = windowIds
        _ = ids.withUnsafeBufferPointer { buffer in
            setWindowListAlpha(skyLight.connectionId, buffer.baseAddress, Int32(buffer.count), alpha)
        }
        return
    }
    guard let setWindowAlpha = skyLight.setWindowAlpha else { return }
    for windowId in windowIds {
        _ = setWindowAlpha(skyLight.connectionId, windowId, alpha)
    }
}

@MainActor
private final class SLSWindowAlpha {
    static let shared = SLSWindowAlpha()

    typealias MainConnectionIdFunction = @convention(c) () -> Int32
    typealias SetWindowAlphaFunction = @convention(c) (Int32, UInt32, Float) -> CGError
    typealias SetWindowListAlphaFunction = @convention(c) (Int32, UnsafePointer<UInt32>?, Int32, Float) -> CGError

    let connectionId: Int32
    let setWindowAlpha: SetWindowAlphaFunction?
    let setWindowListAlpha: SetWindowListAlphaFunction?

    private init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            connectionId = 0
            setWindowAlpha = nil
            setWindowListAlpha = nil
            return
        }
        let mainConnection = dlsym(handle, "SLSMainConnectionID")
            .map { unsafeBitCast($0, to: MainConnectionIdFunction.self) }
        setWindowAlpha = dlsym(handle, "SLSSetWindowAlpha")
            .map { unsafeBitCast($0, to: SetWindowAlphaFunction.self) }
        setWindowListAlpha = dlsym(handle, "SLSSetWindowListAlpha")
            .map { unsafeBitCast($0, to: SetWindowListAlphaFunction.self) }
        connectionId = mainConnection?() ?? 0
    }
}
